import Foundation
import Testing
@testable import MadarCore

/// M5-X00 golden values: the owner's example (16 Oct 2026) and Gregorian calendar facts, written out by hand.
struct RecurrenceTests {
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    func days(_ list: [String]) -> [GregorianDay] { list.map(day) }

    @Test func ownerRentEverySixMonthsFirstDueInFourMonthsAndTwoDays() throws {
        let today = day("2026-10-16")
        // «أول موعد بعد ٤ أشهر ويومين» from 16 Oct 2026 is 18 Feb 2027.
        #expect(RecurrencePhrase.relative(from: today, to: day("2027-02-18")) == "بعد ٤ أشهر ويومين")
        #expect(RecurrencePhrase.span(from: today, to: day("2027-02-18")) == (0, 4, 2))
        let rent = try #require(Recurrence(every: 6, unit: .month, first: day("2027-02-18")))
        #expect(rent.preview(from: today) == days(["2027-02-18", "2027-08-18", "2028-02-18"]))
        #expect(RecurrencePhrase.every(rent) == "كل ٦ أشهر")
        #expect(rent.next(onOrAfter: today) == day("2027-02-18"))
        #expect(rent.next(after: day("2027-02-18")) == day("2027-08-18"))
        #expect(rent.occurrences(from: today, before: day("2027-02-18")).isEmpty)
        #expect(rent.occurrences(from: day("2026-10-16"), before: day("2028-02-19")) == days(["2027-02-18", "2027-08-18", "2028-02-18"]))
    }

    @Test func monthEndClampsFromTheFirstDateNotTheLastOne() throws {
        let monthly = try #require(Recurrence(every: 1, unit: .month, first: day("2027-01-31")))
        #expect(monthly.preview(from: day("2027-01-01"), count: 5) == days(["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30", "2027-05-31"]))
        let quarterly = try #require(Recurrence(every: 3, unit: .month, first: day("2026-11-30")))
        #expect(quarterly.preview(from: day("2026-11-01"), count: 3) == days(["2026-11-30", "2027-02-28", "2027-05-30"]))
    }

    @Test func leapYearFebruary() throws {
        #expect(Recurrence(every: 1, unit: .month, first: day("2028-01-31"))?.occurrence(1) == day("2028-02-29"))
        let yearly = try #require(Recurrence(every: 1, unit: .year, first: day("2028-02-29")))
        #expect(yearly.preview(from: day("2028-01-01"), count: 5) == days(["2028-02-29", "2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"]))
        #expect(RecurrencePhrase.every(yearly) == "كل سنة")
    }

    @Test func dailyAndWeekly() throws {
        let fortnight = try #require(Recurrence(every: 2, unit: .week, first: day("2026-10-16")))
        #expect(fortnight.preview(from: day("2026-10-17")) == days(["2026-10-30", "2026-11-13", "2026-11-27"]))
        #expect(fortnight.occurrences(from: day("2026-12-25"), before: day("2027-01-09")) == days(["2026-12-25", "2027-01-08"]))
        let threeDays = try #require(Recurrence(every: 3, unit: .day, first: day("2026-12-30")))
        #expect(threeDays.preview(from: day("2026-12-30")) == days(["2026-12-30", "2027-01-02", "2027-01-05"]))
        #expect(RecurrencePhrase.every(fortnight) == "كل أسبوعين" && RecurrencePhrase.every(threeDays) == "كل ٣ أيام")
    }

    @Test func yearlyEveryTwoYears() throws {
        let licence = try #require(Recurrence(every: 2, unit: .year, first: day("2027-03-10")))
        #expect(licence.preview(from: day("2027-03-11")) == days(["2029-03-10", "2031-03-10", "2033-03-10"]))
        #expect(RecurrencePhrase.every(licence) == "كل سنتين")
    }

