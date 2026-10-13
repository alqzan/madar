import Foundation
import Observation
import SwiftData
import MadarData
import MadarCore
import MadarSnapshots
import WidgetKit
import MadarCommands
import MadarInbox
import MadarPrayer
import UIKit

typealias JSONValue = MadarData.JSONValue
struct AppUndoToken { let id: UUID; let expiresAt: Date }

@MainActor @Observable
final class AppSession {
    private(set) var container: ModelContainer
    let managedStore: ManagedDataStore?
    let snapshotStore: SnapshotStore
    private(set) var maintenanceInProgress = false
    private var pendingWrites = 0
    private var notificationStoreAccessSuspended = false
    var backupService: (any BackupUIService)?
    var syncService: (any SyncUIService)?
    var lockController: MadarLockController?
    weak var privacyPresenter: ScenePrivacyPresenter?
    private(set) var protectedDataAuthorized = false
    private(set) var notificationAuthorization = "unknown"
#if DEBUG
    var notificationTestResult = ""
#endif
    @ObservationIgnored weak var prayerNotifications: PrayerNotificationCoordinator?
    let schema: SettingsSchema
    var store: SettingsStore
    private(set) var values: [String: JSONValue] = [:]
    private(set) var undoToken: AppUndoToken?
    private(set) var undoMessage = ""
    var errorMessage: String?
    var onboardingComplete = false
    var selectedTab = "foundation"
    private(set) var prayerRevision = 0
    private(set) var prayerWriteInProgress = false
    var settingsQuery = ""
    private let bus: CommandBus
    private let commandAdapter: DurableCommandAdapter
    let pendingInbox: PendingInbox
    @ObservationIgnored private lazy var inboxDrainer = InboxDrainer(inbox: pendingInbox, bus: bus, generation: { [weak self] in
        guard let self else { throw DataError.invalidValue("session unavailable") }
        return try self.inboxGeneration()
    }, hasReceipt: { [weak self] id in
        guard let self else { throw DataError.invalidValue("session unavailable") }
        return try self.commandAdapter.hasReceipt(commandID: id)
    }, refresh: { [weak self] in
        guard let self else { throw DataError.invalidValue("session unavailable") }
        try self.reload(); try self.publishSnapshot()
        try (self.syncService as? AppSyncService)?.processLocalHistory()
        WidgetCenter.shared.reloadAllTimelines()
    }, shouldPause: { [weak self] in
        self?.maintenanceInProgress != false || !UIApplication.shared.isProtectedDataAvailable
    }, authorization: { [weak self] command in
        guard let self, self.lockController != nil else { return .init(status: .needsApp) }
        guard UIApplication.shared.isProtectedDataAvailable else { return .init(status: .needsUnlock) }
        // §16 authorize: prayer.log is blindWrite even with whole-app Face ID protection.
        // App-only settings never enter via transport, even if it claims source: app.
        if command.name == "prayer.log" { return nil }
        return self.lockController?.canPresent(.app) == true ? nil : .init(status: .needsUnlock)
    })
    private var expiryTask: Task<Void, Never>?

    static let supportedKeys = ["core.dayStart", "core.firstCalendar", "core.hijriSource", "core.hijriOffset", "core.weekStart", "core.theme", "core.numerals", "core.homeCity", "core.faceIDLock", "salah.askAfterAdhanMin", "salah.askReminder", "salah.liveActivity", "salah.showMosqueStreak", "salah.askHeart", "notif.thisDeviceReminders", "notif.quietAfterIsha", "notif.quietFrom"]

    init(container: ModelContainer, managedStore: ManagedDataStore? = nil, groupDirectory: URL? = nil) throws {
        self.container = container
        self.managedStore = managedStore
        guard let group = groupDirectory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { throw DataError.missingAppGroup }
        snapshotStore = SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
        pendingInbox = PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
        commandAdapter = DurableCommandAdapter(containerProvider: { try managedStore?.containerForTransaction() ?? container }, lockDirectory: managedStore?.commandLockURL.deletingLastPathComponent() ?? group, transactionClock: { _ in prayerUITestClock(.now) }, generationProvider: {
            if let managedStore { return managedStore.binding.generationID }
            return try PendingInbox(directory: group.appending(path: "PendingInbox")).currentGeneration()?.generationID
        })
        bus = CommandBus(adapter: commandAdapter)
        schema = try SettingsSchema.bundled()
        store = SettingsStore(context: container.mainContext, schema: schema)
        #if DEBUG
        try preparePrayerUITestTrackingStart()
        try preparePrayerStatisticsFixture()
        #endif
        try reload()
        let devices = try container.mainContext.fetch(FetchDescriptor<DeviceSetting>())
        onboardingComplete = devices.contains { $0.key == "sys.onboardingCompleted" && $0.valueJSON == Data("true".utf8) && $0.deletedAt == nil }
        try publishSnapshot()
    }

