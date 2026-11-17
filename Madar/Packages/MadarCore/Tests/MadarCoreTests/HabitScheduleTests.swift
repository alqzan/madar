import Foundation
import Testing
@testable import MadarCore

/// Owner, 17 Nov 2026 (ideas 8 and 16). Expected values come from the rule and from the Hijri calendar itself.
struct HabitScheduleTests {
    let days = MadarCalendarDays(zone: ActivePlace.riyadh.timeZone, source: .ummAlQura)
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    func pages(_ from: String, target: Int = 5) -> HabitRule { var r = HabitRule(effectiveFrom: day(from)); r.measure = .count; r.unit = "pages"; r.target = target; return r }

    @Test func aGrowingGoalStepsUpEveryNDaysAndStopsAtTheCap() throws {
        // 5 pages, +1 every 7 days, cap 7: 6 from 8 Oct, 7 from 15 Oct, nothing after.
        let plan = HabitSchedule.plan(base: pages("2026-10-01"), ramp: .init(step: 1, everyDays: 7, cap: 7), ramadan: nil, today: day("2026-10-01"), days: days)
        #expect(plan.rule.target == 5)
        #expect(plan.steps.map(\.effectiveFrom) == [day("2026-10-08"), day("2026-10-15")] && plan.steps.map(\.target) == [6, 7])
        let result = try HabitEngine.evaluate(rules: [plan.rule] + plan.steps, facts: [], today: day("2026-10-16"), days: days)
        #expect(result.periods.map(\.target) == Array(repeating: 5, count: 7) + Array(repeating: 6, count: 7) + [7, 7])
        // A step that would pass the cap lands on it: 5, +2 every 3 days, cap 8 → 7 then 8.
        let capped = HabitSchedule.plan(base: pages("2026-10-01"), ramp: .init(step: 2, everyDays: 3, cap: 8), ramadan: nil, today: day("2026-10-01"), days: days)
        #expect(capped.steps.map(\.target) == [7, 8])
        // No ramp, no Ramadan: nothing to add.
        #expect(HabitSchedule.plan(base: pages("2026-10-01"), ramp: nil, ramadan: nil, today: day("2026-10-01"), days: days).steps.isEmpty)
    }
    @Test func aPastStartGrowsFromTodayAndNeverRewritesClosedDays() throws {
        let plan = HabitSchedule.plan(base: pages("2026-09-20"), ramp: .init(step: 1, everyDays: 7, cap: 6), ramadan: nil, today: day("2026-10-01"), days: days)
        #expect(plan.steps.map(\.effectiveFrom) == [day("2026-10-08")] && plan.rule.target == 5 && plan.rule.effectiveFrom == day("2026-09-20"))
    }
    func spans() -> [(start: GregorianDay, end: GregorianDay)] { HabitSchedule.ramadanSpans(from: day("2026-01-15"), days: days) }
    @Test func ramadanSpansAreTheHijriMonthNine() {
        let found = spans()
        #expect(found.count == 2)
        for span in found {
            #expect(days.hijri(span.start).month == 9 && days.hijri(span.start).day == 1 && days.hijri(span.start.adding(days: -1)).month == 8)
            #expect(days.hijri(span.end).month == 10 && days.hijri(span.end).day == 1 && days.hijri(span.end.adding(days: -1)).month == 9)
        }
        #expect(found[1].start > found[0].end)
    }
    @Test func theWindowIsRamadansDuringRamadanAndTheNormalOneReturnsAtShawwal() throws {
        var base = HabitRule(effectiveFrom: day("2026-01-15")); base.windowAnchor = .fajr; base.windowStart = 0; base.windowEnd = 90
        let ramadan = HabitRamadanWindow(anchor: .isha, start: 90, end: 360)
        let plan = HabitSchedule.plan(base: base, ramp: nil, ramadan: ramadan, today: day("2026-01-15"), days: days)
        let first = spans()[0]
        #expect(plan.rule.windowAnchor == .fajr && plan.steps.count == 4)
        #expect(plan.steps[0].effectiveFrom == first.start && plan.steps[0].windowAnchor == .isha && plan.steps[0].windowStart == 90 && plan.steps[0].windowEnd == 360)
        #expect(plan.steps[1].effectiveFrom == first.end && plan.steps[1].windowAnchor == .fajr && plan.steps[1].windowEnd == 90)
        for step in plan.steps { try step.validate() }
        func rule(on d: GregorianDay) throws -> HabitRule {
            let result = try HabitEngine.evaluate(rules: [plan.rule] + plan.steps, facts: [], today: d, days: days)
            return try #require(result.current).rule
        }
        #expect(try rule(on: first.start.adding(days: 3)).windowAnchor == .isha)
        #expect(try rule(on: first.end).windowAnchor == .fajr && rule(on: first.end.adding(days: 5)).windowStart == 0)
        // Closed periods keep the rule in force on their own day.
        let after = try HabitEngine.evaluate(rules: [plan.rule] + plan.steps, facts: [], today: first.end.adding(days: 2), days: days)
        let before = try #require(after.periods.first { $0.start == first.start.adding(days: -1) }), inside = try #require(after.periods.first { $0.start == first.start })
        #expect(before.rule.windowAnchor == .fajr && inside.rule.windowAnchor == .isha)
        // The Ramadan window really is the one the engine resolves: Isha + 90 minutes on a Ramadan day.
        let ramadanDay = first.start.adding(days: 2)
        let prayer = try #require(PrayerTimesEngine.calculate(day: ramadanDay, place: .riyadh))
        let window = try #require(HabitEngine.window(rule: try rule(on: ramadanDay), civilDay: ramadanDay, place: .riyadh, prayer: prayer))
        #expect(window.start == prayer.isha.addingTimeInterval(90 * 60))
    }
    @Test func startingInsideRamadanShiftsTheWindowToday() throws {
        var base = HabitRule(effectiveFrom: day("2026-03-01")); base.windowAnchor = .fajr; base.windowStart = 0; base.windowEnd = 90
        #expect(days.hijri(day("2026-03-01")).month == 9)
        let plan = HabitSchedule.plan(base: base, ramp: nil, ramadan: .init(anchor: .isha, start: 90, end: 360), today: day("2026-03-01"), days: days)
        #expect(plan.rule.windowAnchor == .isha && plan.rule.effectiveFrom == day("2026-03-01"))
        #expect(plan.steps.first?.windowAnchor == .fajr && days.hijri(plan.steps[0].effectiveFrom).month == 10)
        // An edit of an older habit dated today: its older version stays as it was, a step dated today carries Ramadan.
        var older = base; older.effectiveFrom = day("2026-02-01")
        let edited = HabitSchedule.plan(base: older, ramp: nil, ramadan: .init(anchor: .isha, start: 90, end: 360), today: day("2026-03-01"), days: days)
        #expect(edited.rule.windowAnchor == .fajr && edited.steps.first?.effectiveFrom == day("2026-03-01") && edited.steps.first?.windowAnchor == .isha)
    }
}
