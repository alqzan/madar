import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import CryptoKit
@testable import Madar

@MainActor final class LegacyHabitTrialTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private let raw = #"{"habits":[{"id":"synthetic","name":"عادة تجريبية","icon":"leaf","color":"green","logs":["2026-10-21","2026-10-22","2026-10-22"],"updatedAt":1792670400000,"unknown":"kept"}],"frozenHabits":["synthetic"],"deleted":{"habitlog:synthetic:2026-10-23":1792832400000}}"#
    private func records(_ container: ModelContainer) throws -> [DataRecord] {
        try RecordBridge.all(ModelContext(container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
    }
    func testNewFreezeUsesMadarBoundaryWhileSourceLogKeepsItsDay() throws {
        let cases = [("fajr", "02", "2026-10-24"), ("midnight", "02", "2026-10-25"),
                     ("maghrib", "12", "2026-10-24"), ("maghrib", "20", "2026-10-25")]
        let backup = Data(#"{"habits":[{"id":"h","name":"عادة","logs":["2026-10-25"]}],"frozenHabits":["h"]}"#.utf8)
        for (boundary, hour, expected) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitBoundary-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try ManagedDataStore(root: root), context = ModelContext(store.container)
            _ = try SettingsStore(context: context).stage(["core.dayStart": .string(boundary)]); try context.save()
            let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T\(hour):00:00+03:00"))
            _ = try LegacyHabitTrial.importBackup(backup, to: store.container, zone: zone, now: now)
            XCTAssertEqual(try context.fetch(FetchDescriptor<HabitPause>()).first?.fromDayKey, expected, boundary + hour)
            XCTAssertEqual(try context.fetch(FetchDescriptor<HabitEvent>()).first?.dayKey, "2026-10-25")
            let before = try records(store.container)
            _ = try LegacyHabitTrial.importBackup(backup, to: store.container, zone: zone, now: now.addingTimeInterval(86400))
            XCTAssertEqual(try records(store.container), before, "replay across a boundary must keep the first observation")
        }
    }
    /// Item 24: a plain daily habit the owner already keeps under the same name takes the old days; nothing duplicates,
    /// and a day the owner already logged is not logged twice. A weekly habit of the same name keeps its own rules.
    func testNativeDailyHabitWithTheSameNameTakesTheOldDays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyHabitNative-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root), context = ModelContext(store.container)
        func native(_ name: String, _ frequency: String) -> Habit {
            let habit = Habit(); habit.name = name; habit.kind = "custom"; context.insert(habit)
            let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = "2026-10-01"; policy.frequency = frequency; context.insert(policy)
            return habit
        }
        let daily = native(" عادة تجريبية ", "daily")
        let logged = HabitEvent(); logged.habitID = daily.id; logged.dayKey = "2026-10-22"; logged.periodKey = "2026-10-22"; logged.delta = 1; context.insert(logged)
        try context.save()
        let plan = try LegacyHabitImport.plan(backup: Data(raw.utf8), observedDay: try GregorianDay("2026-10-25"), zone: zone, uuid: StableIdentity.uuid(for:))
        let counts = try LegacyHabitTrial.apply(plan, to: store.container, zone: zone)
        XCTAssertEqual(counts["habits.created"], nil); XCTAssertEqual(counts["habits.keptNative"], 1)
        XCTAssertEqual(counts["events.keptNative"], 1, "2026-10-22 was already logged natively")
        let check = ModelContext(store.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Habit>()).count, 1)
        let days = try check.fetch(FetchDescriptor<HabitEvent>()).filter { $0.habitID == daily.id }.map(\.dayKey).sorted()
        XCTAssertEqual(days, ["2026-10-21", "2026-10-22", "2026-10-23"])
        XCTAssertTrue(try check.fetch(FetchDescriptor<HabitPause>()).isEmpty, "the native habit keeps its own freeze state")

        let other = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyHabitWeekly-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: other) }
        let weeklyStore = try ManagedDataStore(root: other), weeklyContext = ModelContext(weeklyStore.container)
        let weekly = Habit(); weekly.name = "عادة تجريبية"; weekly.kind = "custom"; weeklyContext.insert(weekly)
        let policy = HabitPolicy(); policy.habitID = weekly.id; policy.effectiveFrom = "2026-10-01"; policy.frequency = "weekly"; weeklyContext.insert(policy)
        try weeklyContext.save()
        let separate = try LegacyHabitTrial.apply(plan, to: weeklyStore.container, zone: zone)
        XCTAssertEqual(separate["habits.created"], 1, "a weekly habit never absorbs old daily times")
    }

    /// The native diary link survives both an old-app merge and a real encrypted package restore, including replay.
    func testNativeMemorySurvivesLegacyMoveAndEncryptedRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitMemoryRestore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root.appendingPathComponent("Source"))
        let context = ModelContext(store.container)
        let habit = Habit(); habit.name = "عادة تجريبية"; habit.kind = "custom"; context.insert(habit)
        let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = "2026-10-01"; policy.frequency = "daily"; context.insert(policy)
        let entry = Entry(); entry.dayKey = "2026-10-22"; entry.text = "ذكرى اصطناعية محفوظة"; context.insert(entry)
        let event = HabitEvent(); event.habitID = habit.id; event.dayKey = entry.dayKey; event.periodKey = entry.dayKey
        event.delta = 1; event.entryID = entry.id; context.insert(event)
        let media = Media(); let bytes = Data("synthetic diary attachment".utf8)
        media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(); context.insert(media)
        try context.save()
        let ids = (habit.id, entry.id, event.id, media.id)
        let backup = Data(#"{"habits":[{"id":"h","name":"عادة تجريبية","logs":["2026-10-21","2026-10-22","2026-10-23"]}]}"#.utf8)
        _ = try LegacyHabitTrial.importBackup(backup, to: store.container, zone: zone, now: Date())
        let expected = try records(store.container)
        let coordinator = BackupCoordinator(store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        let password = "synthetic memory password"
        try await coordinator.configurePassphrase(password)
        let receipt = try await coordinator.export(kind: .automatic)
        XCTAssertEqual(receipt.fileURL.pathExtension, "madarbackupset")
        for mode in [RestoreMode.merge, .replace] {
            let targetRoot = root.appendingPathComponent(UUID().uuidString)
            let target = try ManagedDataStore(root: targetRoot)
            let restore = BackupCoordinator(store: target, backupDirectory: root.appendingPathComponent("Safety-" + UUID().uuidString), keyStore: MemoryBackupKeyStore())
            try await restore.configurePassphrase(password)
            let preview = try await restore.preview(file: receipt.fileURL, passphrase: password)
            _ = try await restore.restore(preview: preview, mode: mode)
            // Reopen from disk rather than trusting the context used for restoration.
            let reopened = try ManagedDataStore(root: targetRoot), check = ModelContext(reopened.container)
            let events = try check.fetch(FetchDescriptor<HabitEvent>()).filter { $0.habitID == ids.0 }
            XCTAssertEqual(events.map(\.dayKey).sorted(), ["2026-10-21", "2026-10-22", "2026-10-23"])
            let remembered = try XCTUnwrap(events.first { $0.dayKey == "2026-10-22" })
            XCTAssertEqual(remembered.id, ids.2); XCTAssertEqual(remembered.entryID, ids.1)
            XCTAssertEqual(try check.fetch(FetchDescriptor<Entry>()).first { $0.id == ids.1 }?.text, "ذكرى اصطناعية محفوظة")
            XCTAssertEqual(try check.fetch(FetchDescriptor<Media>()).first { $0.id == ids.3 }?.data, bytes)
            let beforeReplay = try records(reopened.container)
            _ = try LegacyHabitTrial.importBackup(backup, to: reopened.container, zone: zone, now: Date().addingTimeInterval(86400))
            XCTAssertEqual(try records(reopened.container), beforeReplay, "Legacy replay after restore must keep the linked memory unchanged")
            XCTAssertEqual(Set(expected.map { $0.model + $0.id.uuidString }), Set(beforeReplay.map { $0.model + $0.id.uuidString }))
            let replay = try await restore.preview(file: receipt.fileURL, passphrase: password)
            XCTAssertEqual(replay.additions, 0)
            if mode == .merge { XCTAssertEqual(replay.updates, 0) }
        }
    }
    func testImportPreservesDaysDeletionFreezeAndReplayAfterNativeEdit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyHabitTrial-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let observed = try GregorianDay("2026-10-25")
        let plan = try LegacyHabitImport.plan(backup: Data(raw.utf8), observedDay: observed, zone: zone, uuid: StableIdentity.uuid(for:))
        let imported = try LegacyHabitTrial.apply(plan, to: store.container, zone: zone)
        XCTAssertEqual(imported["habits.created"], 1); XCTAssertEqual(imported["events.created"], 3)
        let context = ModelContext(store.container)
        let habit = try XCTUnwrap(context.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(habit.kind, "custom"); XCTAssertNil(habit.linkedSource)
        let policy = try XCTUnwrap(context.fetch(FetchDescriptor<HabitPolicy>()).first)
        XCTAssertEqual(policy.frequency, "daily"); XCTAssertEqual(policy.measure, "once"); XCTAssertEqual(policy.target, 1)
        let events = try context.fetch(FetchDescriptor<HabitEvent>()).sorted { $0.dayKey < $1.dayKey }
        XCTAssertEqual(events.map(\.dayKey), ["2026-10-21", "2026-10-22", "2026-10-23"])
        XCTAssertEqual(events.map(\.periodKey), events.map(\.dayKey)); XCTAssertEqual(events.map(\.delta), [1,1,1])
        XCTAssertTrue(events.allSatisfy { $0.dayPolicy == "legacy@0" && $0.tzID == "Asia/Riyadh" })
        XCTAssertNotNil(events.last?.deletedAt)
        let pause = try XCTUnwrap(context.fetch(FetchDescriptor<HabitPause>()).first)
        XCTAssertEqual(pause.fromDayKey, "2026-10-25"); XCTAssertNil(pause.toDayKey)
        let reading = try XCTUnwrap(HabitRepository(context: context).readings(at: observed.date(in: zone).addingTimeInterval(43200)).first)
        XCTAssertTrue(reading.paused); XCTAssertEqual(reading.summary.current?.outcome, .excluded)
        XCTAssertEqual(reading.summary.periods.first?.value, 1)
        // Replays retain owner edits and native tombstones, including a resumed pause.
        habit.name = "اسم محلي"; events[0].deletedAt = Date(); pause.toDayKey = "2026-10-26"
        try context.save()
        let before = try records(store.container)
        let replay = try LegacyHabitTrial.apply(plan, to: store.container, zone: zone)
        XCTAssertEqual(replay.filter { $0.key.hasSuffix(".created") }.values.reduce(0,+), 0)
        XCTAssertEqual(try records(store.container), before)
        let archives = try context.fetch(FetchDescriptor<ImportLink>())
        XCTAssertEqual(archives.count, 2)
        XCTAssertTrue(archives.contains { $0.unmappedJSON.flatMap { String(data: $0, encoding: .utf8) }?.contains("unknown") == true })
    }
    func testTombstonedHabitCannotBecomeLiveOnReplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeletedHabitTrial-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let plan = try LegacyHabitImport.plan(backup: Data(#"{"habits":[{"id":"deleted","name":"قديمة","logs":[]}],"deleted":{"deleted":1700000000000}}"#.utf8), observedDay: GregorianDay("2026-10-25"), zone: zone, uuid: StableIdentity.uuid(for:))
        _ = try LegacyHabitTrial.apply(plan, to: store.container, zone: zone)
        _ = try LegacyHabitTrial.apply(plan, to: store.container, zone: zone)
        let context = ModelContext(store.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Habit>()), 1)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Habit>()).first?.deletedAt)
        XCTAssertTrue(try HabitRepository(context: context).readings(at: .now).isEmpty)
    }
}