    func reload() throws {
        if let managedStore { try managedStore.refreshIfNeeded(); container = managedStore.container }
        store = SettingsStore(context: ModelContext(container), schema: schema)
        var current: [String: JSONValue] = [:]
        for item in schema.settings { current[item.key] = try store.value(for: item.key) }
        values = current
        prayerRevision &+= 1
    }
    func prayerSnapshot(at now: Date) throws -> PrayerSnapshot {
        _ = prayerRevision // Observation invalidates the derived view after a committed write.
        return try PrayerRepository(context: ModelContext(container)).snapshot(now: now)
    }
    func prayerNow(_ fallback: Date = .now) -> Date {
        return prayerUITestClock(fallback)
    }
    func recordPrayer(_ reference: PrayerReference, status: PrayerStoredStatus, fridayKind: FridayPrayerKind? = nil, completion: ((Bool) -> Void)? = nil) {
        guard [.jamaah, .alone, .missed].contains(status) else { completion?(false); return }
        let payload: MadarCore.JSONValue = .object([
            "dayKey": .string(reference.day.description),
            "prayer": .string(reference.prayer.rawValue),
            "status": .string(status.rawValue),
            "fridayKind": fridayKind.map { .string($0.rawValue) } ?? .null
        ])
        sendPrayerCommand(name: "prayer.log", payload: payload,
            undoMessage: status == .missed ? "سُجّلت فائتة · التراجع متاح لعشر دقائق" : "سُجّلت الصلاة · التراجع متاح لعشر دقائق", completion: completion)
    }
    func qiyamRequiresRestore(_ night: GregorianDay) throws -> Bool {
        try PrayerRepository(context: ModelContext(container)).nightRequiresRestore(night)
    }
    func recordQiyamNight(_ night: GregorianDay, rakaat: Int, witr: Bool, restoreDeleted: Bool = false, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.logQiyam", payload: .object([
            "nightKey": .string(night.description), "rakaat": .number(Double(rakaat)), "witr": .bool(witr), "restoreDeleted": .bool(restoreDeleted)
        ]), undoMessage: "حُفظ قيام الليلة · التراجع متاح لعشر دقائق", completion: completion)
    }
    func answerPrayerHeart(_ reference: PrayerReference, heart: PrayerHeart?, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.setHeart", payload: .object([
            "dayKey": .string(reference.day.description), "prayer": .string(reference.prayer.rawValue),
            "heart": heart.map { .string($0.rawValue) } ?? .null
        ]), undoMessage: "حُفظت إجابة القلب · التراجع متاح لعشر دقائق", completion: completion)
    }
    func makeUpPrayer(_ reference: PrayerReference, fridayKind: FridayPrayerKind? = nil) {
        let at = prayerNow()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: MadarCore.JSONValue = .object([
            "dayKey": .string(reference.day.description),
            "prayer": .string(reference.prayer.rawValue),
            "at": .string(formatter.string(from: at)),
            "fridayKind": fridayKind.map { .string($0.rawValue) } ?? .null
        ])
        sendPrayerCommand(name: "prayer.makeUp", payload: payload, undoMessage: "قُضيت الصلاة · التراجع متاح لعشر دقائق")
    }
    func resolvePrayerGap(_ resolutions: [PrayerGapResolution]) {
        guard !resolutions.isEmpty else { return }
        let values = resolutions.map { item in
            MadarCore.JSONValue.object([
                "dayKey": .string(item.reference.day.description),
                "prayer": .string(item.reference.prayer.rawValue),
                "status": .string(item.status.rawValue),
                "fridayKind": item.fridayKind.map { .string($0.rawValue) } ?? .null
            ])
        }
        sendPrayerCommand(name: "prayer.resolveGap", payload: .object(["resolutions": .array(values)]),
            undoMessage: "حُلّت الفترة · التراجع متاح لعشر دقائق")
    }
    private func sendPrayerCommand(name: String, payload: MadarCore.JSONValue, undoMessage: String, completion: ((Bool) -> Void)? = nil) {
        guard !prayerWriteInProgress, beginWrite() else { completion?(false); return }
        prayerWriteInProgress = true
        let now = prayerNow()
        Task {
            var succeeded = false
            defer { pendingWrites -= 1; prayerWriteInProgress = false; completion?(succeeded) }
            do {
                succeeded = try await withSerializedPrayerNotificationMutation {
                    let command = CommandEnvelope(name: name, payload: payload, source: .app, issuedAt: now)
                    let result = try await bus.execute(command, now: now)
                    guard result.status == .applied || result.status == .duplicate else {
                        errorMessage = prayerFailure(result.reason)
                        return false
                    }
                    try reload()
                    if let id = result.undoToken {
                        let context = ModelContext(container)
                        if let receipt = try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).first(where: { $0.commandID == id }),
                           let deadline = receipt.undoExpiresAt {
                            showUndo(AppUndoToken(id: id, expiresAt: deadline), message: undoMessage)
                        }
                    }
                    try publishSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                    return true
                }
            } catch {
                errorMessage = "لم يُسجّل التغيير. \(error.localizedDescription)"
            }
        }
    }
    private func prayerFailure(_ reason: String?) -> String {
        switch reason {
        case "futurePrayer": "لم يحن وقت الصلاة بعد."
        case "prayerWindowOpen": "لم ينته وقت الصلاة بعد؛ يمكنك تسجيلها عند انتهائه."
        case "unavailablePrayerTimes": "لا تتوفر مواقيت مؤكدة لهذا الفرض."
        case "beforeTrackingStart": "هذا اليوم يسبق بداية التسجيل."
        case "explicitRestoreRequired": "يتطلب هذا السجل استعادة صريحة."
        case "invalidRecord": "نوع الجمعة متاح لظهر الجمعة فقط."
        default: "لم تُسجّل الصلاة. حاول مرة أخرى."
        }
    }
    #if DEBUG
    private func preparePrayerStatisticsFixture() throws {
        guard ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil,
              ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_FIXTURE"] == "ratio26of30" else { return }
        let context = ModelContext(container)
        // Seed only once in an explicitly isolated DEBUG UI-test store. Values come
        // from the hand-authored §7.2 example, never from engine output.
        guard try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty else { return }
        for index in 0..<30 {
            let row = PrayerLog()
            row.dayKey = String(format: "2026-10-%02d", index / 5 + 1)
            row.prayer = Prayer.allCases[index % 5].rawValue
            row.status = index < 26 ? "jamaah" : index < 28 ? "qada" : "missed"
            row.tzID = "Asia/Riyadh"
            row.eventAt = try GregorianDay(row.dayKey).date(in: ActivePlace.riyadh.timeZone).addingTimeInterval(12 * 3600)
            row.source = "user"
            context.insert(row)
            if index >= 26 {
                let debt = QadaItem(); debt.originalDayKey = row.dayKey; debt.prayer = row.prayer
                if index < 28 { debt.madeUpAt = row.eventAt }
                context.insert(debt)
            }
        }
        try context.save()
    }
    private func preparePrayerUITestTrackingStart() throws {
        guard let raw = ProcessInfo.processInfo.environment["MADAR_UI_TRACKING_START"],
              let day = try? GregorianDay(raw) else { return }
        let context = ModelContext(container)
        let testStore = SettingsStore(context: context, schema: schema)
        try testStore.prepare(.object(["dayKey": .string(day.description), "edits": .number(0)]), for: "salah.trackingStart")
        try context.save()
    }
    #endif
    func string(_ key: String) -> String { if case .string(let v) = values[key] { v } else { "" } }
    func bool(_ key: String) -> Bool { if case .bool(let v) = values[key] { v } else { false } }
    func number(_ key: String) -> Double { if case .number(let v) = values[key] { v } else { 0 } }
    func open(_ url: URL) {
        let today = GregorianDay.containing(.now, in: activePlace.timeZone)
        let context = RouteContext(trackingStart: today.adding(days: -36500), today: today, settingsKeys: Set(Self.supportedKeys), availability: .m0)
        do {
            let route = try RouteRegistry.parse(url, context: context)
            guard url.host == "settings", route.room == .core else { throw CoreError.unavailableFeature }
            settingsQuery = try schema.definition(for: route.path[1]).title
            selectedTab = "customize"
        } catch { errorMessage = "هذا الرابط غير متاح في إصدار مدار الحالي." }
    }
    func set(_ value: JSONValue, key: String, completion: (() -> Void)? = nil) {
        if key == "core.faceIDLock", case .string(let raw) = value, let scope = MadarLockScope(rawValue: raw), let lockController {
            Task {
                do { try await lockController.changeScope(scope); completion?() }
                catch { errorMessage = "لم يتغيّر القفل. \(error.localizedDescription)" }
            }
            return
        }
        execute(name: "settings.set", values: [key: value], message: "حُفظ التعديل", completion: completion)
    }
    func setMany(_ values: [String: JSONValue], completion: (() -> Void)? = nil) {
        execute(name: "settings.set", values: values, message: "حُفظ التعديل", completion: completion)
    }
    func reset(_ keys: [String]) {
        // Privacy authorization is changed through its own redaction lifecycle, never a shape reset.
        let defaults = Dictionary(uniqueKeysWithValues: schema.settings.filter { keys.contains($0.key) && $0.key != "core.faceIDLock" }.map { ($0.key, $0.defaultValue) })
        execute(name: "settings.set", values: defaults, message: "عادت الإعدادات المتفق عليها")
    }
    func applyPreset(_ settings: [String: JSONValue], completion: (() -> Void)? = nil) {
        execute(name: "settings.applyPreset", values: settings, message: "طُبّق النمط · التراجع متاح دقيقة", completion: completion)
    }
    func savePreset(name: String, completion: (() -> Void)? = nil) {
        guard beginWrite() else { return }
        let settings = values.filter { pair in schema.settings.contains { $0.key == pair.key && $0.preset && $0.type != "layout" } }
        var layouts: [String: JSONValue] = [:]
        for definition in schema.settings where definition.type == "layout" {
            layouts[definition.owner] = values[definition.key]
        }
        Task {
            defer { pendingWrites -= 1 }
            do {
                let encoder = JSONEncoder()
                let typed = try settings.mapValues { try JSONDecoder().decode(MadarCore.JSONValue.self, from: encoder.encode($0)) }
                let convertedLayouts = try layouts.mapValues { try JSONDecoder().decode(MadarCore.JSONValue.self, from: encoder.encode($0)) }
                let command = CommandEnvelope(name: "preset.save", payload: .object(["name": .string(name), "settings": .object(typed), "layouts": .object(convertedLayouts)]))
                let result = try await bus.execute(command)
                guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue("preset") }
                try reload(); completion?()
            } catch { errorMessage = "لم يُحفظ النمط. \(error.localizedDescription)" }
        }
    }
    func completeOnboarding() {
        guard beginWrite() else { return }
        Task {
            defer { pendingWrites -= 1 }
            do {
                let result = try await bus.execute(CommandEnvelope(name: "core.completeOnboarding", payload: .object([:])))
                guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue("onboarding") }
                onboardingComplete = true
            } catch { errorMessage = "لم تُحفظ البداية. \(error.localizedDescription)" }
        }
    }
    func undo() {
        guard let token = undoToken else { return }
        guard beginWrite() else { return }
        Task {
            defer { pendingWrites -= 1 }
            do {
                try await withSerializedPrayerNotificationMutation {
                    let result = try await bus.execute(CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(token.id.uuidString)])))
                    guard result.status == .applied else { throw DataError.undoExpired }
                    try reload(); undoToken = nil; expiryTask?.cancel(); try publishSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch { errorMessage = "لم يكتمل التراجع. \(error.localizedDescription)" }
        }
    }
    private func execute(name: String, values: [String: JSONValue], message: String, completion: (() -> Void)? = nil) {
        guard beginWrite() else { return }
        Task {
            defer { pendingWrites -= 1 }
            do {
                try await withSerializedPrayerNotificationMutation {
                    let encoder = JSONEncoder()
                    let typed = try values.mapValues { try JSONDecoder().decode(MadarCore.JSONValue.self, from: encoder.encode($0)) }
                    let command = CommandEnvelope(name: name, payload: .object(["settings": .object(typed)]))
                    let result = try await bus.execute(command)
                    guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "command") }
                    try reload()
                    if let id = result.undoToken {
                        let context = ModelContext(container)
                        if let receipt = try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).first(where: { $0.commandID == id }), let deadline = receipt.undoExpiresAt {
                            showUndo(AppUndoToken(id: id, expiresAt: deadline), message: message)
                        }
                    }
                    try publishSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                completion?()
            } catch { errorMessage = "لم يُحفظ التعديل. \(error.localizedDescription)" }
        }
    }
    private func beginWrite() -> Bool {
        guard !maintenanceInProgress else {
            errorMessage = "مدار يحدّث مخزن البيانات. حاول بعد اكتمال العملية."; return false
        }
        pendingWrites += 1; return true
    }
    func quiesceWriters() async throws {
        guard !maintenanceInProgress else { throw BackupOperationError.busy }
        maintenanceInProgress = true
        notificationStoreAccessSuspended = true
        while pendingWrites > 0 { await Task.yield() }
    }
    func resumeWriters() {
        maintenanceInProgress = false
        Task {
            do {
                guard try await drainInbox() else { return }
            } catch { errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
        }
    }
    func beginNotificationStoreAccess() -> Bool {
        guard notificationStoreAccessAvailable else { return false }
        pendingWrites += 1
        return true
    }
    func endNotificationStoreAccess() {
        pendingWrites = max(0, pendingWrites - 1)
    }
    var notificationStoreAccessAvailable: Bool {
        !maintenanceInProgress && !notificationStoreAccessSuspended
    }
    /// Count the drain as an app writer so export/restore can quiesce it cooperatively.
    @discardableResult
    func drainInbox() async throws -> Bool {
        guard !maintenanceInProgress, !inboxDrainer.isDraining else { return false }
        pendingWrites += 1; defer { pendingWrites -= 1 }
        let drained = try await withSerializedPrayerNotificationMutation(shouldRefresh: { $0 }) {
            guard try await inboxDrainer.drain() else { return false }
            // A malformed/quarantined record may have an unreadable identity: keep all receipts.
            let pinned: Set<UUID>
            do { pinned = try pendingInbox.unacknowledgedCommandIDs() }
            catch InboxError.malformedRecord { return true }
            try commandAdapter.purgeExpiredReceipts(pinnedIDs: pinned)
            return true
        }
        if drained && notificationStoreAccessSuspended && !maintenanceInProgress {
            notificationStoreAccessSuspended = false
            await prayerNotifications?.resumeAfterStoreMaintenance()
        }
        return drained
    }
    private func inboxGeneration() throws -> InboxGeneration {
        let previous = try pendingInbox.currentGeneration()
        guard let managedStore else {
            return previous ?? .init(generationID: UUID(), acceptsUnstampedDeliveries: true)
        }
        try managedStore.refreshIfNeeded()
        // The active pointer retains restore provenance; unstamped legacy files must stay
        // unresolved after replacement, including a crash before snapshot publication.
        struct PointerProvenance: Decodable { let previousGenerationID: UUID? }
        let pointer = try JSONDecoder().decode(PointerProvenance.self, from: Data(contentsOf: managedStore.root.appending(path: "ActiveGeneration.json")))
        let changed = previous.map { $0.generationID != managedStore.binding.generationID } ?? false
        let permitsLegacy = pointer.previousGenerationID == nil && !changed && previous?.acceptsUnstampedDeliveries != false
        return .init(generationID: managedStore.binding.generationID, acceptsUnstampedDeliveries: permitsLegacy)
    }
    func applySettingsAndWait(_ changes: [String: JSONValue]) async throws {
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        try await withSerializedPrayerNotificationMutation {
            let typed = try changes.mapValues { try JSONDecoder().decode(MadarCore.JSONValue.self, from: $0.canonicalData()) }
            let result = try await bus.execute(CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(typed)])))
            guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "settings") }
            try reload(); try publishSnapshot()
        }
    }
    func attachPrayerNotifications(_ coordinator: PrayerNotificationCoordinator) async {
        prayerNotifications = coordinator
        await coordinator.attach(to: self)
    }
    func refreshPrayerNotifications() async {
        do { try await prayerNotifications?.refresh() }
        catch { errorMessage = "تعذّر تحديث تذكيرات الصلاة. \(error.localizedDescription)" }
    }
    private func withSerializedPrayerNotificationMutation<T>(
        shouldRefresh: (T) -> Bool = { _ in true },
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        guard let coordinator = prayerNotifications else { return try await operation() }
        return try await coordinator.withSerializedMutation {
            do {
                let result = try await operation()
                if shouldRefresh(result) { await coordinator.refreshAfterSerializedMutation() }
                return result
            } catch {
                // A store command can commit before a later reload or snapshot write fails.
                // Reconcile while still holding the lifecycle lock so that committed prayer
                // state cannot leave an old request queued.
                await coordinator.refreshAfterSerializedMutation()
                throw error
            }
        }
    }
    func requestPrayerNotificationPermission() {
        Task {
            do { try await prayerNotifications?.requestAuthorization() }
            catch { errorMessage = "تعذّر طلب إذن الإشعارات. \(error.localizedDescription)" }
        }
    }
