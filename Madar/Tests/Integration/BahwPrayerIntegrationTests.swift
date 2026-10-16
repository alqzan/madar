import XCTest
import MadarData
@testable import Madar

@MainActor final class BahwPrayerIntegrationTests: XCTestCase {
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
        XCTAssertEqual(model.nextName, "الفجر")
        XCTAssertFalse(model.nextTime?.isEmpty ?? true)
        XCTAssertTrue(model.nextAfter?.contains("بعد") == true)
        // Tomorrow's Fajr must not be highlighted as an unlogged arch in today's five.
        XCTAssertFalse(model.arches.contains { $0.next })
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
