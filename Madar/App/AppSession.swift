import Foundation
import SwiftUI
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
    private static let bahwReturnStateKey = "sys.bahwReturnPlan"
    let diaryPlayback = DiaryPlayback()
    var diaryRoute: Route?
    /// A diary root link waits for child editors that own an explicit save/discard path.
    var diaryRootRequestID: UUID?
    var diaryRootDraftBlockers: Set<UUID> = []
    var prayerRoute: Route?
    var prayerRootRequestID: UUID?
    var quranRoute: Route?
    /// M4-V03: «السنة وما يهمّك» pushed from the lobby (`madar://bahw/year`).
    var yearOpen = false
    var yearDayID: UUID?
    var widgetMakerRoute: Route?
    var widgetMakerRouteID: UUID?
    var moneyOpen = false
    /// One-shot: the money room opens straight on the bank messages (after the old-Madar move left some for review).
    var moneyOpensMessages = false
    var moneyRoute: Route?
    /// A money-root link closes the pushed screens, but waits while the expense draft holds unsaved input.
    var moneyRootRequestID: UUID?
    var moneyRootDraftBlockers: Set<UUID> = []
    var mihbaraOpen = false
    var mihbaraBookToOpen: UUID?
    var mihbaraRoute: Route?
    var searchRoute: Route?
    var settingsRoute: Route?
    var moneyExpenseSeed: MoneyExpenseSeed?
    @ObservationIgnored private var queuedMoneyExpenseSeeds: [MoneyExpenseSeed] = []
    var habitsOpen = false
    /// A lobby-root link waits for the habits editor to close so its local, unsaved fields stay visible.
    var bahwRootRequestID: UUID?
    /// A capture named a prayer without its state; the prayer home opens that prayer's log sheet.
    var prayerLogRequest: Prayer?
    var habitRouteID:UUID?
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
    private(set) var bahwReturnPlanDay: Int?
#if DEBUG
    var notificationTestResult = ""
    var bankCorpusImportedInputCount = 0
#endif
    @ObservationIgnored weak var prayerNotifications: PrayerNotificationCoordinator?
    @ObservationIgnored private var privacyScopeTransitionPending = false
    let schema: SettingsSchema
    var store: SettingsStore
    private(set) var values: [String: JSONValue] = [:]
    private(set) var undoToken: AppUndoToken?
    private(set) var undoMessage = ""
    /// Owner, 24 Oct 2026: «التراجع متاح… يتكرر وصاير مزعج مره ويطول». The toast shows for a few seconds; the undo
    /// itself stays valid until its token expires.
    private(set) var undoToastVisible = false
    /// UI tests reach the toast after several steps, so a UI-test store keeps it two minutes unless
    /// MADAR_UI_UNDO_SECONDS says otherwise (DEBUG only). The app itself shows it for four seconds.
    static var undoToastSeconds: Double {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let text = environment["MADAR_UI_UNDO_SECONDS"], let seconds = Double(text) { return seconds }
        if environment["MADAR_UI_STORE_ID"] != nil { return 120 }
        #endif
        return 4
    }
    /// Owner, 30 Oct 2026: «الزر حق التراجع… طريقه خروجه وبقائه مزعجه». It popped in and out and every screen jumped
    /// under it; now it glides in and out with the screen, and stays four seconds instead of six.
    private func setUndoToast(_ visible: Bool) {
        guard undoToastVisible != visible else { return }
        withAnimation(.smooth(duration: 0.35)) { undoToastVisible = visible }
    }
    /// A swipe down puts the toast away; the undo itself stays valid until its token expires, as before.
    func hideUndoToast() { toastTask?.cancel(); setUndoToast(false) }
    var errorMessage: String?
    var onboardingComplete = false
    var selectedTab = "foundation"
    /// Focused full-screen flows (the expense keypad, the year) that hide the tab bar also hide the glass accessory.
    var accessoryHiders: Set<String> = []
    private(set) var prayerRevision = 0
    private(set) var prayerWriteInProgress = false
    #if DEBUG
    @ObservationIgnored var failFirstNotebookSave = false
    @ObservationIgnored private var failFirstGoodreadsImport = false
    #endif
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
        // §16 authorize: prayer.log and habit.complete are blindWrite even with whole-app Face ID protection.
        // App-only settings never enter via transport, even if it claims source: app.
        if CommandBus.transportBlindWriteNames.contains(command.name) { return nil }
        return self.lockController?.canPresent(.app) == true ? nil : .init(status: .needsUnlock)
    })
    private var expiryTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var spotlightBookSnapshot: [AppSpotlightBookRecord]?
    @ObservationIgnored private var spotlightDomainsClearedWhileDisabled = false
    @ObservationIgnored private var spotlightReconciliationRevision: UInt64 = 0
    @ObservationIgnored private var spotlightReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private let spotlightIndexOperation: AppSpotlightIndexOperation

    static let supportedKeys = ["core.dayStart", "core.firstCalendar", "core.hijriSource", "core.hijriOffset", "core.weekStart", "core.theme", "core.numerals", "core.homeCity", "core.faceIDLock", "core.spotlightIndex", "salah.pool", "salah.fridayTallArch", "salah.pendingDays", "salah.tripMethod", "salah.travelShortenCombine", "salah.qadaReminder", "salah.askAfterAdhanMin", "salah.askReminder", "salah.liveActivity", "salah.showMosqueStreak", "salah.askHeart", "salah.method", "salah.asr", "salah.highLatitudeRule", "salah.offsets", "notif.thisDeviceReminders", "notif.quietAfterIsha", "notif.quietFrom", "notif.quietUntil", "bahw.yearWhich", "bahw.upcomingCount", "bahw.streakBreakAfter", "bahw.reminder", "bahw.travelFreezesHome", "bahw.smartPresence", "bahw.widgetScope"]

    init(
        container: ModelContainer,
        managedStore: ManagedDataStore? = nil,
        groupDirectory: URL? = nil,
        spotlightIndexOperation: @escaping AppSpotlightIndexOperation = { enabled, records in
            if enabled { try await AppSpotlightIndexing.replaceBookItems(records) }
            else { try await AppSpotlightIndexing.removeAppItems() }
        }
    ) throws {
        self.container = container
        self.managedStore = managedStore
        self.spotlightIndexOperation = spotlightIndexOperation
        guard let group = groupDirectory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { throw DataError.missingAppGroup }
        #if DEBUG
        let notebookTest = ProcessInfo.processInfo.environment
        failFirstNotebookSave = notebookTest["MADAR_UI_NOTE_FAIL_FIRST_SAVE"] == "1"
            && notebookTest["MADAR_UI_STORE_ID"] == group.lastPathComponent
            && group.deletingLastPathComponent().lastPathComponent == "UITestStores"
        failFirstGoodreadsImport = notebookTest["MADAR_UI_MIHBARA_IMPORT_GOODREADS_FAIL_ONCE"] == "1"
            && notebookTest["MADAR_UI_STORE_ID"] == group.lastPathComponent
            && group.deletingLastPathComponent().lastPathComponent == "UITestStores"
        #endif
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
        try preparePrayerPolarNoTimesFixture()
        try prepareStyleSettingsFixture()
        try preparePrayerStatisticsFixture()
        try preparePrayerHomeShowcaseFixture()
        try preparePrayerStreakShowcaseFixture()
        try prepareQuranHomeFixture(group: group)
        try prepareDiaryHomeFixture(group: group)
        try prepareLegacyTrial()
        try prepareHabitFixture(group: group)
        try prepareMoneyFixture(group: group)
        try prepareMihbaraFixture(group: group)
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
    /// Records an authorized app visit. The state lives in a local DeviceSetting and is never sent to CloudKit.
    func recordBahwReturnVisit() {
        guard lockController?.canPresent(.app) ?? protectedDataAuthorized else { return }

        let now = prayerNow()
        let today = AppBahwService(session: self, evaluationDate: now).today
        let context = ModelContext(container)
        let key = Self.bahwReturnStateKey
        do {
            let rows = try context.fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key }))
            let existing = rows.filter { $0.mergedInto == nil }.max {
                $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt
            }
            let previous = existing.flatMap { try? JSONDecoder().decode(BahwReturnVisitState.self, from: $0.valueJSON) }
            let next = BahwReturnPlanEngine.recordVisit(on: today, state: previous)
            let nextDay = BahwReturnPlanEngine.dayNumber(on: today, state: next)

            if next == previous {
                bahwReturnPlanDay = nextDay
                return
            }

            let row = existing ?? DeviceSetting()
            if row.modelContext == nil {
                row.id = StableIdentity.uuid(for: "DeviceSetting:\(key)")
                context.insert(row)
            }
            let localStore = SettingsStore(context: context, schema: schema)
            row.key = key
            row.valueJSON = try JSONEncoder().encode(next)
            row.writerID = try localStore.writerIDForWrite(now: now)
            row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
            row.restoredAt = max(row.updatedAt, (row.deletionBarrierAt ?? .distantPast).addingTimeInterval(0.001))
            row.deletedAt = nil
            try context.save()
            bahwReturnPlanDay = nextDay
        } catch {
            bahwReturnPlanDay = nil
            errorMessage = "تعذّر حفظ خطة العودة على هذا الجهاز. حاول فتح البهو مرة أخرى."
        }
    }
