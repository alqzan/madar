import Foundation
import Testing
@testable import MadarCore

/// Expected values come from §7.1 «السنة وما يهمّك», B03 and B04 and from RL10 (Saturday weeks), never from the engine.
@Suite struct MadarYearTests {
    let riyadh = MadarCalendarDays(zone: TimeZone(identifier: "Asia/Riyadh")!)
    func day(_ text: String) -> GregorianDay { try! GregorianDay(text) }

    @Test func crescentFollowsTheHijriDayFormula() {
        // B04: ١ من ٣٠ ← ٠٫٣٪ متزايد؛ ٨ من ٣٠ ← ٥٠٪؛ ١٥ من ٣٠ ← ٩٩٫٧٪؛ ٢٩ من ٢٩ ← ٠٫٣٪ متناقص.
        let first = MadarYear.crescent(day: 1, length: 30), eighth = MadarYear.crescent(day: 8, length: 30)
        let fifteenth = MadarYear.crescent(day: 15, length: 30), last = MadarYear.crescent(day: 29, length: 29)
        #expect((first.lit * 1000).rounded() / 10 == 0.3 && first.waxing)
        #expect(abs(eighth.lit - 0.5) < 0.0005)
        #expect((fifteenth.lit * 1000).rounded() / 10 == 99.7)
        #expect((last.lit * 1000).rounded() / 10 == 0.3 && !last.waxing)
    }

    @Test func yearMonthAndWeekCountWholeDaysBeforeToday() throws {
        #expect(MadarYear.gregorianYear(day("2026-01-01")) == .init(start: day("2026-01-01"), length: 365, elapsed: 0))
        #expect(MadarYear.gregorianYear(day("2028-12-31")).length == 366)
        #expect(MadarYear.gregorianYear(day("2028-12-31")).remaining == 1)
        // RL10: core.weekStart defaults to Saturday. Thursday 15 Oct 2026 → Saturday to Wednesday have passed.
        #expect(MadarYear.week(day("2026-10-15"), start: .saturday) == .init(start: day("2026-10-10"), length: 7, elapsed: 5))
        #expect(MadarYear.week(day("2026-10-15"), start: .sunday).elapsed == 4)
        #expect(MadarYear.week(day("2026-10-10"), start: .saturday).elapsed == 0)
        // §7.1: Ramadan 1448 has 29 days by Umm al-Qura and 29 Ramadan is 8 March 2027.
        let month = MadarYear.hijriMonth(day("2027-03-08"), riyadh)
        #expect(month.length == 29 && month.remaining == 1 && month.start == (day("2027-02-08")))
        let year = MadarYear.hijriYear(day("2027-03-08"), riyadh)
        #expect([354, 355].contains(year.length) && riyadh.hijri(year.start) == HijriDate(year: 1448, month: 1, day: 1))
    }

    @Test func landmarksAndRamadanCountdown() throws {
        // 1 Ramadan 1448 is 8 February 2027 (29 Ramadan = 8 March); Eid al-Fitr follows the 29-day month.
        let today = day("2026-10-15")
        #expect(MadarYear.ramadanIn(today, riyadh) == 116)
        let marks = MadarYear.landmarks(today, riyadh)
        #expect(marks.count == 5)
        #expect(marks.first?.name == .gregorianYearEnd && marks.first?.daysLeft == 77)
        #expect(marks.first(where: { $0.name == .eidAlFitr })?.day == (day("2027-03-09")))
        #expect(marks.map(\.daysLeft) == marks.map(\.daysLeft).sorted())
        #expect(MadarYear.ramadanIn(day("2027-02-20"), riyadh) == nil)
    }

    @Test func upcomingRulesFallBackToTheMonthsLastDay() throws {
        // B03 acceptance: «٣٠ رمضان» yearly Hijri falls on 29 Ramadan 1448 (8 March 2027) and on 30 Ramadan in a 30-day year.
        let ramadan30 = MadarUpcomingRule(calendar: .hijri, month: 9, day: 30, repeats: .yearly)
        #expect(ramadan30.next(onOrAfter: day("2026-10-15"), riyadh) == (day("2027-03-08")))
        let thirty = try #require(ramadan30.next(onOrAfter: day("2029-06-01"), riyadh))
        #expect(riyadh.hijri(thirty) == HijriDate(year: 1451, month: 9, day: 30))
        // A 29 February birthday falls on 28 February 2027 and 29 February 2028.
        let leap = MadarUpcomingRule(calendar: .gregorian, month: 2, day: 29, repeats: .yearly)
        #expect(leap.next(onOrAfter: day("2026-10-15"), riyadh) == (day("2027-02-28")))
        #expect(leap.next(onOrAfter: day("2027-03-01"), riyadh) == (day("2028-02-29")))
        // Monthly on the 31st → the last day of a shorter month.
        #expect(MadarUpcomingRule(calendar: .gregorian, month: 1, day: 31, repeats: .monthly).next(onOrAfter: day("2026-11-02"), riyadh) == (day("2026-11-30")))
        // A one-time day that has passed has no next occurrence.
        #expect(MadarUpcomingRule(calendar: .gregorian, year: 2026, month: 1, day: 5, repeats: .none).next(onOrAfter: day("2026-10-15"), riyadh) == nil)
    }

    @Test func hijriCorrectionMovesTheOccurrenceNotTheRule() throws {
        // B03: a +1 day correction moves the next Hijri occurrence by one day; the rule itself is unchanged.
        let rule = MadarUpcomingRule(calendar: .hijri, month: 9, day: 1, repeats: .yearly)
        let zone = TimeZone(identifier: "Asia/Riyadh")!, today = day("2026-10-15")
        let plain = try #require(rule.next(onOrAfter: today, MadarCalendarDays(zone: zone, source: .sighting, offset: 0)))
        let corrected = try #require(rule.next(onOrAfter: today, MadarCalendarDays(zone: zone, source: .sighting, offset: 1)))
        #expect(abs(MadarCalendarDays.distance(from: plain, to: corrected)) == 1)
        #expect(rule == MadarUpcomingRule(calendar: .hijri, month: 9, day: 1, repeats: .yearly))
    }

