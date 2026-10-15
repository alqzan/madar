import Foundation
import Testing
@testable import MadarCore

struct DiaryTravelTests {
    private let id=UUID(uuidString:"00000000-0000-4000-8000-000000000001")!
    // §7.3 travel theme, canonical notes-app/21: entry stamped 29 September, the next page reads «اليوم الثاني».
    @Test func arrivalDayIsDayOneAndTheNextIsTheSecond() throws {
        let span=DiaryTravelSpan(id:id,city:"إسطنبول",arrival:try GregorianDay("2026-09-29"),departure:nil)
        #expect(span.number(of:try GregorianDay("2026-09-29"))==1)
        #expect(span.number(of:try GregorianDay("2026-09-30"))==2)
        #expect(DiaryTravelCalendar.ordinal(2)=="الثاني")
        #expect(DiaryTravelCalendar.ordinal(10)=="العاشر")
        #expect(DiaryTravelCalendar.ordinal(11)==nil)
        #expect(span.number(of:try GregorianDay("2026-10-31"))==33)
    }
    // §10: the trip window is [start, end). The return day is home; a same-day trip still owns its day.
    @Test func coverageEndsBeforeTheReturnDay() throws {
        let span=DiaryTravelSpan(id:id,city:"لندن",arrival:try GregorianDay("2026-09-29"),departure:try GregorianDay("2026-10-05"))
        #expect(!span.covers(try GregorianDay("2026-09-28")))
        #expect(span.covers(try GregorianDay("2026-10-04")))
        #expect(!span.covers(try GregorianDay("2026-10-05")))
        let sameDay=DiaryTravelSpan(id:id,city:"جدة",arrival:try GregorianDay("2026-09-29"),departure:try GregorianDay("2026-09-29"))
        #expect(sameDay.covers(try GregorianDay("2026-09-29")))
        #expect(DiaryTravelCalendar.span(covering:try GregorianDay("2026-10-05"),in:[span])==nil)
    }
    @Test func laterArrivalWinsWhenSpansTouch() throws {
        let first=DiaryTravelSpan(id:id,city:"إسطنبول",arrival:try GregorianDay("2026-09-29"),departure:nil)
        let second=DiaryTravelSpan(id:UUID(),city:"أنقرة",arrival:try GregorianDay("2026-10-02"),departure:nil)
        #expect(DiaryTravelCalendar.span(covering:try GregorianDay("2026-10-03"),in:[first,second])?.city=="أنقرة")
    }
    // Riyadh–Istanbul great-circle ≈ 2,440 km (canonical «٢٬٤٤٠ كم عن الرياض»).
    @Test func fallbackDistanceMatchesGreatCircle() throws {
        let istanbul=try ActivePlace(latitude:41.0082,longitude:28.9784,timeZoneID:"Europe/Istanbul")
        let km=DiaryTravelCalendar.kilometres(from:.riyadh,to:istanbul)
        #expect(abs(km-2440)<30)
    }
}