#if DEBUG
    func seedBahwReturnPlanFixtureIfRequested() {
        guard ProcessInfo.processInfo.environment["MADAR_UI_RETURN_PLAN"] == "1" else { return }
        let key = Self.bahwReturnStateKey
        let context = ModelContext(container)
        do {
            let rows = try context.fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key }))
            guard !rows.contains(where: { $0.deletedAt == nil && $0.mergedInto == nil }) else { return }
            let today = AppBahwService(session: self, evaluationDate: prayerNow()).today
            let state = BahwReturnVisitState(lastVisitedDay: today.adding(days: -3))
            let row = rows.first ?? DeviceSetting()
            if row.modelContext == nil {
                row.id = StableIdentity.uuid(for: "DeviceSetting:\(key)")
                context.insert(row)
            }
            let localStore = SettingsStore(context: context, schema: schema)
            row.key = key
            row.valueJSON = try JSONEncoder().encode(state)
            row.writerID = try localStore.writerIDForWrite(now: prayerNow())
            row.updatedAt = StableIdentity.monotonic(now: prayerNow(), previous: row.updatedAt)
            row.restoredAt = row.updatedAt
            row.deletedAt = nil
            try context.save()
        } catch {
            errorMessage = "تعذّر تجهيز حالة العودة للاختبار."
        }
    }
