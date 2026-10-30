import Foundation
import MadarCore
import MadarQuran
import XCTest

@MainActor
final class ReviewSchedulingTests: XCTestCase {
    private func day(_ value: String) throws -> GregorianDay { try GregorianDay(value) }
    private func pages(_ first: Int, _ last: Int) throws -> QuranPageRange {
        try QuranPageRange(first: first, last: last)
    }

    func testIntervalLadderAndIntensityPresetsFollowTheApprovedValues() {
        let balanced = QuranReviewPreset.balanced
        XCTAssertEqual(QuranReviewIntensity.light.preset.ladder, [10, 21, 45, 90])
        XCTAssertEqual(QuranReviewIntensity.light.preset.goodDays, 5)
        XCTAssertEqual(QuranReviewIntensity.light.preset.needsDays, 2)
        XCTAssertEqual(balanced.ladder, [7, 14, 30, 60])
        XCTAssertEqual(balanced.goodDays, 3)
        XCTAssertEqual(balanced.needsDays, 1)
        XCTAssertEqual(QuranReviewIntensity.intense.preset.ladder, [5, 10, 21, 45])

        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 0, rating: .needsMastery), 1)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 0, rating: .good), 3)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 0, rating: .mastered), 3)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 3, rating: .mastered), 7)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 7, rating: .mastered), 14)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 14, rating: .mastered), 30)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 30, rating: .mastered), 60)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 60, rating: .mastered), 60)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 60, rating: .needsMastery), 1)
    }

    /// Owner, 30 Oct: «جيد» on time stretches the gap ×1.3 up to the first rung (7 days, balanced); expected values worked by hand.
    func testRepeatedGoodSpacesOutUpToTheFirstRung() {
        func good(_ previous: Int, elapsed: Int) -> Int { QuranReviewEngine.nextInterval(previousDays: previous, rating: .good, elapsedDays: elapsed) }
        XCTAssertEqual(good(3, elapsed: 3), 4)    // 3 × 1.3 = 3.9
        XCTAssertEqual(good(4, elapsed: 4), 5)    // 5.2
        XCTAssertEqual(good(5, elapsed: 5), 7)    // 6.5, up to the 7-day rung
        XCTAssertEqual(good(6, elapsed: 6), 7)    // 7.8, capped at 7
        XCTAssertEqual(good(7, elapsed: 7), 7)    // already at the rung
        // On time means at least 80٪ of the last gap: 4 of 5 days counts, 3 of 5 does not.
        XCTAssertEqual(good(5, elapsed: 4), 7)
        XCTAssertEqual(good(5, elapsed: 3), 3)
        // Beyond the rung only «متقن» climbs; «جيد» keeps the plain gap. A first «جيد» is unchanged.
        XCTAssertEqual(good(14, elapsed: 14), 3)
        XCTAssertEqual(good(0, elapsed: 0), 3)
    }

    func testEaseAndLateMasteryUseTheApprovedBoundsAndRounding() {
        XCTAssertEqual(QuranReviewEngine.nextEase(1, rating: .needsMastery), 0.82, accuracy: 0.0001)
        XCTAssertEqual(QuranReviewEngine.nextEase(1, rating: .good), 0.95, accuracy: 0.0001)
        XCTAssertEqual(QuranReviewEngine.nextEase(1, rating: .mastered), 1.06, accuracy: 0.0001)
        XCTAssertEqual(QuranReviewEngine.normalizedEase(.infinity), 1)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 0, rating: .good, ease: 0.6), 2)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 16, rating: .mastered, ease: 1.12), 34)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 7, rating: .mastered, elapsedDays: 20), 20)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 7, rating: .mastered, elapsedDays: 40), 28)
        XCTAssertEqual(QuranReviewEngine.nextInterval(previousDays: 60, rating: .mastered, ease: 1.4, elapsedDays: 400), 84)
    }

    func testEarlyMasteryKeepsTheCurrentIntervalAndEaseButEarlyNeedsCounts() throws {
        let cursor = QuranMemoryCursor(intervalDays: 7, ease: 1.12, lastReviewed: try day("2026-01-01"))
        let early = QuranReviewEngine.apply(.mastered, to: cursor, on: try day("2026-01-06"))
        XCTAssertTrue(early.wasEarlyMastery)
        XCTAssertEqual(early.intervalDays, 7)
        XCTAssertEqual(early.ease, 1.12, accuracy: 0.0001)

        let lapse = QuranReviewEngine.apply(.needsMastery, to: cursor, on: try day("2026-01-02"))
        XCTAssertFalse(lapse.wasEarlyMastery)
        XCTAssertEqual(lapse.intervalDays, 1)
        XCTAssertEqual(lapse.ease, 0.92, accuracy: 0.0001)
    }

    func testLatestSameDayRatingWinsAndFirstReviewIsDue() throws {
        let singlePage = try pages(1, 1)
        let jan1 = try day("2026-01-01")
        let jan8 = try day("2026-01-08")
        let jan9 = try day("2026-01-09")
        let events = [
            QuranReviewEvent(pages: singlePage, day: jan1, rating: .mastered),
            QuranReviewEvent(pages: singlePage, day: jan8, rating: .mastered, occurredAt: 100, inputOrder: 1),
            QuranReviewEvent(pages: singlePage, day: jan8, rating: .needsMastery, occurredAt: 200, inputOrder: 2),
        ]
        let schedule = QuranReviewEngine.schedules(pages: singlePage, events: events, today: jan9)[0]
        XCTAssertEqual(schedule.intervalDays, 1)
        XCTAssertEqual(schedule.lapses, 1)
        XCTAssertEqual(schedule.lastReviewed, jan8)
        XCTAssertEqual(schedule.dueDate, jan9)
        XCTAssertTrue(schedule.isDue)

        let unreviewed = QuranReviewEngine.schedules(pages: singlePage, events: [], today: jan9)[0]
        XCTAssertEqual(unreviewed.intervalDays, 0)
        XCTAssertNil(unreviewed.dueDate)
        XCTAssertTrue(unreviewed.isDue)
        XCTAssertEqual(unreviewed.risk, 2.5, accuracy: 0.0001)
    }

    func testDueDateUsesTheFullFirstIntervalAndRiskUsesRelativeOverdueTime() throws {
        let singlePage = try pages(1, 1)
        let jan1 = try day("2026-01-01")
        let event = QuranReviewEvent(pages: singlePage, day: jan1, rating: .mastered)
        let beforeDue = QuranReviewEngine.schedules(pages: singlePage, events: [event], today: try day("2026-01-03"))[0]
        let onDue = QuranReviewEngine.schedules(pages: singlePage, events: [event], today: try day("2026-01-04"))[0]
        let late = QuranReviewEngine.schedules(pages: singlePage, events: [event], today: try day("2026-01-10"))[0]
        XCTAssertEqual(beforeDue.dueDate, try day("2026-01-04"))
        XCTAssertFalse(beforeDue.isDue)
        XCTAssertTrue(onDue.isDue)
        XCTAssertEqual(late.overdueDays, 6)
        XCTAssertEqual(QuranReviewEngine.pageRisk(intervalDays: 7, overdueDays: 3, lapses: 0, openMistakes: 0, lastReviewed: jan1), 0.86, accuracy: 0.0001)
        XCTAssertEqual(QuranReviewEngine.pageRisk(intervalDays: 60, overdueDays: 3, lapses: 0, openMistakes: 0, lastReviewed: jan1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(QuranReviewEngine.pageRisk(intervalDays: 0, overdueDays: 0, lapses: 0, openMistakes: 2, lastReviewed: nil), 3.5, accuracy: 0.0001)
    }

    func testDuePagesSortByRiskThenOverdueThenPageAndHonorRecentExclusion() throws {
        let range = try pages(1, 3)
        let jan1 = try day("2026-01-01")
        let events = [
            QuranReviewEvent(pages: try pages(1, 1), day: jan1, rating: .good),
            QuranReviewEvent(pages: try pages(2, 2), day: jan1, rating: .needsMastery),
        ]
        let schedule = QuranReviewEngine.schedules(
            pages: range,
            events: events,
            openMistakesByPage: [3: 1],
            today: try day("2026-01-05")
        )
        XCTAssertEqual(QuranReviewEngine.duePages(schedule).map(\.page), [2, 3, 1])
        XCTAssertEqual(QuranReviewEngine.duePages(schedule, excluding: [2]).map(\.page), [3, 1])
    }

    func testConsistencyUsesUniqueActivityDaysWithinTheLastFourteenDays() throws {
        let today = try day("2026-01-14")
        let activity = try (1...14).map { try day(String(format: "2026-01-%02d", $0)) }
        let todayOnly = try day("2026-01-14")
        let repeated = Array(repeating: todayOnly, count: 5)
        XCTAssertEqual(
            QuranReviewEngine.reviewConsistency(hifzActivityDays: repeated, reviewActivityDays: repeated, through: today),
            1.0 / 14.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(QuranReviewEngine.reviewConsistency(hifzActivityDays: activity, reviewActivityDays: [], through: today), 1)
        XCTAssertEqual(QuranReviewEngine.reviewConsistency(hifzActivityDays: [try day("2025-12-31")], reviewActivityDays: [], through: today), 0)
        XCTAssertEqual(QuranReviewEngine.adaptiveReviewCap(dailyReviewPages: 7, hifzActivityDays: [], reviewActivityDays: [], through: today), 5)
        XCTAssertEqual(QuranReviewEngine.adaptiveReviewCap(dailyReviewPages: 7, hifzActivityDays: activity, reviewActivityDays: [], through: today), 11)
        XCTAssertEqual(QuranReviewEngine.adaptiveReviewCap(dailyReviewPages: 1, hifzActivityDays: [], reviewActivityDays: [], through: today), 2)
    }

    func testDueQueueReportsTheUncappedTotalAndHonorsExplicitLimits() throws {
        let range = try pages(1, 8)
        let today = try day("2026-01-14")
        let schedule = QuranReviewEngine.schedules(pages: range, events: [], today: today)
        let adaptive = QuranReviewEngine.dueQueue(
            schedule,
            dailyReviewPages: 7,
            hifzActivityDays: [],
            reviewActivityDays: [],
            through: today
        )
        XCTAssertEqual(adaptive.pages.map(\.page), [1, 2, 3, 4, 5])
        XCTAssertEqual(adaptive.total, 8)
        XCTAssertEqual(adaptive.hidden, 3)
        XCTAssertEqual(adaptive.cap, 5)

        let limited = QuranReviewEngine.dueQueue(
            schedule,
            dailyReviewPages: 7,
            hifzActivityDays: [],
            reviewActivityDays: [],
            through: today,
            explicitLimit: 3
        )
        XCTAssertEqual(limited.pages.map(\.page), [1, 2, 3])
        XCTAssertEqual(limited.total, 8)
        XCTAssertEqual(limited.hidden, 5)
        XCTAssertEqual(limited.cap, 3)
    }

    func testComputedNeedUsesAllDuePagesAndTheBalanceGuards() {
        let need = QuranReviewEngine.need(
            recentCount: 5,
            memorizedIntervals: [0, 2, 4],
            dueCount: 3,
            recoveryShare: 0.5
        )
        XCTAssertEqual(need.steadyNeed, 5.75, accuracy: 0.0001)
        XCTAssertEqual(need.todayNeed, 8.5, accuracy: 0.0001)

        let overloaded = QuranReviewNeed(steadyNeed: 5, todayNeed: 10.01)
        XCTAssertTrue(QuranReviewEngine.shouldHalfWird(
            need: overloaded,
            balanceDecides: true,
            forcedFullWird: false,
            savedHifzToday: false,
            consolidationRequired: false
        ))
        let exactBoundary = QuranReviewNeed(steadyNeed: 5, todayNeed: 10)
        XCTAssertFalse(QuranReviewEngine.shouldHalfWird(
            need: exactBoundary,
            balanceDecides: true,
            forcedFullWird: false,
            savedHifzToday: false,
            consolidationRequired: false
        ))
        XCTAssertFalse(QuranReviewEngine.shouldHalfWird(
            need: overloaded,
            balanceDecides: true,
            forcedFullWird: false,
            savedHifzToday: true,
            consolidationRequired: false
        ))
        XCTAssertFalse(QuranReviewEngine.shouldHalfWird(
            need: overloaded,
            balanceDecides: true,
            forcedFullWird: false,
            savedHifzToday: false,
            consolidationRequired: true
        ))
        XCTAssertFalse(QuranReviewEngine.shouldHalfWird(
            need: overloaded,
            balanceDecides: false,
            forcedFullWird: false,
            savedHifzToday: false,
            consolidationRequired: false
        ))
        XCTAssertFalse(QuranReviewEngine.shouldHalfWird(
            need: overloaded,
            balanceDecides: true,
            forcedFullWird: true,
            savedHifzToday: false,
            consolidationRequired: false
        ))
    }
}
