import XCTest
import SwiftUI
import MadarData
import MadarCore
import MadarPrayer
import SwiftData
@testable import Madar

@MainActor final class BahwPrayerIntegrationTests: XCTestCase {
    func testPrayerTodayTimelineStopsTickingWhenRoomIsHidden() {
        let start = Date(timeIntervalSince1970: 1_760_000_123)
        let hidden = PrayerTodayMinuteTimelineSchedule(isActive: false)
        XCTAssertTrue(Array(hidden.entries(from: start, mode: .normal)).isEmpty)

        let visible = PrayerTodayMinuteTimelineSchedule(isActive: true)
        let entries = Array(visible.entries(from: start, mode: .normal).prefix(3))
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].timeIntervalSince(entries[0]), 60, accuracy: 0.001)
        XCTAssertEqual(entries[2].timeIntervalSince(entries[1]), 60, accuracy: 0.001)
    }

    func testLegacyPrayerLayoutDropsRetiredQadaBacklogBlock() {
        let legacy = MadarData.JSONValue.object([
            "blocks": .array(["next", "riwaq", "pending", "hali", "qada", "qiyam"].map(MadarData.JSONValue.string)),
            "pinned": .array(["next", "riwaq"].map(MadarData.JSONValue.string)),
            "hidden": .array([.string("qada")]),
            "sizes": .object([:])
        ])
        let layout = PrayerHomeLayout(legacy)
        XCTAssertFalse(layout.order.contains("qada"))
        XCTAssertFalse(layout.visible.contains("qada"))
        XCTAssertFalse(layout.payload.object?["blocks"]?.array?.compactMap(\.string).contains("qada") ?? false)
    }

    func testUpcomingIsReadOncePerStoreGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "UpcomingCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "core.weekStart": .string("saturday")])
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        let service = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!)
        let first = service.upcoming(limit: 50)
        let behindBack = ModelContext(app.container)
        let row = UpcomingDay(); row.title = "يوم الاختبار"; row.calendar = "gregorian"; row.month = 3; row.day = 9; row.repeats = "yearly"
        behindBack.insert(row); try behindBack.save()
        XCTAssertEqual(service.upcoming(limit: 50).map(\.id), first.map(\.id), "Same store generation: the cached list is returned")
        try app.reload()
        XCTAssertTrue(service.upcoming(limit: 50).contains { $0.title == "يوم الاختبار" }, "A new generation re-reads")
        XCTAssertEqual(service.upcoming(limit: 1).count, 1)
    }

    func testHabitOrbitClockUsesTheSelectedDayBoundaryAndCalendar() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "HabitOrbitClock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "core.weekStart": .string("saturday")])
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        let service = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!)
        let positions = service.habitOrbitPositions()
        // Thursday, 20:00: five days into the Saturday week, fourteen into October, 287 into 2026.
        XCTAssertEqual(try XCTUnwrap(positions[.daily]), 20.0 / 24, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(positions[.weekly]), (5 + 20.0 / 24) / 7, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(positions[.monthly]), (14 + 20.0 / 24) / 31, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(positions[.yearly]), (287 + 20.0 / 24) / 365, accuracy: 0.000001)
        let sameMinute = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T20:00:30+03:00")!).habitOrbitPositions()
        XCTAssertEqual(try XCTUnwrap(sameMinute[.daily]), 20.0 / 24 + 30.0 / 86_400, accuracy: 0.000001)
        XCTAssertGreaterThan(try XCTUnwrap(sameMinute[.daily]), try XCTUnwrap(positions[.daily]))
        _ = try settings.stage(["core.dayStart": .string("fajr"), "core.firstCalendar": .string("hijri")]); try context.save(); try app.reload()
        let sameMinuteAfterSettings = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T20:00:30+03:00")!).habitOrbitPositions()
        XCTAssertNotEqual(try XCTUnwrap(sameMinuteAfterSettings[.daily]), try XCTUnwrap(sameMinute[.daily]))
        let early = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T04:00:00+03:00")!)
        XCTAssertEqual(early.today.description, "2026-10-14")
        let beforeFajr = early.habitOrbitPositions()
        XCTAssertGreaterThan(try XCTUnwrap(beforeFajr[.daily]), 0.9)
        XCTAssertLessThan(try XCTUnwrap(beforeFajr[.daily]), 1)
        // 14 October is 3 Jumada I 1448: the Hijri month has just begun, rather than half October.
        XCTAssertLessThan(try XCTUnwrap(beforeFajr[.monthly]), 0.15)
    }
    func testUpcomingRingsUseOneYearScale() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwRing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        let service = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T15:00:00+03:00")!)
        XCTAssertEqual(service.upcomingCloseness(daysLeft: 116), 249.0 / 365, accuracy: 0.000001)
        XCTAssertEqual(service.upcomingCloseness(daysLeft: 213), 152.0 / 365, accuracy: 0.000001)
        XCTAssertEqual(service.upcomingCloseness(daysLeft: 0), 1)
        XCTAssertEqual(service.upcomingCloseness(daysLeft: 700), 0)
    }
    func testLobbyKeepsNextFajrAfterIsha() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwPrayer-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        let now = ISO8601DateFormatter().date(from: "2026-10-15T22:00:00+03:00")!
        let service = AppBahwService(session: app, evaluationDate: now)
        let model = try XCTUnwrap(service.prayer())
        XCTAssertEqual(model.nextName, "الفجر غدًا")
        XCTAssertFalse(model.nextTime?.isEmpty ?? true)
        XCTAssertTrue(model.nextAfter?.contains("بعد") == true)
        // Tomorrow's Fajr must not be highlighted as an unlogged arch in today's five.
        XCTAssertFalse(model.arches.contains { $0.next })
    }
    func testPrayerSnapshotOffMainMatchesTheRepositorySnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwPrayerOffMain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        let now = ISO8601DateFormatter().date(from: "2026-10-15T22:00:00+03:00")!
        let expected = try PrayerRepository(context: ModelContext(container)).snapshot(now: now)
        let actual = try await app.prayerSnapshotOffMain(at: now)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(try app.prayerSnapshot(at: now), expected, "The async result joins the existing per-minute cache")
        let service = AppBahwService(session: app, evaluationDate: now)
        XCTAssertEqual(service.prayer(snapshot: actual), service.prayer())
    }
    /// §7.2: on Friday the Dhuhr arch and the next-prayer line read «الجمعة» in the lobby too.
    func testFridayDhuhrReadsJumuahInTheLobby() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwFriday-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        let friday = try XCTUnwrap(AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-16T08:40:00+03:00")!).prayer())
        XCTAssertEqual(friday.nextName, "الجمعة")
        XCTAssertEqual(friday.arches.first { $0.id == "dhuhr" }?.name, "الجمعة")
        let thursday = try XCTUnwrap(AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T08:40:00+03:00")!).prayer())
        XCTAssertEqual(thursday.nextName, "الظهر")
    }
}