#endif
    func reconcileSpotlightIndex(reportFailure: Bool = false) async {
        spotlightReconciliationRevision &+= 1
        let revision = spotlightReconciliationRevision
        let enabled = bool("core.spotlightIndex")
        if enabled {
            spotlightDomainsClearedWhileDisabled = false
        } else {
            // An in-flight index or deletion may have changed Spotlight even if its
            // completion becomes stale. Never let a newer enable trust that snapshot.
            spotlightBookSnapshot = nil
        }
        if !enabled, spotlightDomainsClearedWhileDisabled, spotlightReconciliationTask == nil { return }

        let previousTask = spotlightReconciliationTask
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self, self.spotlightReconciliationRevision == revision else { return }
            await self.performSpotlightReconciliation(enabled: enabled, revision: revision, reportFailure: reportFailure)
        }
        spotlightReconciliationTask = task
        await task.value
        if spotlightReconciliationRevision == revision { spotlightReconciliationTask = nil }
    }

    private func performSpotlightReconciliation(enabled: Bool, revision: UInt64, reportFailure: Bool) async {
        guard spotlightReconciliationRevision == revision, bool("core.spotlightIndex") == enabled else { return }
        if !enabled {
            do {
                try await spotlightIndexOperation(false, [])
                guard spotlightReconciliationRevision == revision, !bool("core.spotlightIndex") else { return }
                spotlightBookSnapshot = nil
                spotlightDomainsClearedWhileDisabled = true
            } catch {
                guard spotlightReconciliationRevision == revision, !bool("core.spotlightIndex") else { return }
                if reportFailure { errorMessage = "تعذّر تنظيف نتائج البحث لهذا الجهاز." }
            }
            return
        }

        do {
            let books = try ModelContext(container).fetch(FetchDescriptor<Book>())
            let records = AppSpotlightIndexing.records(from: books)
            guard records != spotlightBookSnapshot || spotlightDomainsClearedWhileDisabled else { return }
            guard spotlightReconciliationRevision == revision, bool("core.spotlightIndex") else { return }
            // Once a write starts, a newer request must re-read/re-index even when it
            // returns to the previous snapshot; this operation may finish out of date.
            spotlightBookSnapshot = nil
            try await spotlightIndexOperation(true, records)
            guard spotlightReconciliationRevision == revision, bool("core.spotlightIndex") else { return }
            spotlightBookSnapshot = records
            spotlightDomainsClearedWhileDisabled = false
        } catch {
            guard spotlightReconciliationRevision == revision, bool("core.spotlightIndex") else { return }
            spotlightBookSnapshot = nil
            if reportFailure { errorMessage = "تعذّر تحديث نتائج بحث الكتب. أعد المحاولة بعد قليل." }
        }
    }
    func openSpotlightBook(_ id: UUID) {
        mihbaraBookToOpen = id
        selectedTab = "mihbara"
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
            undoMessage: status == .missed ? "سُجّلت فائتة" : "سُجّلت الصلاة", completion: completion)
    }
    func oldMissedRequiresRestore(_ reference: PrayerReference) throws -> Bool {
        try PrayerRepository(context: ModelContext(container)).oldMissedRequiresRestore(reference)
    }
    func addOldMissedPrayer(_ reference: PrayerReference, fridayKind: FridayPrayerKind?, restoreDeleted: Bool = false, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.addOldMissed", payload: .object([
            "dayKey": .string(reference.day.description), "prayer": .string(reference.prayer.rawValue),
            "fridayKind": fridayKind.map { .string($0.rawValue) } ?? .null, "restoreDeleted": .bool(restoreDeleted)
        ]), undoMessage: "أُضيفت الفائتة القديمة", completion: completion)
    }
    func qiyamRequiresRestore(_ night: GregorianDay) throws -> Bool {
        try PrayerRepository(context: ModelContext(container)).nightRequiresRestore(night)
    }
    func recordQiyamNight(_ night: GregorianDay, rakaat: Int, witr: Bool, restoreDeleted: Bool = false, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.logQiyam", payload: .object([
            "nightKey": .string(night.description), "rakaat": .number(Double(rakaat)), "witr": .bool(witr), "restoreDeleted": .bool(restoreDeleted)
        ]), undoMessage: "حُفظ قيام الليلة", completion: completion)
    }
    func answerPrayerHeart(_ reference: PrayerReference, heart: PrayerHeart?, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.setHeart", payload: .object([
            "dayKey": .string(reference.day.description), "prayer": .string(reference.prayer.rawValue),
            "heart": heart.map { .string($0.rawValue) } ?? .null
        ]), undoMessage: "حُفظت إجابة القلب", completion: completion)
    }
    /// P04: the tracking start moves once, up to 30 days before the first run. The engine enforces both limits.
    func editPrayerTrackingStart(_ day: GregorianDay, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.editTrackingStart", payload: .object(["dayKey": .string(day.description)]),
            undoMessage: "عُدّلت بداية التتبّع", completion: completion)
    }
    /// RP4/RP7: the owner answered the one question. The method is stored first; times then use it for this trip only.
    func startPrayerTrip(city: String, country: String, place: ActivePlace, homeKm: Double?, method: PrayerCalculationMethod, completion: ((Bool) -> Void)? = nil) {
        set(.string(method.rawValue), key: "salah.tripMethod") { [self] in
            var payload: [String: MadarCore.JSONValue] = ["city": .string(city), "country": .string(country), "lat": .number(place.latitude), "lon": .number(place.longitude), "tzID": .string(place.timeZoneID)]
            if let homeKm { payload["homeKm"] = .number(homeKm) }
            sendPrayerCommand(name: "prayer.startTrip", payload: .object(payload), undoMessage: "بدأت الرحلة", completion: completion)
        }
    }
    /// OR-09: the trip moves on to another country; the open leg closes and the next joins the same journey (one undo).
    func continuePrayerTrip(city: String, country: String, place: ActivePlace, homeKm: Double?, completion: ((Bool) -> Void)? = nil) {
        var payload: [String: MadarCore.JSONValue] = ["city": .string(city), "country": .string(country), "lat": .number(place.latitude), "lon": .number(place.longitude), "tzID": .string(place.timeZoneID)]
        if let homeKm { payload["homeKm"] = .number(homeKm) }
        sendPrayerCommand(name: "prayer.continueTrip", payload: .object(payload), undoMessage: "أُضيفت " + city + " إلى رحلتك", completion: completion)
    }
    func endPrayerTrip(_ id: UUID, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.endTrip", payload: .object(["tripID": .string(id.uuidString)]), undoMessage: "انتهت الرحلة", completion: completion)
    }
    func logPrayerPair(day: GregorianDay, pair: PrayerPair, status: PrayerStoredStatus, shortened: Bool, mode: PrayerPairMode, completion: ((Bool) -> Void)? = nil) {
        sendPrayerCommand(name: "prayer.logPair", payload: .object(["dayKey": .string(day.description), "pair": .string(pair.rawValue), "status": .string(status.rawValue), "shortened": .bool(shortened), "mode": .string(mode.rawValue)]),
            undoMessage: "سُجّلت الصلاتان", completion: completion)
    }
    func makeUpPrayer(_ reference: PrayerReference, fridayKind: FridayPrayerKind? = nil, completion: ((Bool) -> Void)? = nil) {
        let at = prayerNow()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: MadarCore.JSONValue = .object([
            "dayKey": .string(reference.day.description),
            "prayer": .string(reference.prayer.rawValue),
            "at": .string(formatter.string(from: at)),
            "fridayKind": fridayKind.map { .string($0.rawValue) } ?? .null
        ])
        sendPrayerCommand(name: "prayer.makeUp", payload: payload, undoMessage: "قُضيت الصلاة", completion: completion)
    }
    func resolvePrayerGap(_ resolutions: [PrayerGapResolution], completion: ((Bool) -> Void)? = nil) {
        guard !resolutions.isEmpty else { completion?(false); return }
        let values = resolutions.map { item in
            MadarCore.JSONValue.object([
                "dayKey": .string(item.reference.day.description),
                "prayer": .string(item.reference.prayer.rawValue),
                "status": .string(item.status.rawValue),
                "fridayKind": item.fridayKind.map { .string($0.rawValue) } ?? .null
            ])
        }
        sendPrayerCommand(name: "prayer.resolveGap", payload: .object(["resolutions": .array(values)]),
            undoMessage: "حُلّت الفترة", completion: completion)
    }
    /// Capture's prayer report uses the same command, undo and refresh as a tap on the arch.
    @discardableResult
    func logCapturedPrayer(payload: MadarCore.JSONValue, undoMessage: String) -> Bool {
        sendPrayerCommand(name: "prayer.log", payload: payload, undoMessage: undoMessage)
    }
    @discardableResult
    private func sendPrayerCommand(name: String, payload: MadarCore.JSONValue, undoMessage: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard !prayerWriteInProgress, beginWrite() else { completion?(false); return false }
        prayerWriteInProgress = true
        let now = prayerNow()
        Task {
            var succeeded = false
            defer {
                pendingWrites -= 1
                prayerWriteInProgress = false
                completion?(succeeded)
                Task { await MadarIntentHandoff.shared.flush() }
            }
            do {
                succeeded = try await withSerializedPrayerNotificationMutation {
                    let command = CommandEnvelope(name: name, payload: payload, source: .app, issuedAt: now)
                    let result = try await bus.execute(command, now: now)
                    guard result.status == .applied || result.status == .duplicate else {
                        errorMessage = prayerFailure(result.reason)
                        return false
                    }
                    clearRecoveredMaintenanceError()
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
                errorMessage = "لم يُسجّل التغيير. \(madarUserMessage(error))"
            }
        }
        return true
    }
    private func prayerFailure(_ reason: String?) -> String {
        switch reason {
        case "futurePrayer": "لم يحن وقت الصلاة بعد."
        case "prayerWindowOpen": "لم ينته وقت الصلاة بعد؛ يمكنك تسجيلها عند انتهائه."
        case "unavailablePrayerTimes": "لا تتوفر مواقيت مؤكدة لهذا الفرض."
        case "beforeTrackingStart": "هذا اليوم يسبق بداية التسجيل."
        case "explicitRestoreRequired": "يتطلب هذا السجل استعادة صريحة."
        case "invalidRecord": "نوع الجمعة متاح لظهر الجمعة فقط."
        case "noActiveTrip": "لا توجد رحلة جارية."
        case "invalidPair": "هاتان الصلاتان لا تُجمعان الآن."
        case "invalidShortening": "القصر لا ينطبق على هذه الصلاة."
        case "trackingAlreadyEdited": "اكتمل التعديل الوحيد لبداية التتبّع."
        case "invalidTrackingStart": "البداية خارج المدى: حتى ثلاثين يومًا قبل أول تشغيل."
        default: "لم تُسجّل الصلاة. حاول مرة أخرى."
        }
    }
    #if DEBUG
    /// OR-15/16/27 screenshots: picks one of the appearance looks in an isolated UI-test store, e.g.
    /// MADAR_UI_STYLE_SETTINGS="mal.hawlStyle=orbit,notes.fridayStyle=medallion". Only these four keys are accepted.
    private func prepareStyleSettingsFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        guard UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil, let raw = environment["MADAR_UI_STYLE_SETTINGS"] else { return }
        let allowed: Set = ["mal.figureStyle", "mal.hawlStyle", "notes.fridayStyle", "notes.ramadanStyle"]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, allowed.contains(parts[0]) else { continue }
            try store.prepare(.string(parts[1]), for: parts[0], now: prayerNow())
        }
        try container.mainContext.save()
    }
    /// Isolated UI-test fixture for the contract that polar days have no invented times but remain manually loggable.
    private func preparePrayerPolarNoTimesFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        guard UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
              environment["MADAR_UI_PRAYER_FIXTURE"] == "polarNoTimes" else { return }
        try store.prepare(.object([
            "name": .string("Tromsø"), "country": .string("NO"),
            "lat": .number(69.6492), "lon": .number(18.9553),
            "tz": .string("Europe/Oslo"), "currency": .string("NOK")
        ]), for: "core.homeCity", now: prayerNow())
        try store.prepare(.string("manual"), for: "core.travelMode", now: prayerNow())
        try container.mainContext.save()
    }

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
    /// DEBUG-only S1 showcase in an isolated UI-test store: a week shaped like the canonical
    /// home (three prayers recorded today, last night's Isha unrecorded, three owed prayers).
    /// Hand-authored rows, never engine output; use with MADAR_UI_NOW 2026-10-07T16:20+03:00.
    private func preparePrayerHomeShowcaseFixture() throws {
        guard ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil,
              let fixture = ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_FIXTURE"], ["homeShowcase", "homeShowcaseFriday"].contains(fixture) else { return }
        // `homeShowcaseFriday` is the same week carried to Friday 2026-10-09 (use MADAR_UI_NOW 2026-10-09T16:20+03:00).
        let lastDay = fixture == "homeShowcaseFriday" ? 9 : 7
        let context = ModelContext(container)
        guard try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty else { return }
        let alone: Set<String> = ["2026-10-03.dhuhr", "2026-10-05.fajr", "2026-10-07.asr"]
        let missed: Set<String> = ["2026-10-02.asr", "2026-10-03.fajr", "2026-10-04.isha"]
        for day in 1...lastDay {
            let dayKey = String(format: "2026-10-%02d", day)
            for prayer in Prayer.allCases {
                let key = dayKey + "." + prayer.rawValue
                if dayKey == "2026-10-06" && prayer == .isha { continue }
                if day == lastDay && [.maghrib, .isha].contains(prayer) { continue }
                let row = PrayerLog()
                row.dayKey = dayKey
                row.prayer = prayer.rawValue
                row.status = missed.contains(key) ? "missed" : alone.contains(key) ? "alone" : "jamaah"
                if prayer == .dhuhr && (day == 2 || day == 9) { row.fridayKind = row.status == "jamaah" ? "jumuah" : "dhuhr" }
                row.tzID = "Asia/Riyadh"
                row.eventAt = try GregorianDay(dayKey).date(in: ActivePlace.riyadh.timeZone).addingTimeInterval(12 * 3600)
                row.source = "user"
                context.insert(row)
                if missed.contains(key) {
                    let debt = QadaItem(); debt.originalDayKey = dayKey; debt.prayer = prayer.rawValue
                    context.insert(debt)
                }
            }
        }
        for (night, rakaat, witr) in [("2026-10-01", 8, true), ("2026-10-02", 4, false), ("2026-10-04", 2, true), ("2026-10-05", 8, true)] {
            let row = QiyamNight(); row.nightKey = night; row.rakaat = rakaat; row.witr = witr; row.tzID = "Asia/Riyadh"
            context.insert(row)
        }
        try context.save()
    }
    /// DEBUG-only «سلاسلك» showcase: the hand-worked week of `PrayerStreakTests` (a made-up Fajr on 3 Oct,
    /// Asr alone on 4 Oct, Isha unrecorded on 6 Oct). Expected: congregation 2, on time 3, completion 6.
    /// Use with MADAR_UI_NOW 2026-10-08T16:20+03:00 and MADAR_UI_TRACKING_START 2026-10-01.
    private func preparePrayerStreakShowcaseFixture() throws {
        guard ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil,
              let fixture = ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_FIXTURE"], ["streakShowcase", "streakShowcaseMonth"].contains(fixture) else { return }
        let context = ModelContext(container)
        guard try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty else { return }
        // `streakShowcaseMonth` (tracking start 2026-09-12): Asr missed on 13 Sep, Fajr made up on 21 Sep,
        // Dhuhr alone on 28 Sep. Expected: congregation 9, on time 16, completion 24.
        let month = fixture == "streakShowcaseMonth"
        let keys = month ? (12...30).map { String(format: "2026-09-%02d", $0) } + (1...8).map { String(format: "2026-10-%02d", $0) }
                         : (1...8).map { String(format: "2026-10-%02d", $0) }
        let qadaDay = month ? "2026-09-21" : "2026-10-03", aloneDay = month ? "2026-09-28" : "2026-10-04"
        let aloneSlot: Prayer = month ? .dhuhr : .asr
        let fridays: Set<String> = ["2026-09-18", "2026-09-25", "2026-10-02"]
        for dayKey in keys {
            for prayer in Prayer.allCases {
                if !month && dayKey == "2026-10-06" && prayer == .isha { continue }
                if dayKey == "2026-10-08" && ![.fajr, .dhuhr].contains(prayer) { continue }
                let row = PrayerLog()
                row.dayKey = dayKey
                row.prayer = prayer.rawValue
                row.status = month && dayKey == "2026-09-13" && prayer == .asr ? "missed"
                    : dayKey == qadaDay && prayer == .fajr ? "qada" : dayKey == aloneDay && prayer == aloneSlot ? "alone" : "jamaah"
                if prayer == .dhuhr && fridays.contains(dayKey) && row.status == "jamaah" { row.fridayKind = "jumuah" }
                row.tzID = "Asia/Riyadh"
                row.eventAt = try GregorianDay(dayKey).date(in: ActivePlace.riyadh.timeZone).addingTimeInterval(12 * 3600)
                row.source = "user"
                context.insert(row)
                if row.status == "qada" || row.status == "missed" {
                    let debt = QadaItem(); debt.originalDayKey = dayKey; debt.prayer = prayer.rawValue
                    if row.status == "qada" { debt.madeUpAt = row.eventAt }
                    context.insert(debt)
                }
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
    var settingsWriteInProgress: Bool { pendingWrites > 0 || maintenanceInProgress }
    func string(_ key: String) -> String { if case .string(let v) = values[key] { v } else { "" } }
    func bool(_ key: String) -> Bool { if case .bool(let v) = values[key] { v } else { false } }
    func number(_ key: String) -> Double { if case .number(let v) = values[key] { v } else { 0 } }
    func setDiaryRootDraftBlocker(_ id: UUID, active: Bool) {
        if active { diaryRootDraftBlockers.insert(id) }
        else { diaryRootDraftBlockers.remove(id) }
    }
    func setMoneyRootDraftBlocker(_ id: UUID, active: Bool) {
        if active { moneyRootDraftBlockers.insert(id) }
        else { moneyRootDraftBlockers.remove(id) }
    }
    func open(_ url: URL) {
        let today = GregorianDay.containing(.now, in: activePlace.timeZone)
        let unavailableSettings = Set(schema.settings.map(\.key)).subtracting(Self.supportedKeys)
        let context = RouteContext(trackingStart: today.adding(days: -36500), today: today, settingsKeys: Set(Self.supportedKeys), unavailableSettings: unavailableSettings, availability: .init(builtRooms: [.core, .salah, .quran, .notes, .bahw, .year, .habits, .mal, .mihbara]))
        do {
            var components=URLComponents(url:url,resolvingAgainstBaseURL:false)
            if components?.host == "prayer" {components?.host="salah"} // Existing placed widgets used this legacy alias.
            let route = try RouteRegistry.parse(components?.url ?? url, context: context)
            if url.host == "settings" {
                settingsRoute = route
                settingsQuery = (try? schema.definition(for: route.path[1]).title) ?? ""
                selectedTab = "customize"
                return
            }
            if route.room == .mal, route.path == ["add"] {
                let raw = route.parameters["amount"].flatMap(Int.init).map { AppMoneyService(app: self).moneyInput($0) } ?? ""
                presentMoneyExpenseSeed(.init(amount: raw, merchant: String((route.parameters["merchant"] ?? "").prefix(80)), method: route.parameters["method"], homeCurrency: true)); return
            }
            if route.room == .mal, route.path.isEmpty || route.path == ["now"] { moneyRootRequestID = UUID(); selectedTab = "money"; return }
            if route.room == .mal { moneyRoute = route; selectedTab = "money"; return }
            if route.room == .salah {
                if route.path.isEmpty { prayerRootRequestID = UUID(); selectedTab = "prayer" }
                else { prayerRoute = route; selectedTab = "prayer" }
                return
            }
            if route.room == .bahw, route.path.isEmpty {
                yearOpen = false; selectedTab = "foundation"
                if habitsOpen { bahwRootRequestID = UUID() }
                else { habitsOpen = false }
                return
            }
            if route.room == .bahw, route.path == ["widget-maker"] { widgetMakerRoute = route; widgetMakerRouteID = UUID(); selectedTab = "customize"; return }
            if route.room == .quran {
                quranRoute = route; selectedTab = "quran"; return
            }
            if route.room == .notes {
                if route.path.isEmpty {
                    diaryRootRequestID = UUID()
                    if selectedTab != "notes" { selectedTab = "notes" }
                } else {
                    diaryRoute = route
                    selectedTab = "notes"
                }
                return
            }
            if route.room == .habits { bahwRootRequestID = nil; habitRouteID=route.path.last.flatMap(UUID.init(uuidString:)) ?? route.parameters["habit"].flatMap(UUID.init(uuidString:)); yearOpen = false; selectedTab = "foundation"; habitsOpen = true; return }
            if route.room == .year {
                yearDayID = route.path.count == 3 ? route.path.last.flatMap(UUID.init(uuidString:)) : nil
                bahwRootRequestID = nil; habitsOpen = false; selectedTab = "foundation"; yearOpen = true; return
            }
            if route.room == .mihbara { mihbaraRoute = route; selectedTab = "mihbara"; return }
            // A valid link whose inner screen has no direct route yet opens its room, never «هذا الرابط غير متاح».
            let roomTabs: [Room: String] = [.salah: "prayer", .quran: "quran", .notes: "notes", .mal: "money", .mihbara: "mihbara", .bahw: "foundation", .year: "foundation"]
            if url.host == "search" {
                searchRoute = route
                selectedTab = route.parameters["room"].flatMap(Room.init(rawValue:)).flatMap { roomTabs[$0] } ?? "notes"
                return
            }
            if let tab = roomTabs[route.room] { selectedTab = tab; return }
            throw CoreError.unavailableFeature
        } catch { errorMessage = "هذا الرابط غير متاح في إصدار مدار الحالي." }
    }
    /// Keep later Capture/deep-link requests until the current local-only expense draft is dismissed.
    func presentMoneyExpenseSeed(_ seed: MoneyExpenseSeed) {
        if moneyExpenseSeed?.id == seed.id || queuedMoneyExpenseSeeds.contains(where: { $0.id == seed.id }) { return }
        if moneyExpenseSeed == nil && queuedMoneyExpenseSeeds.isEmpty {
            moneyExpenseSeed = seed
        } else {
            queuedMoneyExpenseSeeds.append(seed)
            if moneyExpenseSeed == nil { presentNextMoneyExpenseSeed() }
        }
    }
    /// Called only after SwiftUI has finished dismissing the current expense cover.
    func presentNextMoneyExpenseSeed() {
        guard moneyExpenseSeed == nil, !queuedMoneyExpenseSeeds.isEmpty else { return }
        moneyExpenseSeed = queuedMoneyExpenseSeeds.removeFirst()
    }
    func set(_ value: JSONValue, key: String, completion: (() -> Void)? = nil) {
        if key == "core.faceIDLock", case .string(let raw) = value, let scope = MadarLockScope(rawValue: raw), let lockController {
            Task {
                do { try await lockController.changeScope(scope); completion?() }
                catch { errorMessage = "لم يتغيّر القفل. \(madarUserMessage(error))" }
            }
            return
        }
        execute(name: "settings.set", values: [key: value], message: "حُفظ التعديل", completion: completion)
    }
    func setMany(_ values: [String: JSONValue], completion: (() -> Void)? = nil) {
        execute(name: "settings.set", values: values, message: "حُفظ التعديل", completion: completion)
    }
    func reset(_ keys: [String], completion: (() -> Void)? = nil) {
        // Privacy authorization is changed through its own redaction lifecycle, never a shape reset.
        let defaults = Dictionary(uniqueKeysWithValues: schema.settings.filter { keys.contains($0.key) && $0.key != "core.faceIDLock" }.map { ($0.key, $0.defaultValue) })
        execute(name: "settings.set", values: defaults, message: "عادت الإعدادات المتفق عليها", completion: completion)
    }
    func applyPreset(_ settings: [String: JSONValue], completion: (() -> Void)? = nil) {
        execute(name: "settings.applyPreset", values: settings, message: "طُبّق النمط", completion: completion)
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
            } catch { errorMessage = "لم يُحفظ النمط. \(madarUserMessage(error))" }
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
            } catch { errorMessage = "لم تُحفظ البداية. \(madarUserMessage(error))" }
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
                    try reload(); undoToken = nil; setUndoToast(false); expiryTask?.cancel(); try publishSnapshot()
                    await reconcileSpotlightIndex()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch { errorMessage = "لم يكتمل التراجع. \(madarUserMessage(error))" }
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
                if values["core.spotlightIndex"] != nil { await reconcileSpotlightIndex(reportFailure: true) }
                completion?()
            } catch { errorMessage = "لم يُحفظ التعديل. \(madarUserMessage(error))" }
        }
    }
    private func beginWrite() -> Bool {
        guard !maintenanceInProgress else {
            errorMessage = Self.maintenanceBusyMessage; return false
        }
        pendingWrites += 1; return true
    }
    private static let maintenanceBusyMessage = "مدار يحدّث مخزن البيانات. حاول بعد اكتمال العملية."
    func clearRecoveredMaintenanceError() {
        if errorMessage == Self.maintenanceBusyMessage { errorMessage = nil }
    }
    func quiesceWriters() async throws {
        guard !maintenanceInProgress else { throw BackupOperationError.busy }
        maintenanceInProgress = true
        notificationStoreAccessSuspended = true
        while pendingWrites > 0 { await Task.yield() }
    }
    func resumeWriters() {
        maintenanceInProgress = false
        MihbaraReadingSaveCoordinator.storeMaintenanceEnded(for: self)
        Task {
            do {
                guard try await drainInbox() else { return }
            } catch { errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))"; return }
            await MadarIntentHandoff.shared.flush()
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
    func executeQuranCommand(_ name: String, payload: [String: MadarCore.JSONValue]) async throws -> CommandOutcome {
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        let result = try await withSerializedPrayerNotificationMutation {
            let result = try await bus.execute(CommandEnvelope(name: name, payload: .object(payload)))
            guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "Quran command") }
            try reload(); try publishSnapshot()
            return result
        }
        if let id = result.undoToken, let receipt = try ModelContext(container).fetch(FetchDescriptor<MadarData.CommandReceipt>()).first(where: { $0.commandID == id }), let deadline = receipt.undoExpiresAt {
            showUndo(AppUndoToken(id: id, expiresAt: deadline), message: "حُفظ التغيير")
        }
        return result
    }

    #if DEBUG
    /// UI fixtures only: runs a command as its real producer (for example the Shortcut) would.
    @discardableResult
    func executeFixtureCommand(_ envelope: CommandEnvelope) async -> Bool {
        guard let outcome = try? await bus.execute(envelope, now: prayerNow()) else { return false }
        return outcome.status == .applied || outcome.status == .duplicate
    }
    #endif
    /// The six default categories, only while the store has no category at all (the handler checks again inside its
    /// transaction). One shared attempt: the money home and the expense screen can both ask at once, and a busy writer
    /// is retried briefly so the first expense screen does not open with no categories.
    func seedMoneyDefaults() async {
        if let moneySeed { return await moneySeed.value }
        guard ((try? ModelContext(container).fetchCount(FetchDescriptor<MadarData.Category>())) ?? 1) == 0 else { return }
        let task = Task { @MainActor in
            for attempt in 0..<5 {
                do { try await executeMoneyCommand("money.seedCategories"); return }
                catch BackupOperationError.busy where attempt < 4 { try? await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
        }
        moneySeed = task; await task.value; moneySeed = nil
    }
    private var moneySeed: Task<Void, Never>?

    /// The old-Madar move (item 24) and its DEBUG trial: one command through the bus without the per-command reload and
    /// reminder re-plan; the caller holds the write and reloads once at the end. Returns the bus status.
    func executeImportCommand(_ name: String, payload: [String: MadarCore.JSONValue], id: UUID) async throws -> String {
        let now = prayerNow()
        let result = try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
        return result.status == .applied ? "applied" : result.status == .duplicate ? "duplicate" : "rejected:" + (result.reason ?? "")
    }
    /// Quiesces every other writer for a whole old-Madar move or its undo, then reloads, republishes and refreshes widgets once.
    func performLegacyMove<T>(_ body: (Date) async throws -> T) async throws -> T {
        guard lockController?.canPresent(.app) ?? protectedDataAuthorized else { throw DataError.authenticationFailed }
        // Every other writer (UI, inbox, backup) waits, so the before/after snapshots hold only the move's own rows.
        try await quiesceWriters()
        defer { resumeWriters() }
        let now = prayerNow()
        let result: T
        do { result = try await body(now) } catch { try? reload(); try? publishSnapshot(); throw error }
        try reload(); try publishSnapshot(); WidgetCenter.shared.reloadAllTimelines()
        Task { await refreshPrayerNotifications() }
        return result
    }

    func executeMoneyCommand(_ name: String, payload: [String: MadarCore.JSONValue] = [:], id: UUID = UUID()) async throws {
        guard lockController?.canPresent(.app) ?? protectedDataAuthorized else { throw DataError.authenticationFailed }
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        let now = prayerNow()
        let result = try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
        guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "money command") }
        if result.status == .applied {
            // The command is committed: a failed refresh must not read as a failed save, or a retry with a new ID records it twice.
            do { try reload(); try publishSnapshot() } catch { errorMessage = "حُفظ التغيير، لكن تعذّر تحديث العرض. أغلق الصفحة وافتحها مرة أخرى." }
            // A confirmed spend can cross a category's 80% line (M5-V10); re-plan room reminders through the one arbiter.
            Task { await refreshPrayerNotifications() }
        }
        if let token = result.undoToken { showUndo(.init(id: token, expiresAt: now.addingTimeInterval(600)), message: name == "money.confirmSalary" ? "فُتحت الدورة" : name == "money.logExpense" ? "سُجّل المصروف" : name == "money.deleteTransaction" ? "حُذفت الحركة" : name == "money.removeAccount" ? "حُذف الحساب" : "حُفظ التغيير") }
    }

    func executeBookCommand(_ name: String, payload: [String: MadarCore.JSONValue], id: UUID = UUID(), undoMessage: String = "حُفظ في المحبرة") async throws {
        guard lockController?.canPresent(.app) ?? protectedDataAuthorized else { throw DataError.authenticationFailed }
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        #if DEBUG
        // One failed command in an explicitly named synthetic UI store; never applies to an owner store.
        if failFirstNotebookSave && name == "notebook.savePrivate" {
            failFirstNotebookSave = false
            throw DataError.invalidValue("notebook UI fixture write failure")
        }
        if failFirstGoodreadsImport && name == "book.importGoodreads" {
            failFirstGoodreadsImport = false
            throw DataError.invalidValue("تعذّرت إضافة كتب Goodreads إلى المحبرة. حاول مرة أخرى.")
        }
        #endif
        let now = prayerNow()
        let result = try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
        guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "تعذّر حفظ الكتاب") }
        try reload(); try publishSnapshot()
        if ["book.importPDF", "book.importEPUB", "book.importGoodreads", "book.savePaper", "book.updatePaper", "book.delete", "book.restore"].contains(name) {
            await reconcileSpotlightIndex()
        }
        if let token = result.undoToken { showUndo(.init(id: token, expiresAt: now.addingTimeInterval(600)), message: undoMessage) }
        else if BookCommand.parse(name, payload)?.isUndoable == false { clearUndo() }
    }

    var diaryStagingDirectory: URL { commandAdapter.diaryStagingDirectory }
    var bookStagingDirectory: URL { commandAdapter.bookStagingDirectory }
    func executeDiaryCommand(_ name: String, payload: [String: MadarCore.JSONValue], id: UUID = UUID()) async throws {
        guard !name.hasPrefix("diary.") || (lockController?.canPresent(.notes) ?? protectedDataAuthorized) else { throw DataError.invalidValue("المذكرات مقفلة") }
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
#if DEBUG
        if name == "habit.complete",
           ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil,
           let milliseconds = Int(ProcessInfo.processInfo.environment["MADAR_UI_HABIT_WRITE_HOLD_MS"] ?? ""),
           (1...5000).contains(milliseconds) {
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
#endif
        let now = prayerNow()
        func run() async throws -> CommandOutcome {
            let result = try await bus.execute(CommandEnvelope(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
            guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "diary command") }
            try reload(); try publishSnapshot()
            return result
        }
        // F02/V12: a habit change, an intention or a letter reschedules its reminder (a met habit or written intention stops reminding).
        let reschedules = name.hasPrefix("habit.") || ["diary.setIntention", "diary.sealLetter", "diary.openLetter", "diary.rescheduleLetter", "diary.refreshLetters"].contains(name)
        let result = reschedules ? try await withSerializedPrayerNotificationMutation { try await run() } : try await run()
        if let id = result.undoToken {
            let token = AppUndoToken(id: id, expiresAt: now.addingTimeInterval(600))
            showUndo(token, message: name == "habit.archive" ? "حُذفت العادة" : name == "habit.pause" ? "جُمّدت العادة" : name == "habit.resume" ? "عادت العادة" : name == "habit.complete" ? "سُجّلت" : name.hasPrefix("habit.") ? "حُفظت العادة" : name == "widget.save" ? "حُفظت الودجة" : name == "widget.delete" ? "حُذفت الودجة" : name == "bahw.saveUpcomingDay" ? "حُفظ اليوم" : name == "bahw.deleteUpcomingDay" ? "حُذف اليوم" : name == "diary.deleteEntry" ? "حُذف السطر" : name == "diary.setIntentionResult" ? (payload["result"] == .null ? "مُسحت النتيجة" : "حُفظت النتيجة") : name.contains("Intention") ? "حُفظت النيّة" : "حُفظ السطر")
            if name == "diary.deleteEntry" { scheduleDiaryMediaCleanup(after: token.expiresAt) }
        }
    }
    /// Keep deleted diary attachments restorable during the ten-minute undo window, then apply the
    /// dictionary's tombstone policy only to Media with no remaining live references.
    private func scheduleDiaryMediaCleanup(after expiry: Date) {
        Task { [weak self] in
            guard let self else { return }
            let delay = max(0, expiry.timeIntervalSince(self.prayerNow()))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let pinned = try? self.pendingInbox.unacknowledgedCommandIDs() else { return }
            try? self.commandAdapter.purgeExpiredReceipts(pinnedIDs: pinned, now: self.prayerNow())
        }
    }
    /// M3-V09: a Day One import (or its undo) is one app-process write (RA2), gated like a diary command so
    /// backup/restore can quiesce it and a locked diary refuses it.
    func performDiaryImport<T>(_ body: (Date) async throws -> T) async throws -> T {
        guard lockController?.canPresent(.notes) ?? protectedDataAuthorized else { throw DataError.invalidValue("المذكرات مقفلة") }
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        let result = try await body(prayerNow())
        try reload(); try publishSnapshot(); WidgetCenter.shared.reloadAllTimelines()
        return result
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
        if changes["core.spotlightIndex"] != nil { await reconcileSpotlightIndex(reportFailure: true) }
    }
    func attachPrayerNotifications(_ coordinator: PrayerNotificationCoordinator) async {
        prayerNotifications = coordinator
        await refreshEligibleDiaryLettersForNotificationLifecycle()
        await coordinator.attach(to: self)
    }
    /// Diary eligibility is a forward-only, protected-state change. Reconcile it
    /// when the app opens or returns to the foreground, but only after the diary
    /// access gate is open; the notification coordinator then sees the new state.
    func refreshEligibleDiaryLettersForNotificationLifecycle() async {
        guard lockController?.canPresent(.notes) ?? protectedDataAuthorized,
              notificationStoreAccessAvailable else { return }
        do { try await AppDiaryService(app: self).refreshLetters() }
        catch BackupOperationError.busy { }
        catch { errorMessage = "تعذّر تحديث موعد الرسالة. \(madarUserMessage(error))" }
    }
    func refreshPrayerNotifications() async {
        do { try await prayerNotifications?.refresh() }
        catch { errorMessage = "تعذّر تحديث تذكيرات الصلاة. \(madarUserMessage(error))" }
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
            catch { errorMessage = "تعذّر طلب إذن الإشعارات. \(madarUserMessage(error))" }
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
            catch { notificationTestResult = "FAIL — \(madarUserMessage(error))" }
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
        undoToken = nil; setUndoToast(false); expiryTask?.cancel()
    }
    func redactQuranWidgetSnapshot() throws {
        try snapshotStore.remove("quran")
        WidgetCenter.shared.reloadTimelines(ofKind: "MadarQuran")
    }
    /// Remove every room snapshot that can reveal protected progress before whole-app
    /// scope is persisted. A later publication replaces these with locked-safe copies.
    func beginPrivacyScopeTransition() { privacyScopeTransitionPending = true }
    func finishPrivacyScopeTransition() throws {
        privacyScopeTransitionPending = false
        try publishSnapshot()
    }
    func redactSensitiveWidgetSnapshots() throws {
        let names = Set(BuiltRoomWidget.allCases.map(\.rawValue) + [
            "quran", HabitShortcutSnapshot.name, WidgetCatalogSnapshot.name,
            WidgetCatalogSnapshot.valuesName, "notes", "notesToday", "privateNote", "notesMemory"
        ])
        for name in names { try snapshotStore.remove(name) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    func authorizeProtectedData() { protectedDataAuthorized = true }
    func bindContainer(_ replacement: ModelContainer) {
        container = replacement; store = SettingsStore(context: ModelContext(replacement), schema: schema)
        undoToken = nil; setUndoToast(false); expiryTask?.cancel()
    }
    private func showUndo(_ token: AppUndoToken, message: String) {
        undoToken = token; undoMessage = message; setUndoToast(true); expiryTask?.cancel(); toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoToastSeconds))
            guard !Task.isCancelled else { return }
            if self?.undoToken?.id == token.id { self?.setUndoToast(false) }
        }
        expiryTask = Task { [weak self] in
            let delay = max(0, token.expiresAt.timeIntervalSince(self?.prayerNow() ?? .now))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if self?.undoToken?.id == token.id { self?.undoToken = nil; self?.setUndoToast(false) }
        }
    }
    private func clearUndo() {
        undoToken = nil; setUndoToast(false)
        expiryTask?.cancel(); expiryTask = nil
        toastTask?.cancel(); toastTask = nil
    }
    var homeCity: [String: JSONValue] { if case .object(let place) = values["core.homeCity"] { place } else { [:] } }
    var cityName: String { if case .string(let name) = homeCity["name"] { name } else { "" } }
    var activePlace: ActivePlace {
        let city = homeCity
        guard case .number(let lat) = city["lat"], case .number(let lon) = city["lon"], case .string(let zone) = city["tz"], let place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: zone) else { return .riyadh }
        return place
    }
    func publishSnapshot() throws {
        if privacyScopeTransitionPending {
            try redactSensitiveWidgetSnapshots()
            return
        }
        let instant = prayerNow()
        try pendingInbox.publishGeneration(inboxGeneration())
        try publishNotificationBudget(at: instant)
        let prayerSource=try PrayerRepository(context:ModelContext(container)),place=prayerSource.place(at:instant),options=prayerSource.calculationOptions(at:instant)
        let day = GregorianDay.containing(instant, in: place.timeZone)
        let prayers = [day.adding(days: -1), day].compactMap { PrayerTimesEngine.calculate(day: $0, place: place,options:options) }
        guard let key = try? MadarDay.resolve(instant: instant, place: place, boundary: DayBoundary(rawValue: string("core.dayStart")) ?? .fajr, prayerDays: prayers, hijriSource: HijriSource(rawValue: string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(number("core.hijriOffset"))) else {
            try snapshotStore.remove("foundation")
            try? snapshotStore.remove("quran")
            for room in BuiltRoomWidget.allCases {try? snapshotStore.remove(room.rawValue)}
            try? snapshotStore.remove(HabitShortcutSnapshot.name)
            try? snapshotStore.remove(WidgetCatalogSnapshot.name)
            try? snapshotStore.remove(WidgetCatalogSnapshot.valuesName)
            return
        }
        let snapshot = SnapshotEnvelope(name: "foundation", generatedAt: instant, validUntil: instant.addingTimeInterval(3600), dayKey: key.dayKey, tzID: place.timeZoneID, privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: string("core.firstCalendar"), numerals: string("core.numerals")))
        try snapshotStore.write(snapshot)
        try publishRoomWidgetSnapshots(at:instant)
        publishPrayerNextSnapshot(at: instant, tzID: place.timeZoneID, dayKey: key.dayKey)
        if string("core.faceIDLock") == "app" {
            try redactQuranWidgetSnapshot()
        } else {
            let quran = AppQuranService(session: self, clock: { instant })
            do { try snapshotStore.write(quran.widgetSnapshot()); WidgetCenter.shared.reloadTimelines(ofKind: "MadarQuran") }
            catch { try? redactQuranWidgetSnapshot() }
        }
        try publishWidgetCatalog(at: instant)
    }
    /// The next-prayer widget reads this file only; it holds times, never counts or streaks (RP9, RU2).
    private func publishPrayerNextSnapshot(at instant: Date, tzID: String, dayKey: String) {
        let names: [Prayer: String] = [.fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"]
        var items: [PrayerNextSnapshot.Item] = []
        for offset in [0, 1] {
            guard let day = try? prayerSnapshot(at: instant.addingTimeInterval(Double(offset) * 86_400)).today else { continue }
            for cell in day.cells {
                guard let at = cell.prayerTime, !items.contains(where: { $0.at == at }) else { continue }
                items.append(.init(prayer: cell.reference.prayer.rawValue, name: names[cell.reference.prayer] ?? "", at: at))
            }
        }
        let snapshotItems = PrayerNextSnapshot.itemsForTodayAndTomorrow(
            items, at: instant, timeZone: TimeZone(identifier: tzID) ?? .current
        )
        guard let last = snapshotItems.map(\.at).max(), last > instant else { try? snapshotStore.remove("prayerNext"); return }
        let envelope = SnapshotEnvelope(name: "prayerNext", generatedAt: instant, validUntil: last, dayKey: dayKey, tzID: tzID, privacy: SnapshotPrivacy(),
                                        payload: PrayerNextSnapshot(items: snapshotItems, numerals: string("core.numerals") == "western" ? "western" : "hindi"))
        try? snapshotStore.write(envelope)
    }
}

func prayerUITestClock(_ fallback: Date) -> Date {
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