    @Test func farFutureOneTimeDatesUseTheirStoredYear() throws {
        // B03 places no 800-day horizon on a one-off. The Gregorian target is
        // literal; the Ramadan 1448 clamp comes from the handoff's 8 March row.
        let future = MadarUpcomingRule(calendar: .gregorian, year: 2035, month: 11, day: 19, repeats: .none)
        #expect(future.next(onOrAfter: day("2026-10-25"), riyadh) == day("2035-11-19"))
        #expect(future.next(onOrAfter: day("2035-11-19"), riyadh) == day("2035-11-19"))
        #expect(future.next(onOrAfter: day("2035-11-20"), riyadh) == nil)
        let short = MadarUpcomingRule(calendar: .gregorian, year: 2031, month: 2, day: 29, repeats: .none)
        #expect(short.next(onOrAfter: day("2026-10-25"), riyadh) == day("2031-02-28"))
        let ramadan = MadarUpcomingRule(calendar: .hijri, year: 1448, month: 9, day: 30, repeats: .none)
        #expect(ramadan.next(onOrAfter: day("2020-10-25"), riyadh) == day("2027-03-08"))
        let corrected = MadarCalendarDays(zone: riyadh.zone, source: .sighting, offset: 1)
        #expect(ramadan.next(onOrAfter: day("2020-10-25"), corrected) == day("2027-03-07"))
    }
    @Test func oneTimeCountUpStartsOnlyAfterTheNamedDayAndDefaultsOff() throws {
        // Owner-approved 25 October behavior: 24th -> one day left, 25th -> today,
        // 26th -> one day elapsed, 30th -> five days elapsed. No wall-clock duration.
        let rule = MadarUpcomingRule(calendar: .gregorian, year: 2026, month: 10, day: 25, repeats: .none,
                                     countFrom: day("2026-10-22"), countUpAfter: true)
        let before = try #require(rule.counter(today: day("2026-10-24"), riyadh))
        #expect(before.occurrence == day("2026-10-25") && before.daysLeft == 1 && before.elapsedDays == nil)
        #expect(abs(before.closed - 2.0 / 3.0) < 0.0001)
        let today = try #require(rule.counter(today: day("2026-10-25"), riyadh))
        #expect(today.daysLeft == 0 && today.elapsedDays == nil && today.closed == 1)
        #expect(rule.counter(today: day("2026-10-26"), riyadh)?.elapsedDays == 1)
        let after = try #require(rule.counter(today: day("2026-10-30"), riyadh))
        #expect(after.occurrence == day("2026-10-25") && after.daysLeft == 0 && after.elapsedDays == 5 && after.closed == 1)
        #expect(rule.next(onOrAfter: day("2026-10-30"), riyadh) == nil, "next keeps its future-only contract")
        let off = MadarUpcomingRule(calendar: .gregorian, year: 2026, month: 10, day: 25, repeats: .none)
        #expect(!off.countUpAfter && off.counter(today: day("2026-10-26"), riyadh) == nil)
        let recurring = MadarUpcomingRule(calendar: .gregorian, month: 10, day: 25, repeats: .yearly, countUpAfter: true)
        #expect(recurring.counter(today: day("2026-10-30"), riyadh)?.daysLeft == 360)
        #expect(recurring.counter(today: day("2026-10-30"), riyadh)?.elapsedDays == nil)
    }
    @Test func countUpUsesTheClampedAndCorrectedCalendarOccurrence() throws {
        let ramadan = MadarUpcomingRule(calendar: .hijri, year: 1448, month: 9, day: 30, repeats: .none, countUpAfter: true)
        #expect(ramadan.counter(today: day("2027-03-10"), riyadh)?.elapsedDays == 2)
        let sighting = MadarCalendarDays(zone: riyadh.zone, source: .sighting, offset: 1)
        #expect(ramadan.counter(today: day("2027-03-10"), sighting)?.elapsedDays == 3)
        let short = MadarUpcomingRule(calendar: .gregorian, year: 2031, month: 2, day: 29, repeats: .none, countUpAfter: true)
        #expect(short.counter(today: day("2031-03-01"), riyadh)?.elapsedDays == 1)
        let leap = MadarUpcomingRule(calendar: .gregorian, year: 2028, month: 2, day: 29, repeats: .none, countUpAfter: true)
        #expect(leap.counter(today: day("2028-03-01"), riyadh)?.elapsedDays == 1)
    }
    @Test func ringRestartsAfterEachOccurrence() throws {
        // countStart = max(countFromDayKey, the day after the previous occurrence): after an occurrence a new count begins.
        let rule = MadarUpcomingRule(calendar: .gregorian, month: 1, day: 10, repeats: .monthly, countFrom: day("2026-01-01"))
        let ring = try #require(rule.ring(today: day("2026-10-15"), riyadh))
        #expect(ring.next == (day("2026-11-10")) && ring.daysLeft == 26)
        #expect(abs(ring.closed - 4.0 / 30.0) < 0.0001) // 11 October to 10 November is 30 days; 4 have passed
        let fresh = MadarUpcomingRule(calendar: .gregorian, month: 1, day: 10, repeats: .monthly, countFrom: day("2026-10-14"))
        let restarted = try #require(fresh.ring(today: day("2026-10-15"), riyadh)); #expect(abs(restarted.closed - 1.0 / 27.0) < 0.0001)
    }
}
