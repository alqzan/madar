import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
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
