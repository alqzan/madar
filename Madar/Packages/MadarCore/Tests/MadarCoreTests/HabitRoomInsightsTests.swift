import Foundation
import Testing
@testable import MadarCore

/// Expected values come from the rules written in each test, never from the engine's own output.
struct HabitRoomInsightsTests {
    let days = MadarCalendarDays(zone: ActivePlace.riyadh.timeZone)
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    /// A daily habit from `start`, kept on every day for which `keep` is true. 2026-11-17 is a Tuesday.
    func series(start: String = "2026-07-01", today: String = "2026-11-17", keep: (GregorianDay) -> Bool) throws -> HabitRoomSeries {
        let first = day(start), last = day(today)
        var facts: [HabitFact] = [], done: [GregorianDay] = [], cursor = first
        while cursor <= last { if keep(cursor) { facts.append(.init(id: UUID(), day: cursor, periodKey: cursor.description, delta: 1)); done.append(cursor) }; cursor = cursor.adding(days: 1) }
        let summary = try HabitEngine.evaluate(rules: [HabitRule(effectiveFrom: first)], facts: facts, today: last, days: days)
        return .init(id: UUID(), periods: summary.periods, doneDays: done, loggedAt: [])
    }

    @Test func thursdayAndFridayAreTheWeakestWhenOnlyTheyAreMissed() throws {
        // Weekday 5 = Thursday, 6 = Friday: never kept; every other day always kept.
        let s = try series { ![5, 6].contains(HabitEngine.weekday($0)) }
        let stats = HabitRoomInsights.weekdayRates([s], today: day("2026-11-17"))
        #expect(stats.first { $0.weekday == 2 }?.rate == 1 && stats.first { $0.weekday == 5 }?.rate == 0)
        #expect(Set(HabitRoomInsights.weakestWeekdays(stats) ?? []) == [5, 6])
    }
    @Test func noWeakDayWhenEveryDayIsKeptEqually() throws {
        let s = try series { _ in true }
        #expect(HabitRoomInsights.weakestWeekdays(HabitRoomInsights.weekdayRates([s], today: day("2026-11-17"))) == nil)
    }
    @Test func aNewHabitHasTooFewSamplesPerWeekday() throws {
        let s = try series(start: "2026-11-10") { _ in true }
        #expect(HabitRoomInsights.weakestWeekdays(HabitRoomInsights.weekdayRates([s], today: day("2026-11-17"))) == nil)
    }
    @Test func aLongerHabitHasADominantWeekdayOnlyWhenHalfItsLogsShareOne() {
        // Five logs on Fridays (2026-11-13 is a Friday) and two on a Monday: 5/7 on Friday.
        let fridays = ["2026-10-02", "2026-10-09", "2026-10-16", "2026-10-23", "2026-10-30"].map(day) + ["2026-10-05", "2026-10-12"].map(day)
        #expect(HabitRoomInsights.dominantWeekday(HabitRoomInsights.weekdayShares(fridays)) == 6)
        let spread = ["2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"].map(day)
        #expect(HabitRoomInsights.dominantWeekday(HabitRoomInsights.weekdayShares(spread)) == nil)
    }

