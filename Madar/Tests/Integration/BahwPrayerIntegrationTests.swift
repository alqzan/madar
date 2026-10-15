import XCTest
import MadarData
@testable import Madar

@MainActor final class BahwPrayerIntegrationTests: XCTestCase {
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
}
