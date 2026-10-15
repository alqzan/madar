import Foundation
import Testing
@testable import MadarCore

struct DiaryRevisionTests {
    private func at(_ s:String)->Date{ISO8601DateFormatter().date(from:s)!}
    // RD1: written at 03:50 under fajr@1 the entry belongs to the previous day and freezes 24 h after the next Fajr,
    // not at that Fajr.
    @Test func fajrEntryAt0350FreezesADayAfterItsDayEnds() throws {
        let riyadh=TimeZone(identifier:"Asia/Riyadh")!,written=at("2024-03-11T03:50:00+03:00")
        let civil=try GregorianDay("2024-03-11"),prayers=try #require(PrayerTimesEngine.calculate(day:civil,place:.riyadh))
        let key=try MadarDay.resolve(instant:written,place:.riyadh,boundary:DiaryFreeze.boundary(policy:"fajr@1"),prayerDays:[prayers]).date
        #expect(key.description=="2024-03-10")
        let freeze=try #require(DiaryFreeze.freezesAt(day:key,boundary:.fajr,timeZone:riyadh,nextDay:prayers))
        #expect(freeze==prayers.fajr.addingTimeInterval(86_400))
        #expect(freeze>prayers.fajr)
        #expect(freeze<at("2024-03-12T06:00:00+03:00"))
    }
    @Test func midnightDayFreezesAtTheSecondMidnight() throws {
        let riyadh=TimeZone(identifier:"Asia/Riyadh")!
        #expect(DiaryFreeze.freezesAt(day:try GregorianDay("2024-03-10"),boundary:DiaryFreeze.boundary(policy:"midnight@1"),timeZone:riyadh,nextDay:nil)==at("2024-03-12T00:00:00+03:00"))
        #expect(DiaryFreeze.boundary(policy:"") == .midnight)
        #expect(DiaryFreeze.boundary(policy:"maghrib@1") == .maghrib)
    }
    @Test func chainShowsOnlyTheNewestRowAndKeepsTheOriginal() {
        let a=UUID(),b=UUID(),c=UUID(),other=UUID()
        let chains=DiaryRevisionChains([.init(id:a,replaces:nil),.init(id:b,replaces:a),.init(id:c,replaces:b),.init(id:other,replaces:nil)])
        #expect(chains.heads==[c,other])
        #expect(chains.originals==[c:a])
        // Undo tombstones the newest row: the previous one is the head again.
        let undone=DiaryRevisionChains([.init(id:a,replaces:nil),.init(id:b,replaces:a)])
        #expect(undone.heads==[b]);#expect(undone.originals==[b:a])
        #expect(DiaryRevisionChains([.init(id:a,replaces:nil)]).originals.isEmpty)
    }
}
