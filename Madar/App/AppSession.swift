import Foundation
import Observation
import SwiftData
import MadarData
import MadarCore
import MadarSnapshots
import WidgetKit
import MadarCommands

typealias JSONValue = MadarData.JSONValue
struct AppUndoToken { let id: UUID; let expiresAt: Date }

@MainActor @Observable
final class AppSession {
    private(set) var container: ModelContainer
    let managedStore: ManagedDataStore?
    let snapshotStore: SnapshotStore
    private(set) var maintenanceInProgress = false
    private var pendingWrites = 0
    var backupService: (any BackupUIService)?
    var syncService: (any SyncUIService)?
    var lockController: MadarLockController?
    private(set) var protectedDataAuthorized = false
    let schema: SettingsSchema
    var store: SettingsStore
    private(set) var values: [String: JSONValue] = [:]
    private(set) var undoToken: AppUndoToken?
    private(set) var undoMessage = ""
    var errorMessage: String?
    var onboardingComplete = false
    var selectedTab = "foundation"
    var settingsQuery = ""
    private let bus: CommandBus
    private var expiryTask: Task<Void, Never>?

    static let supportedKeys = ["core.dayStart", "core.firstCalendar", "core.hijriSource", "core.hijriOffset", "core.weekStart", "core.theme", "core.numerals", "core.homeCity", "core.faceIDLock"]

    init(container: ModelContainer, managedStore: ManagedDataStore? = nil, groupDirectory: URL? = nil) throws {
        self.container = container
        self.managedStore = managedStore
        guard let group = groupDirectory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { throw DataError.missingAppGroup }
        snapshotStore = SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
        bus = CommandBus(adapter: DurableCommandAdapter(containerProvider: { try managedStore?.containerForTransaction() ?? container }, lockDirectory: managedStore?.commandLockURL.deletingLastPathComponent() ?? group))
        schema = try SettingsSchema.bundled()
        store = SettingsStore(context: container.mainContext, schema: schema)
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
    }
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
                let result = try await bus.execute(CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(token.id.uuidString)])))
                guard result.status == .applied else { throw DataError.undoExpired }
                try reload(); undoToken = nil; expiryTask?.cancel(); try publishSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
            } catch { errorMessage = "لم يكتمل التراجع. \(error.localizedDescription)" }
        }
    }
    private func execute(name: String, values: [String: JSONValue], message: String, completion: (() -> Void)? = nil) {
        guard beginWrite() else { return }
        Task {
            defer { pendingWrites -= 1 }
            do {
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
                WidgetCenter.shared.reloadAllTimelines(); completion?()
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
        while pendingWrites > 0 { await Task.yield() }
    }
    func resumeWriters() { maintenanceInProgress = false }
    func applySettingsAndWait(_ changes: [String: JSONValue]) async throws {
        guard beginWrite() else { throw BackupOperationError.busy }
        defer { pendingWrites -= 1 }
        let typed = try changes.mapValues { try JSONDecoder().decode(MadarCore.JSONValue.self, from: $0.canonicalData()) }
        let result = try await bus.execute(CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(typed)])))
        guard result.status == .applied || result.status == .duplicate else { throw DataError.invalidValue(result.reason ?? "settings") }
        try reload(); try publishSnapshot()
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
            let delay = max(0, token.expiresAt.timeIntervalSinceNow)
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
