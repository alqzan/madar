import Foundation
import Testing
@testable import MadarCore

/// Review T14 items 10 and 11. Expected values are hand figures, not the engine's output:
/// Umm al-Qura: 1 Ramadan 1448 = Mon 8 Feb 2027, Ramadan 1448 has 29 days (spec §7.1), so 29 Ramadan = Mon 8 Mar 2027 and 1 Shawwal = Tue 9 Mar 2027.
/// Spec: Isha is 120 min after Maghrib on Ramadan days and 90 min otherwise.
/// London on 29 Mar 2026: clocks go forward at 01:00 UTC, so the civil day is 23 h; solar noon is about 12:05 UTC (13:05 BST),
/// sunset about 19:27 BST. Oslo at the June solstice: sunset about 22:43 CEST.
struct PrayerCalendarEdgeTests {
    private func gap(_ day: String) throws -> TimeInterval {
        let prayers = try #require(PrayerTimesEngine.calculate(day: GregorianDay(day), place: .riyadh))
        return prayers.isha.timeIntervalSince(prayers.maghrib)
    }
    @Test func ramadanIshaIntervalChangesExactlyOnTheMonthEdges() throws {
        #expect(try gap("2027-02-07") == 90 * 60)   // last Sha'ban day
        #expect(try gap("2027-02-08") == 120 * 60)  // 1 Ramadan
        #expect(try gap("2027-03-08") == 120 * 60)  // 29 Ramadan, the last day
        #expect(try gap("2027-03-09") == 90 * 60)   // 1 Shawwal
    }
    private func local(_ date: Date, _ zone: String) -> Double {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour!) + Double(c.minute!) / 60
    }
    @Test func londonOnTheClockChangeDayIsTwentyThreeHoursAndStaysOrdered() throws {
        let london = try ActivePlace(latitude: 51.5074, longitude: -0.1278, timeZoneID: "Europe/London")
        let day = try GregorianDay("2026-03-29")
        let prayers = try #require(PrayerTimesEngine.calculate(day: day, place: london))
        let start = day.date(in: london.timeZone), next = day.adding(days: 1).date(in: london.timeZone)
        #expect(next.timeIntervalSince(start) == 23 * 3600)
        #expect(prayers.fajr < prayers.sunrise && prayers.sunrise < prayers.dhuhr && prayers.dhuhr < prayers.asr && prayers.asr < prayers.maghrib && prayers.maghrib < prayers.isha)
        #expect(abs(local(prayers.dhuhr, "Europe/London") - 13.1) < 0.15)    // 13:05–13:07 BST
        #expect((19.33...19.6).contains(local(prayers.maghrib, "Europe/London")))
    }
    @Test func osloAtTheSolsticeStillGivesAnOrderedDayWithinTheHighLatitudeRule() throws {
        let oslo = try ActivePlace(latitude: 59.9139, longitude: 10.7522, timeZoneID: "Europe/Oslo")
        let prayers = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-06-21"), place: oslo))
        #expect(prayers.fajr < prayers.sunrise && prayers.sunrise < prayers.dhuhr && prayers.dhuhr < prayers.asr && prayers.asr < prayers.maghrib && prayers.maghrib < prayers.isha)
        #expect((22.5...23.0).contains(local(prayers.maghrib, "Europe/Oslo")))
        // Whatever fallback the rule picks, Isha stays the same prayer day: within six hours of Maghrib.
        #expect(prayers.isha.timeIntervalSince(prayers.maghrib) <= 6 * 3600)
    }
}
