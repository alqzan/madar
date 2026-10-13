import MadarCore
import MadarQuran
import XCTest

@MainActor
final class ReviewBalanceSimulationTests: XCTestCase {
    private struct SimulatedPage {
        var intervalDays = 60
        var ease = 1.0
        var lastReviewed: GregorianDay
        var reviewOrdinal = 0

        var dueDate: GregorianDay { lastReviewed.adding(days: intervalDays) }
    }

    private struct Result {
        let halfDays: Int
        let simulatedDays: Int
        let longestHalfRun: Int

        var halfPercent: Double { Double(halfDays) * 100 / Double(simulatedDays) }
    }

    func testSimulatedReviewBalanceMeetsTheApprovedTargetsAtAllCorpusSizes() throws {
        for pageCount in [100, 300, 604] {
            let mastered = try simulate(pageCount: pageCount, goodPercent: 0)
            let mixed = try simulate(pageCount: pageCount, goodPercent: 35)

            print("RQ1 simulation: pages=\(pageCount), mastered=\(mastered.halfPercent)%, 35%-good=\(mixed.halfPercent)%, longest-run=\(max(mastered.longestHalfRun, mixed.longestHalfRun))")
            XCTAssertLessThanOrEqual(mastered.halfPercent, 10)
            XCTAssertLessThanOrEqual(mixed.halfPercent, 20)
            XCTAssertLessThanOrEqual(mastered.longestHalfRun, 3)
            XCTAssertLessThanOrEqual(mixed.longestHalfRun, 3)
        }
    }

    private func simulate(pageCount: Int, goodPercent: Int) throws -> Result {
        let firstDay = try GregorianDay("2026-01-01")
        var pages = (1...pageCount).map { page in
            SimulatedPage(lastReviewed: firstDay.adding(days: -((page - 1) % 60)))
        }
        var halfDays = 0
        var currentRun = 0
        var longestRun = 0

        for offset in 1...365 {
            let today = firstDay.adding(days: offset)
            let dueIndexes = pages.indices.filter { pages[$0].dueDate <= today }
            let need = QuranReviewEngine.need(
                recentCount: 5,
                memorizedIntervals: pages.map(\.intervalDays),
                dueCount: dueIndexes.count,
                recoveryShare: 0
            )
            let half = QuranReviewEngine.shouldHalfWird(
                need: need,
                balanceDecides: true,
                forcedFullWird: false,
                savedHifzToday: false,
                consolidationRequired: false
            )
            if half {
                halfDays += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }

            // Every due page is served. Quality is deterministic so each page
            // receives the selected percentage over every 100 reviews.
            for index in dueIndexes {
                let rating: QuranReviewRating = pages[index].reviewOrdinal % 100 < goodPercent ? .good : .mastered
                let cursor = QuranMemoryCursor(
                    intervalDays: pages[index].intervalDays,
                    ease: pages[index].ease,
                    lastReviewed: pages[index].lastReviewed
                )
                let update = QuranReviewEngine.apply(rating, to: cursor, on: today)
                pages[index].intervalDays = update.intervalDays
                pages[index].ease = update.ease
                pages[index].lastReviewed = today
                pages[index].reviewOrdinal += 1
            }
        }

        return Result(halfDays: halfDays, simulatedDays: 365, longestHalfRun: longestRun)
    }
}
