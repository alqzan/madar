import XCTest
import MadarCore
@testable import Madar

final class HabitRhythmTests: XCTestCase {
    func testDailyBandKeepsPartialCountBelowACompleteDayEvenAtMinimum() throws {
        let today = try GregorianDay("2026-10-15"), yesterday = today.adding(days: -1)
        var rule = HabitRule(effectiveFrom: yesterday)
        rule.measure = .count; rule.target = 8; rule.minimum = 1; rule.unit = "كوب"
        let summary = try HabitEngine.evaluate(rules: [rule], facts: [
            .init(id: UUID(), day: yesterday, periodKey: yesterday.description, delta: 1, unit: "كوب"),
            .init(id: UUID(), day: today, periodKey: today.description, delta: 8, unit: "كوب")
        ], today: today, days: .init(zone: .gmt))
        let steps = HabitRhythmBand.dailySteps(summaries: [summary], today: today)
        XCTAssertEqual(steps[5].share, 0.125, accuracy: 0.0001)
        XCTAssertEqual(steps[6].share, 1)
        XCTAssertEqual(steps.filter { $0.share >= 1 }.count, 1)
    }

    func testDailyBandUsesHistoricalEligibilityInsteadOfTodaysFreezeOrNewHabit() throws {
        let today = try GregorianDay("2026-10-15"), yesterday = today.adding(days: -1)
        var old = HabitRule(effectiveFrom: today.adding(days: -6)); old.restWeekdays = [3] // Tuesday
        let summary = try HabitEngine.evaluate(rules: [old], facts: [
            .init(id: UUID(), day: yesterday, periodKey: yesterday.description, delta: 1)
        ], pauses: [.init(from: today)], today: today, days: .init(zone: .gmt))
        let new = try HabitEngine.evaluate(rules: [.init(effectiveFrom: today)], facts: [], today: today, days: .init(zone: .gmt))
        let steps = HabitRhythmBand.dailySteps(summaries: [summary, new], today: today)
        XCTAssertEqual(steps[5].share, 1, "A habit created today cannot make yesterday incomplete; today's freeze cannot erase it")
        XCTAssertEqual(steps[4].share, 0, "A rest day is not a completed day")
        XCTAssertEqual(steps[6].share, 0)
    }
}
