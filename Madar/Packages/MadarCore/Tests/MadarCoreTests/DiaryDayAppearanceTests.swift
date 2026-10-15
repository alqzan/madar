import Foundation
import Testing
@testable import MadarCore
struct DiaryDayAppearanceTests {
    private func instant(_ s:String)->Date{ISO8601DateFormatter().date(from:s)!}
    @Test func maghribChangesPresentationOnlyAndHistoricalDaysStayFixed() throws {
        let day=try GregorianDay("2024-03-11"),prayers=try #require(PrayerTimesEngine.calculate(day:day,place:.riyadh))
        let before=DiaryDayAppearance(day:day,currentDay:day,now:instant("2024-03-11T15:00:00+03:00"),prayers:prayers)
        #expect(before.ramadanDay==1);#expect(!before.night);#expect(before.hijriDisplayDay.description=="2024-03-11");#expect(before.iftarAt != nil)
        let after=DiaryDayAppearance(day:day,currentDay:day,now:instant("2024-03-11T20:00:00+03:00"),prayers:prayers)
        #expect(after.ramadanDay==2);#expect(after.night);#expect(after.hijriDisplayDay.description=="2024-03-12");#expect(after.iftarAt==nil);#expect(day.description=="2024-03-11")
        let old=DiaryDayAppearance(day:day,currentDay:try GregorianDay("2026-10-15"),now:instant("2026-10-15T22:00:00+03:00"),prayers:prayers)
        #expect(old.hijriDisplayDay==day);#expect(!old.night);#expect(old.iftarAt==nil)
    }
    @Test func fridayUsesStoredDayAndSightingOffset() throws {
        let day=try GregorianDay("2026-10-16"),prayers=try #require(PrayerTimesEngine.calculate(day:day,place:.riyadh))
        #expect(DiaryDayAppearance(day:day,currentDay:day,now:instant("2026-10-16T15:00:00+03:00"),prayers:prayers).friday)
        #expect(!DiaryDayAppearance(day:day,currentDay:day,now:instant("2026-10-16T07:00:00+03:00"),prayers:prayers).weekAvailable)
        #expect(DiaryDayAppearance(day:day,currentDay:day,now:instant("2026-10-16T16:00:00+03:00"),prayers:prayers).weekAvailable)
        let ramadan=try GregorianDay("2024-03-11"),p=try #require(PrayerTimesEngine.calculate(day:ramadan,place:.riyadh))
        #expect(DiaryDayAppearance(day:ramadan,currentDay:ramadan,now:instant("2024-03-11T15:00:00+03:00"),prayers:p,source:.sighting,offset:2).ramadanDay==3)
    }
}
