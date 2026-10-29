import Foundation
import MadarQuran
import XCTest

@MainActor final class CoverageAndPortionsTests: XCTestCase {
    private func range(_ first: Int, _ last: Int) throws -> QuranAyahRange {
        try QuranAyahRange(first: first, last: last)
    }

    private func session(_ id: String, _ first: Int, _ last: Int, at: Double = 1,
                         kind: QuranSessionKind = .hifz, deleted: Bool = false) throws -> QuranCoverageSession {
        QuranCoverageSession(id: id, kind: kind, ayahs: try range(first, last),
                             endedAt: Date(timeIntervalSince1970: at), isDeleted: deleted)
    }

    func testOverlappingAndRepeatedSessionsAreAUnionAsSpecifiedInQ02() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let result = try QuranCoverageEngine.summarize(sessions: [
            session("a", 10, 20), session("b", 15, 30), session("duplicate", 10, 20),
        ], catalog: catalog)
        XCTAssertEqual(result.ranges, [try range(10, 30)])
        XCTAssertEqual(result.coveredAyahs.count, 21)
    }

    func testRepeatedPartialPageEntersRecentReviewWithoutCompletingThePage() throws {
        let catalog = try QuranResourceCatalog.bundled()
        // Official page 22 consists of ayahIds 149...152 (2:142...145).
        let result = try QuranCoverageEngine.summarize(sessions: [session("a", 149, 150), session("b", 149, 150)], catalog: catalog)
        XCTAssertEqual(result.coveredAyahs.count, 2)
        XCTAssertFalse(result.completedPages.contains(22))
        XCTAssertEqual(result.partialRecentPortions.map(\.page), [22])
        XCTAssertEqual(result.partialRecentPortions.first?.memorizedRanges, [try range(149, 150)])
        XCTAssertEqual(try result.frontier(from: 149), 151)
        XCTAssertEqual(result.planProgress(in: try range(149, 152)), 0.5)
    }

    func testDeletingTheMiddleSessionReopensTheFirstGapAndRestoreRebuildsIt() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let first = try session("a", 1, 50, at: 1), middle = try session("b", 51, 100, at: 2)
        let last = try session("c", 101, 150, at: 3)
        let before = try QuranCoverageEngine.summarize(sessions: [first, middle, last], catalog: catalog)
        let after = try QuranCoverageEngine.summarize(sessions: [first, session("b", 51, 100, at: 2, deleted: true), last], catalog: catalog)
        XCTAssertEqual(after.ranges, [try range(1, 50), try range(101, 150)])
        XCTAssertEqual(try after.frontier(from: 1), 51)
        XCTAssertFalse(before.completedPages.subtracting(after.completedPages).isEmpty)
        let restored = try QuranCoverageEngine.summarize(sessions: [last, first, middle], catalog: catalog)
        XCTAssertEqual(restored, before, "Input order cannot change derived facts")
    }

    func testOnlyActiveHifzCreatesCoverageAndCompletionTimeIsRebuilt() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let ignored = try QuranCoverageEngine.summarize(sessions: [
            session("deleted", 1, 6236, deleted: true), session("review", 1, 6236, kind: .review),
            session("free", 1, 6236, kind: .free), session("qiyam", 1, 6236, kind: .qiyam),
            session("drill", 1, 6236, kind: .drill),
        ], catalog: catalog)
        XCTAssertTrue(ignored.ranges.isEmpty); XCTAssertTrue(ignored.memorizedAt.isEmpty)
        let first = try session("a", 1, 3, at: 10), completion = try session("b", 4, 7, at: 20)
        let duplicate = try session("c", 1, 7, at: 30)
        let original = try QuranCoverageEngine.summarize(sessions: [duplicate, completion, first], catalog: catalog)
        XCTAssertEqual(original.memorizedAt[1], Date(timeIntervalSince1970: 20))
        let deleted = try QuranCoverageEngine.summarize(sessions: [first, duplicate], catalog: catalog)
        XCTAssertEqual(deleted.memorizedAt[1], Date(timeIntervalSince1970: 30))
    }

    func testAnAyahSharedByTwoPagesIsRequiredOnBoth() throws {
        let pages = [try QuranCoveragePage(number: 1, ayahIDs: [1]),
                     try QuranCoveragePage(number: 2, ayahIDs: [1, 2])]
        let partial = try QuranCoverageEngine.summarize(sessions: [session("a", 2, 2)], pages: pages)
        XCTAssertTrue(partial.completedPages.isEmpty)
        let complete = try QuranCoverageEngine.summarize(sessions: [session("a", 1, 2)], pages: pages)
        XCTAssertEqual(complete.completedPages, [1, 2])
        XCTAssertFalse(complete.isKhatm)
    }

    func testJuzThirtyHasTwentyThreePagesAndIsNotAKhatmFromAnNaba() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let result = try QuranCoverageEngine.summarize(sessions: [session("juz30", 5673, 6236)], catalog: catalog)
        XCTAssertEqual(result.completedPages, Set(582...604))
        XCTAssertEqual(result.completedJuz, [30])
        XCTAssertTrue(result.pagesOutsideCompletedJuz.isEmpty)
        XCTAssertEqual(result.percent, 3)
        XCTAssertFalse(result.isKhatm)
        XCTAssertEqual(result.planProgress(in: try range(5673, 6236)), 1)
        XCTAssertNil(try result.frontier(from: 5673))
        XCTAssertEqual(try result.frontier(from: 1), 1)
        let firstJuz = try QuranCoverageEngine.summarize(sessions: [session("juz1", 1, 148)], catalog: catalog)
        XCTAssertEqual(firstJuz.completedPages, Set(1...21))
        XCTAssertEqual(firstJuz.completedJuz, [1])
    }

    func testOneMissingAyahCannotShowOneHundredPercentOrKhatm() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let almost = try QuranCoverageEngine.summarize(sessions: [session("almost", 1, 6235)], catalog: catalog)
        XCTAssertEqual(almost.completedPages.count, 603); XCTAssertEqual(almost.percent, 99)
        XCTAssertFalse(almost.isKhatm)
        let complete = try QuranCoverageEngine.summarize(sessions: [session("all", 1, 6236)], catalog: catalog)
        XCTAssertEqual(complete.completedPages.count, 604); XCTAssertEqual(complete.percent, 100)
        XCTAssertTrue(complete.isKhatm); XCTAssertEqual(complete.completedJuz.count, 30)
    }

    func testHalfOfAnEightLinePageEndsNearItsMiddle() throws {
        let c = try QuranResourceCatalog.bundled()
        // Pages 1 and 2 have eight lines: half of page 1 from its first ayah ends near line 4, not line 7–8.
        let half = try QuranPortionEngine.portion(from: 1, unit: .half, amount: 1, catalog: c)
        let last = try XCTUnwrap(c.ayah(id: half.last))
        XCTAssertEqual(last.page, 1)
        XCTAssertTrue((3...5).contains(last.lineEnd), "line \(last.lineEnd) of 8")
    }

    func testPortionsUseOfficialLinesAndRetainTheWholePageLegacyResult() throws {
        let c = try QuranResourceCatalog.bundled()
        // Official page 22: ayahs 149/150/151/152 end on lines 3/8/12/15.
        XCTAssertEqual(try QuranPortionEngine.portion(from: 149, unit: .ayah, amount: 5, catalog: c).last, 153)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 149, unit: .quarter, amount: 1, catalog: c).last, 149)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 149, unit: .half, amount: 1, catalog: c).last, 150)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 149, unit: .page, amount: 1, catalog: c).last, 152)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 150, unit: .page, amount: 1, catalog: c).last, 152)
        // Page 48 contains the debt ayah alone: a quarter cannot split it.
        XCTAssertEqual(try QuranPortionEngine.portion(from: 289, unit: .quarter, amount: 1, catalog: c), try range(289, 289))
        // Spec example: 1.5 faces from 285 ends at the ayah ending on line 8 of 286.
        XCTAssertEqual(try QuranPortionEngine.portion(from: 2057, unit: .page, amount: 1, multiplier: 1.5, catalog: c).last, 2073)
        // From line 6 of page 285, half a page targets line 12.5: ends 12/13 tie.
        XCTAssertEqual(try QuranPortionEngine.portion(from: 2061, unit: .half, amount: 1, catalog: c).last, 2064)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 1, unit: .ayah, amount: 1, multiplier: 1.5, catalog: c).last, 2)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 6236, unit: .page, amount: 604, catalog: c).last, 6236)
        XCTAssertEqual(try QuranPortionEngine.portion(from: 149, through: 150, unit: .page, amount: 10, catalog: c).last, 150)
    }

    func testPortionsRetainTheirPageContextAndInvalidAmountsAreRejected() throws {
        let c = try QuranResourceCatalog.bundled()
        let slices = try QuranPortionEngine.pages(for: range(2059, 2069), catalog: c)
        XCTAssertEqual(slices.map(\.page), [285, 286])
        XCTAssertEqual(slices.map(\.ayahs), [try range(2059, 2067), try range(2068, 2069)])
        XCTAssertTrue(slices.allSatisfy { !$0.wholePage })
        XCTAssertTrue(try QuranPortionEngine.pages(for: range(2057, 2067), catalog: c)[0].wholePage)
        XCTAssertEqual(QuranPortionEngine.leadOnPage(from: 2059, catalog: c), 2058)
        XCTAssertNil(QuranPortionEngine.leadOnPage(from: 2057, catalog: c))
        for amount in [0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try QuranPortionEngine.portion(from: 1, unit: .page, amount: amount, catalog: c))
        }
    }
}
