import XCTest
@testable import Madar

final class LegacyMoveFileTests: XCTestCase {
    func testPasswordProtectedExportIsRecognised() {
        let json = #"{"__madar_enc":"v1","salt":"AAAA","iv":"BBBB","data":"CCCC"}"#
        XCTAssertEqual(LegacyMoveInspection.inspect(Data(json.utf8)), .encrypted)
        XCTAssertTrue(LegacyMoveError.encrypted.errorDescription?.contains("مشفّر") == true)
    }

    func testUnmovedPartsAreCountedOnlyWhenPresent() {
        let json = #"{"journalEntries":[{},{},{}],"books":[{}],"readingLogs":[],"prayerLogs":[{},{}],"habits":[]}"#
        XCTAssertEqual(LegacyMoveInspection.inspect(Data(json.utf8)), .readable(diary: 3, books: 1, readingLogs: 0, prayerLogs: 2))
        XCTAssertEqual(LegacyMoveInspection.inspect(Data(#"{"habits":[]}"#.utf8)), .readable(diary: 0, books: 0, readingLogs: 0, prayerLogs: 0))
    }

    func testNonJSONOrArrayIsNotInspectable() {
        XCTAssertNil(LegacyMoveInspection.inspect(Data("hello".utf8)))
        XCTAssertNil(LegacyMoveInspection.inspect(Data("[1,2]".utf8)))
    }
}