    @Test func hoursFindTheBusiestStretchAndTheMorningShare() {
        // Buckets are 6…23. Ten logs: 1 at 6, 6 at 7, 3 at 8 -> the peak is 7, the half-of-peak rule takes 8 (3 >= 3) and not 6 (1 < 3).
        var buckets = [Int](repeating: 0, count: 18); buckets[0] = 1; buckets[1] = 6; buckets[2] = 3
        let peak = HabitRoomInsights.peak(buckets)
        #expect(peak == .init(from: 7, to: 9, share: 0.9))
        #expect(HabitRoomInsights.morningShare(buckets) == 1)
        var evening = [Int](repeating: 0, count: 18); evening[16] = 8; evening[3] = 2
        #expect(HabitRoomInsights.morningShare(evening) == 0.2)
    }
    @Test func hoursNeedEightLogsAndBucketInTheGivenZone() {
        var few = [Int](repeating: 0, count: 18); few[2] = 7
        #expect(HabitRoomInsights.peak(few) == nil && HabitRoomInsights.morningShare(few) == nil)
        // 2026-11-17 04:30 UTC is 07:30 in Riyadh (UTC+3); 02:30 UTC is 05:30 there, before the chart starts.
        let utc = { (h: Int, m: Int) in Date(timeIntervalSince1970: day("2026-11-17").date(in: .gmt).timeIntervalSince1970 + Double(h * 3600 + m * 60)) }
        let zone = ActivePlace.riyadh.timeZone
        let b = HabitRoomInsights.hourBuckets([utc(4, 30), utc(4, 40), utc(2, 30), utc(19, 5)], zone: zone)
        #expect(b[1] == 2 && b.reduce(0, +) == 3)   // 07:xx twice; 22:05 once at index 16; 05:30 is dropped
        #expect(b[16] == 1)
    }

    @Test func aRisingKeptShareIsReportedWithItsEnds() {
        let rates: [Double?] = [0.5, 0.55, 0.6, 0.7, 0.8, 0.85, 0.9, 0.9]
        #expect(HabitRoomInsights.trend(rates) == .rising(from: (0.5 + 0.55 + 0.6) / 3, to: (0.85 + 0.9 + 0.9) / 3))
        #expect(HabitRoomInsights.trend([0.9, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5, 0.4]) != nil)
        if case .falling = HabitRoomInsights.trend([0.9, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5, 0.4]) {} else { Issue.record("expected falling"); return }
        if case .steady = HabitRoomInsights.trend([0.8, 0.82, 0.8, 0.81, 0.8, 0.79, 0.8, 0.8]) {} else { Issue.record("expected steady"); return }
        #expect(HabitRoomInsights.trend([0.8, nil, nil, nil, 0.9, 0.9, nil, nil]) == nil)   // only three points
    }
    @Test func weeklyRatesCountOnlyClosedDaysAndNeedFourPerWindow() throws {
        // Kept every day: the newest window is 100%; a habit started 10 days ago leaves the older windows empty.
        let s = try series(start: "2026-11-07") { _ in true }
        let rates = HabitRoomInsights.weeklyRates([s], today: day("2026-11-17"))
        #expect(rates.count == 8 && rates.last! == 1)
        #expect(rates.dropLast(2).allSatisfy { $0 == nil })
    }
    @Test func theMoverIsTheHabitWhoseLastTwoWeeksChangedMostAgainstTheTwoBefore() throws {
        let t = day("2026-11-17")
        let improving = try series { $0 >= t.adding(days: -14) ? true : (HabitEngine.weekday($0) == 2) }   // before: Mondays only (1/7), now: all
        let steady = try series { _ in true }
        let m = HabitRoomInsights.mover([steady, improving], today: t)
        #expect(m?.id == improving.id && m?.rising == true)
        #expect(m!.now == 1 && abs(m!.before - 1.0 / 7.0) < 0.001)
        #expect(HabitRoomInsights.mover([steady], today: t) == nil)
    }