    @Test func firstDateInThePastKeepsItsRhythm() throws {
        let gym = try #require(Recurrence(every: 1, unit: .month, first: day("2026-01-15")))
        #expect(gym.next(onOrAfter: day("2026-10-16")) == day("2026-11-15"))
        #expect(gym.next(onOrAfter: day("2026-10-15")) == day("2026-10-15"))
        #expect(gym.next(after: day("2026-10-15")) == day("2026-11-15"))
        #expect(gym.occurrences(from: day("2026-10-01"), before: day("2026-12-01")) == days(["2026-10-15", "2026-11-15"]))
        #expect(gym.occurrences(from: day("2025-12-01"), before: day("2026-02-01")) == days(["2026-01-15"]))
        #expect(RecurrencePhrase.relative(from: day("2026-10-16"), to: day("2026-10-13")) == "قبل ٣ أيام")
    }

    @Test func aLinkedPaymentSettlesTheNearestDueDay() throws {
        let rent = try #require(Recurrence(every: 6, unit: .month, first: day("2027-02-18")))
        // Paid three days early: the February rent is settled; August and the next February stay due.
        #expect(rent.occurrenceIndex(paidOn: day("2027-02-15")) == 0)
        #expect(rent.unpaid(from: day("2027-01-01"), before: day("2028-03-01"), paidOn: days(["2027-02-15"])) == days(["2027-08-18", "2028-02-18"]))
        // Paid ten days late: still February's.
        #expect(rent.occurrenceIndex(paidOn: day("2027-02-28")) == 0)
        // A payment nearer the half-year before the first due day settles nothing.
        #expect(rent.occurrenceIndex(paidOn: day("2026-08-20")) == nil)
        // A tie goes to the earlier due day.
        let alternate = try #require(Recurrence(every: 2, unit: .day, first: day("2026-10-01")))
        #expect(alternate.occurrenceIndex(paidOn: day("2026-10-02")) == 0)
        #expect(alternate.occurrenceIndex(paidOn: day("2026-10-03")) == 1)
    }

    @Test func storedFieldsAndLimits() {
        #expect(Recurrence(every: 6, unit: "month", firstDayKey: "2027-02-18") == Recurrence(every: 6, unit: .month, first: day("2027-02-18")))
        #expect(Recurrence(every: nil, unit: "month", firstDayKey: "2027-02-18") == nil)
        #expect(Recurrence(every: 6, unit: "fortnight", firstDayKey: "2027-02-18") == nil)
        #expect(Recurrence(every: 6, unit: "month", firstDayKey: "18/02/2027") == nil)
        #expect(Recurrence(every: 0, unit: .day, first: day("2027-02-18")) == nil)
        #expect(Recurrence(every: 121, unit: .month, first: day("2027-02-18")) == nil)
        #expect(Recurrence(every: 365, unit: .day, first: day("2027-02-18")) != nil)
        #expect(Recurrence(every: 11, unit: .year, first: day("2027-02-18")) == nil)
    }

    @Test func arabicNumberAgreement() {
        let western = MadarNumberFormatter(style: .western)
        #expect(RecurrencePhrase.count(1, .month) == "شهر")
        #expect(RecurrencePhrase.count(2, .day) == "يومين")
        #expect(RecurrencePhrase.count(10, .week) == "١٠ أسابيع")
        #expect(RecurrencePhrase.count(11, .month) == "١١ شهرًا")
        #expect(RecurrencePhrase.count(3, .year) == "٣ سنوات")
        #expect(RecurrencePhrase.count(100, .day) == "١٠٠ يوم")
        #expect(RecurrencePhrase.count(103, .day, digits: western) == "103 أيام")
        #expect(RecurrencePhrase.relative(from: day("2026-10-16"), to: day("2026-10-16")) == "اليوم")
        #expect(RecurrencePhrase.relative(from: day("2026-10-16"), to: day("2026-10-17")) == "غدًا")
        #expect(RecurrencePhrase.relative(from: day("2026-10-16"), to: day("2027-12-16")) == "بعد سنة وشهرين")
        #expect(RecurrencePhrase.relative(from: day("2027-01-31"), to: day("2027-03-01")) == "بعد شهر ويوم")
    }
}
