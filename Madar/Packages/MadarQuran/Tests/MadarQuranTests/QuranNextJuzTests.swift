import Foundation
import MadarQuran
import XCTest

/// Expected values are Mushaf facts (Madani 604-page print), not engine output:
/// juz 1 = ayahs 1…148 on pages 1…21; juz 2 = 2:142…2:252 (ayahs 149…259) on pages 22…41; page 22 = ayahs 149…152.
@MainActor final class QuranNextJuzTests: XCTestCase {
    private func coverage(_ first: Int, _ last: Int, _ catalog: QuranResourceCatalog) throws -> QuranCoverage {
        try QuranCoverageEngine.summarize(sessions: [QuranCoverageSession(id: "a", kind: .hifz, ayahs: try QuranAyahRange(first: first, last: last), endedAt: Date(timeIntervalSince1970: 1))], catalog: catalog)
    }
    private func pages(_ catalog: QuranResourceCatalog) throws -> [QuranCoveragePage] {
        try XCTUnwrap(catalog.layout).pages.map { try QuranCoveragePage(number: $0.page, ayahIDs: Set($0.lines.flatMap(\.words).map(\.ayahID))) }
    }

    func testAfterTheFirstJuzTheNextIsJuzTwoWithTwentyPages() throws {
        let catalog = try QuranResourceCatalog.bundled(), value = try coverage(1, 148, catalog)
        let next = QuranProgressEngine.nextJuz(frontierAyah: try value.frontier(from: 1), coverage: value, pages: try pages(catalog), juzSegments: try catalog.juzCycleSegments())
        XCTAssertEqual(next, QuranNextJuz(juz: 2, remainingPages: 20))
    }

    func testACompletedPageInsideTheJuzIsNoLongerRemaining() throws {
        let catalog = try QuranResourceCatalog.bundled(), value = try coverage(1, 152, catalog)
        let next = QuranProgressEngine.nextJuz(frontierAyah: try value.frontier(from: 1), coverage: value, pages: try pages(catalog), juzSegments: try catalog.juzCycleSegments())
        XCTAssertEqual(next, QuranNextJuz(juz: 2, remainingPages: 19))
    }

    func testNothingLeftFromThePlanStartGivesNoJuz() throws {
        let catalog = try QuranResourceCatalog.bundled(), value = try coverage(5673, 6236, catalog)
        XCTAssertNil(QuranProgressEngine.nextJuz(frontierAyah: try value.frontier(from: 5673), coverage: value, pages: try pages(catalog), juzSegments: try catalog.juzCycleSegments()))
    }
}
