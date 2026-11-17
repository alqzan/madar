import Foundation
import Testing
@testable import MadarCore

/// Owner, 17 Nov 2026 (idea 2). Worked by hand: today is 17 Oct 2026, so the seven closed days are 10–16 Oct.
struct HabitInsightsTests {
    let days = MadarCalendarDays(zone: ActivePlace.riyadh.timeZone)
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    func summary(done: [String], from start: String = "2026-10-01", pauses: [HabitBreak] = []) throws -> HabitSummary {
        let rule = HabitRule(effectiveFrom: day(start))
        return try HabitEngine.evaluate(rules: [rule], facts: done.map { .init(id: UUID(), day: day($0), periodKey: $0, delta: 1) }, pauses: pauses, today: day("2026-10-17"), days: days)
    }
    @Test func twoOfSevenIsStrugglingAndThreeIsNot() throws {
        let two = try #require(HabitInsights.lastWeek(of: try summary(done: ["2026-10-11", "2026-10-14"]), today: day("2026-10-17")))
        #expect(two == .init(met: 2, total: 7) && two.struggling)
        let three = try #require(HabitInsights.lastWeek(of: try summary(done: ["2026-10-11", "2026-10-14", "2026-10-16"]), today: day("2026-10-17")))
        #expect(three.met == 3 && !three.struggling)
        // Today is not a closed day: logging today changes nothing.
        let withToday = try #require(HabitInsights.lastWeek(of: try summary(done: ["2026-10-11", "2026-10-14", "2026-10-17"]), today: day("2026-10-17")))
        #expect(withToday == .init(met: 2, total: 7))
    }
    @Test func aNewOrMostlyPausedHabitIsLeftAlone() throws {
        // Started 14 Oct: only 14, 15 and 16 Oct are closed days, fewer than five.
        let young = try #require(HabitInsights.lastWeek(of: try summary(done: [], from: "2026-10-14"), today: day("2026-10-17")))
        #expect(young.total == 3 && !young.struggling)
        // Paused 10–14 Oct: two countable days.
        let paused = try summary(done: [], pauses: [.init(from: day("2026-10-10"), until: day("2026-10-15"))])
        let reading = try #require(HabitInsights.lastWeek(of: paused, today: day("2026-10-17")))
        #expect(reading.total == 2 && !reading.struggling)
    }
}