    @Test func theGregorianYearHasTwelveRealMonthsAndTheHijriYearTwelveHijriOnes() {
        let g = HabitRoomInsights.yearMonths(containing: day("2026-11-17"), calendar: .gregorian, days: days)
        #expect(g.count == 12 && g[1].length == 28 && g[10].start == day("2026-11-01") && g.reduce(0) { $0 + $1.length } == 365)
        let h = HabitRoomInsights.yearMonths(containing: day("2026-11-17"), calendar: .hijri, days: days)
        #expect(h.count == 12 && days.hijri(h[0].start).month == 1 && days.hijri(h[0].start).day == 1)
        #expect(h.allSatisfy { $0.length == 29 || $0.length == 30 })
        #expect(h[1].start == h[0].end)
    }
    @Test func monthValuesAreTheMeanOfTheirDayRatesAndBestAndWorstSkipOpenMonths() throws {
        // Kept on all days of October and half of November's first fourteen days (odd days).
        let s = try series(start: "2026-10-01") { $0.month == 10 || $0.day % 2 == 1 }
        let rates = HabitRoomInsights.dayRates([s], selected: nil, today: day("2026-11-17"))
        let months = HabitRoomInsights.yearMonths(containing: day("2026-11-17"), calendar: .gregorian, days: days)
        let values = HabitRoomInsights.monthValues(months, rates: rates)
        #expect(values[9] == 1)
        #expect(abs(values[10]! - 9.0 / 17.0) < 0.001)   // 1, 3 … 17 are the 9 odd days of 17 rated days (the 17th itself is today and counts)
        #expect(values[0] == nil && values[11] == nil)
        let complete = months.map { $0.end <= day("2026-11-17") }
        #expect(HabitRoomInsights.extremes(values, complete: complete) == .init(best: 9, worst: nil))   // only October is over
        #expect(HabitRoomInsights.extremes([nil, 0.9, 0.5, 0.7], complete: [true, true, true, true]) == .init(best: 1, worst: 2))
    }
    @Test func aLongerHabitRatesOneOnItsDoneDaysAndZeroOnTheOthers() throws {
        var r = HabitRule(effectiveFrom: day("2026-11-01")); r.frequency = .weekly
        let facts: [HabitFact] = [.init(id: UUID(), day: day("2026-11-06"), periodKey: "w", delta: 1)]
        let summary = try HabitEngine.evaluate(rules: [r], facts: facts, today: day("2026-11-17"), days: days)
        let s = HabitRoomSeries(id: UUID(), periods: summary.periods, doneDays: [day("2026-11-06")], loggedAt: [])
        let rates = HabitRoomInsights.dayRates([s], selected: s.id, today: day("2026-11-17"))
        #expect(rates[day("2026-11-06")] == 1 && rates[day("2026-11-07")] == 0)
        #expect(rates[day("2026-11-18")] == nil)
        #expect(HabitRoomInsights.monthValues(HabitRoomInsights.yearMonths(containing: day("2026-11-17"), calendar: .gregorian, days: days), rates: rates, counting: true)[10] == 1)
    }

    @Test func theLongestStreakIsTheLongestRunOfKeptPeriodsAndNeverBrokenByToday() throws {
        // Kept 1–5 Nov, missed 6 Nov, kept 7–9 Nov, missed 10–16 Nov (the habit began 2026-11-01); today (17th) is still open.
        let kept: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]
        let s = try series(start: "2026-11-01") { $0.month == 11 && kept.contains($0.day) }
        let longest = HabitRoomInsights.longestStreak(s.periods, today: day("2026-11-17"))
        // One missed day does not end a streak (two in a row do), so the run is 5 + 3 kept days around the single miss.
        #expect(longest?.length == 8 && longest?.end == day("2026-11-09"))
        // Strict reading (one miss ends it): the first run of five is the longest.
        let strict = HabitRoomInsights.longestStreak(s.periods, today: day("2026-11-17"), breakAfter: 1)
        #expect(strict?.length == 5 && strict?.end == day("2026-11-05"))
        // A habit kept every day since the 1st and open today: the open period (kept) counts, the run is 17.
        let all = try series(start: "2026-11-01") { _ in true }
        #expect(HabitRoomInsights.longestStreak(all.periods, today: day("2026-11-17"))?.length == 17)
        // Nothing kept: no longest run.
        let none = try series(start: "2026-11-01") { _ in false }
        #expect(HabitRoomInsights.longestStreak(none.periods, today: day("2026-11-17")) == nil)
        #expect(HabitRoomInsights.keptPeriods(s.periods).kept == 8)
    }
}
