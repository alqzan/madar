import XCTest
@testable import MadarQuran

final class ReviewProgressTests: XCTestCase {
    func testRecentIncludesPartialPageThenRiskOrderAndSeparateFinalTest() throws {
        let sections = QuranReviewSection.make(regular: [280, 281, 282, 283, 284, 140, 141, 21, 22], recent: Set(280...284), partialRecent: [285], tests: [22, 23])
        XCTAssertEqual(sections, [.init(kind: .recent, pages: Array(280...285)), .init(kind: .due, pages: [140, 141]), .init(kind: .due, pages: [21]), .init(kind: .test, pages: [22, 23])])
        XCTAssertEqual(try JSONDecoder().decode([QuranReviewSection].self, from: JSONEncoder().encode(sections)), sections)
    }
    func testAdjacentOldTestStaysSeparateAndDuplicatePagesAppearOnce() {
        XCTAssertEqual(QuranReviewSection.make(regular: [3, 3, 4, 10], recent: [3, 4], partialRecent: [4], tests: [5, 5]),
            [.init(kind: .recent, pages: [3, 4]), .init(kind: .due, pages: [10]), .init(kind: .test, pages: [5])])
        XCTAssertEqual(QuranReviewSection.make(regular: [3, 4, 5, 6], recent: [3, 4], partialRecent: [], tests: [7]),
            [.init(kind: .mixed, pages: [3, 4, 5, 6]), .init(kind: .test, pages: [7])])
    }
}