#if DEBUG
    func runNotificationScenarioForTesting() {
        guard let coordinator = prayerNotifications else {
            notificationTestResult = "FAIL — notification coordinator is not attached"
            return
        }
        notificationTestResult = "RUNNING"
        Task { [weak self, coordinator] in
            guard let self else { return }
            do { notificationTestResult = try await coordinator.runSimulatorAcceptanceScenarioForTesting() }
            catch { notificationTestResult = "FAIL — \(error.localizedDescription)" }
        }
    }
#endif
    func openPrayerNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    func updateNotificationAuthorization(_ state: String) { notificationAuthorization = state }
    var notificationsAuthorized: Bool { ["authorized", "provisional", "ephemeral"].contains(notificationAuthorization) }
    var canRequestNotificationPermission: Bool { notificationAuthorization == "notDetermined" }
    var shouldOpenNotificationSettings: Bool { notificationAuthorization == "denied" }
    var notificationPermissionTitle: String {
        switch notificationAuthorization {
        case "authorized", "provisional", "ephemeral": "إذن الإشعارات مفعّل لهذا الجهاز."
        case "denied": "إشعارات الصلاة مطفأة في إعدادات النظام."
        case "notDetermined": "اسمح بالإشعارات لتصلك أسئلة الصلاة بعد نهاية الحرمة."
        default: "تُقرأ حالة إذن الإشعارات من النظام."
        }
    }
    func redactProtectedData() {
        protectedDataAuthorized = false
        undoToken = nil; expiryTask?.cancel()
    }
    func authorizeProtectedData() { protectedDataAuthorized = true }
    func bindContainer(_ replacement: ModelContainer) {
        container = replacement; store = SettingsStore(context: ModelContext(replacement), schema: schema)
        undoToken = nil; expiryTask?.cancel()
    }
    private func showUndo(_ token: AppUndoToken, message: String) {
        undoToken = token; undoMessage = message; expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            let delay = max(0, token.expiresAt.timeIntervalSince(self?.prayerNow() ?? .now))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if self?.undoToken?.id == token.id { self?.undoToken = nil }
        }
    }
    var homeCity: [String: JSONValue] { if case .object(let place) = values["core.homeCity"] { place } else { [:] } }
    var cityName: String { if case .string(let name) = homeCity["name"] { name } else { "" } }
    var activePlace: ActivePlace {
        let city = homeCity
        guard case .number(let lat) = city["lat"], case .number(let lon) = city["lon"], case .string(let zone) = city["tz"], let place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: zone) else { return .riyadh }
        return place
    }
    func publishSnapshot() throws {
        try pendingInbox.publishGeneration(inboxGeneration())
        let instant = Date(), place = activePlace, day = GregorianDay.containing(instant, in: place.timeZone)
        let prayers = [day.adding(days: -1), day].compactMap { PrayerTimesEngine.calculate(day: $0, place: place) }
        guard let key = try? MadarDay.resolve(instant: instant, place: place, boundary: DayBoundary(rawValue: string("core.dayStart")) ?? .fajr, prayerDays: prayers, hijriSource: HijriSource(rawValue: string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(number("core.hijriOffset"))) else {
            try snapshotStore.remove("foundation")
            return
        }
        let snapshot = SnapshotEnvelope(name: "foundation", generatedAt: instant, validUntil: instant.addingTimeInterval(3600), dayKey: key.dayKey, tzID: place.timeZoneID, privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: string("core.firstCalendar"), numerals: string("core.numerals")))
        try snapshotStore.write(snapshot)
    }
}

private func prayerUITestClock(_ fallback: Date) -> Date {
    #if DEBUG
    if let raw = ProcessInfo.processInfo.environment["MADAR_UI_NOW"] {
        let formatter = ISO8601DateFormatter()
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) { return value }
    }
    #endif
    return fallback
}
