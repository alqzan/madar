import XCTest
import MadarCore
import MadarData
@testable import Madar

/// Both calendars always (owner, 15 Oct): a letter that opens on a Hijri day names its Gregorian day too.
@MainActor final class LetterWaitingDatesTests: XCTestCase {
    func testHijriTriggerShowsBothCalendars() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LetterDates-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let service = AppDiaryService(app: app)
        // 1 Ramadan 1448 (Umm al-Qura) falls in February 2028.
        let text = service.waitingFor(.hijriDate, value: "1448-09-01", target: nil)
        XCTAssertTrue(text.hasPrefix("تُفتح في "), text)
        XCTAssertTrue(text.contains("رمضان"), text)
        XCTAssertTrue(text.contains("فبراير"), text)
        XCTAssertEqual(service.waitingFor(.hijriDate, value: nil, target: nil), "تُفتح في يومها")
    }
}
