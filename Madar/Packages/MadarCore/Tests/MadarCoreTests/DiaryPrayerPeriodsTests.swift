import Foundation
import Testing
@testable import MadarCore

@Suite struct DiaryPrayerPeriodsTests {
    // Hand-specified times, Asia/Riyadh, 15 Oct 2026 (as minutes after local midnight).
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private func t(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    private var times: PrayerDay {
        get throws {
            try PrayerDay(day: GregorianDay(year: 2026, month: 10, day: 15), place: ActivePlace(latitude: 24.7, longitude: 46.7, timeZoneID: "Asia/Riyadh"),
                          fajr: t(300), sunrise: t(370), dhuhr: t(700), asr: t(900), maghrib: t(1050), isha: t(1140))
        }
    }

    @Test func boundaryBelongsToThePeriodItOpens() throws {
        let x = try times
        #expect(DiaryPrayerPeriods.period(at: t(299.9), times: x, preFajrExists: true) == .beforeFajr)
        #expect(DiaryPrayerPeriods.period(at: t(300), times: x, preFajrExists: true) == .afterFajr)
        #expect(DiaryPrayerPeriods.period(at: t(370), times: x, preFajrExists: true) == .duha)
        #expect(DiaryPrayerPeriods.period(at: t(700), times: x, preFajrExists: true) == .afterDhuhr)
        #expect(DiaryPrayerPeriods.period(at: t(900), times: x, preFajrExists: true) == .afterAsr)
        #expect(DiaryPrayerPeriods.period(at: t(1050), times: x, preFajrExists: true) == .afterMaghrib)
        #expect(DiaryPrayerPeriods.period(at: t(1140), times: x, preFajrExists: true) == .afterIsha)
    }

    @Test func entriesAfterIshaStayInAfterIshaUntilTheDayEnds() throws {
        let x = try times
        #expect(DiaryPrayerPeriods.period(at: t(1439), times: x, preFajrExists: true) == .afterIsha)
        #expect(DiaryPrayerPeriods.period(at: t(1700), times: x, preFajrExists: false) == .afterIsha)
    }

    @Test func dayStartingAtFajrHasNoPreFajrPeriod() throws {
        let x = try times
        #expect(DiaryPrayerPeriods.period(at: t(100), times: x, preFajrExists: false) == .afterFajr)
        #expect(DiaryPrayerPeriods.period(at: t(100), times: x, preFajrExists: true) == .beforeFajr)
    }

    @Test func onlyPeriodsWithEntriesGetAHeadingAndEachAppearsOnce() throws {
        let x = try times
        let headings = DiaryPrayerPeriods.headings(for: [t(10), t(20), t(720), t(800), t(1100), t(1200)], times: x, preFajrExists: true)
        #expect(headings.map(\.period) == [.beforeFajr, .afterDhuhr, .afterMaghrib, .afterIsha])
        #expect(headings.map(\.index) == [0, 2, 4, 5])
        #expect(headings[0].time == nil)
        #expect(headings[1].time == t(700))
        #expect(headings[3].time == t(1140))
    }

    @Test func emptyDayHasNoHeadings() throws {
        #expect(try DiaryPrayerPeriods.headings(for: [], times: times, preFajrExists: true).isEmpty)
    }

    @Test func outOfOrderEntryNeverRepeatsAHeading() throws {
        let x = try times
        let headings = DiaryPrayerPeriods.headings(for: [t(720), t(400), t(730)], times: x, preFajrExists: true)
        #expect(headings.map(\.period) == [.afterDhuhr, .duha])
    }
}
