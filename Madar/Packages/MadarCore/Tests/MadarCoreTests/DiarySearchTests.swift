import Foundation
import Testing
@testable import MadarCore
struct DiarySearchTests {
    private func parser(_ week:Int=7) throws -> DiarySearchParser { try .init(today:GregorianDay("2026-10-15"),zone:TimeZone(identifier:"Asia/Riyadh")!,weekStart:week) }
    @Test func previousCalendarPeriodsAndAgoWindow() throws {
        let p=try parser()
        #expect(p.parse("ماذا كتبت العام الماضي؟").map(\.rule)==[.year(2025,.gregorian)])
        #expect(p.parse("الأسبوع الماضي").map(\.rule)==[.range(try GregorianDay("2026-10-03"),try GregorianDay("2026-10-09"))])
        #expect(try parser(1).parse("الأسبوع الماضي").map(\.rule)==[.range(try GregorianDay("2026-10-04"),try GregorianDay("2026-10-10"))])
        #expect(p.parse("الشهر الماضي").map(\.rule)==[.range(try GregorianDay("2026-09-01"),try GregorianDay("2026-09-30"))])
        #expect(p.parse("قبل ٣ أشهر").map(\.rule)==[.range(try GregorianDay("2026-07-12"),try GregorianDay("2026-07-18"))])
        #expect(p.parse("أول أمس").map(\.rule)==[.range(try GregorianDay("2026-10-13"),try GregorianDay("2026-10-13"))])
    }
    @Test func monthsYearsRangesAndFiller() throws {
        let p=try parser()
        #expect(p.parse("أكتوبر ٢٠٢٤").map(\.rule)==[.month(10,2024,.gregorian)])
        #expect(p.parse("في رمضان").map(\.rule)==[.month(9,nil,.hijri)])
        #expect(p.parse("ماذا كتبت عن أمي في رمضان الماضي؟").map(\.rule)==[.month(9,1447,.hijri),.words("امي")])
        #expect(p.parse("١٤٤٥").map(\.rule)==[.year(1445,.hijri)])
        #expect(p.parse("من ١ رمضان ١٤٤٥ إلى ١٠ شوال ١٤٤٥").map(\.rule)==[.range(try GregorianDay("2024-03-11"),try GregorianDay("2024-04-19"))])
        #expect(p.parse("من ١ رمضان ١٤٤٥ إلى 2024-04-19").map(\.rule)==[.range(try GregorianDay("2024-03-11"),try GregorianDay("2024-04-19"))])
    }
    @Test func localProjectPlaceWeekdayAndTypes() throws {
        let id=UUID(),p=try DiarySearchParser(today:GregorianDay("2026-10-15"),zone:TimeZone(identifier:"Asia/Riyadh")!,places:["جدة"],projects:["البيت":id])
        #expect(p.parse("⌗البيت").map(\.rule)==[.project(id)])
        #expect(p.parse("مشروع البيت في جدة").map(\.rule).contains(.place("جدة")))
        #expect(p.parse("في الجمعات صور").map(\.rule)==[.weekday(6),.kind("photo")])
        #expect(p.parse("تسجيلات هوامش نيّات لِغد رسائل").count==5)
    }
    @Test func ArabicNormalizationAndNoInventedAnswer() throws {
        #expect(DiarySearchParser.contains("بالصبر والصلاة",words:"الصَّبر الصلاة"))
        #expect(DiarySearchParser.contains("أمي في مكـة ١٤٤٥",words:"امي مكه 1445"))
        #expect(!DiarySearchParser.contains("يوم في جدة",words:"معنى حياتي"))
        #expect(try parser().parse("ما معنى حياتي؟").map(\.rule)==[.words("ما معني حياتي")])
        #expect(try parser().parse("عنان").map(\.rule)==[.words("عنان")])
    }
}
