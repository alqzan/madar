import Foundation
import Testing
@testable import MadarCore

struct HabitEngineTests {
    let days = MadarCalendarDays(zone: ActivePlace.riyadh.timeZone)
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    func fact(_ d: String, _ value: Int = 1, id: UUID = UUID(), key: String? = nil) -> HabitFact { .init(id: id, day: day(d), periodKey: key ?? d, delta: value) }
    func rule(_ start: String, frequency: HabitFrequency = .daily) -> HabitRule { var r = HabitRule(effectiveFrom: day(start)); r.frequency = frequency; return r }
    @Test func dailyMissesAndMinimumFollowOwnerRules() throws {
        var r = rule("2026-10-01"); r.measure = .count; r.target = 4; r.minimum = 1
        let a = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-01")], today: day("2026-10-03"), days: days)
        #expect(a.periods.first?.outcome == .minimum); #expect(a.streak == 1 && a.consecutiveMisses == 1 && a.atRisk)
        let b = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-01")], today: day("2026-10-04"), days: days)
        #expect(b.streak == 0 && b.consecutiveMisses == 2)
        let c = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-01")], today: day("2026-10-03"), days: days, breakAfter: 1)
        #expect(c.streak == 0)
    }
    @Test(arguments: [HabitFrequency.weekly, .monthly, .yearly])
    func twoMissedPeriodsBreakEachFrequency(_ frequency: HabitFrequency) throws {
        let r = rule("2022-01-01", frequency: frequency)
        let result = try HabitEngine.evaluate(rules: [r], facts: [fact("2022-01-01",key:frequency == .monthly ? "g:2022-01" : frequency == .yearly ? "g:2022" : "2022-01-01")], today: day("2026-01-01"), days: days)
        #expect(result.streak == 0 && result.consecutiveMisses >= 2)
    }
    @Test func freezePersistsAndDoesNotBreakStreak() throws {
        let r = rule("2026-10-01")
        let result = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-01"), fact("2026-10-07")], pauses: [.init(from: day("2026-10-02"), until: day("2026-10-07"))], today: day("2026-10-07"), days: days)
        #expect(result.streak == 2); #expect(result.periods.filter { $0.outcome == .excluded }.count == 5)
        #expect(throws: CoreError.invalidCommand) { try HabitBreak.validateStart(day("2026-10-05"), today: day("2026-10-07")) }
        try HabitBreak.validateStart(day("2026-10-06"), today: day("2026-10-07"))
    }
    @Test func targetChangeDoesNotRewriteYesterdayAndFrequencyStartsNewStreak() throws {
        var old = rule("2026-10-01"); old.measure = .count; old.target = 2
        var new = old; new.effectiveFrom = day("2026-10-02"); new.target = 4
        let result = try HabitEngine.evaluate(rules: [old,new], facts: [fact("2026-10-01", 2),fact("2026-10-02", 2)], today: day("2026-10-02"), days: days)
        #expect(result.periods[0].target == 2 && result.periods[0].met)
        #expect(result.current?.target == 4 && result.current?.outcome == .waiting)
        var weekly = new; weekly.effectiveFrom = day("2026-10-02"); weekly.frequency = .weekly; weekly.target = 1
        let changed = try HabitEngine.evaluate(rules: [old,weekly], facts: [fact("2026-10-01",2)], today: day("2026-10-02"), days: days)
        #expect(changed.current?.start == day("2026-10-02") && changed.streak == 0)
    }
    @Test func changingToWeeklyOnFridayMakesOneDayFirstWeek() throws {
        let old=rule("2026-10-01")
        var weekly=rule("2026-10-02",frequency:.weekly);weekly.measure = .count;weekly.target=7
        let a=try HabitEngine.evaluate(rules:[old,weekly],facts:[],today:day("2026-10-02"),days:days)
        #expect(a.current?.end == day("2026-10-03") && a.current?.target == 1)
    }
    @Test func designatedDaysShortFirstWeekAndExtraBonus() throws {
        var r = rule("2026-10-06", frequency: .weekly); r.measure = .count; r.target = 9; r.weekdays = [2,5]
        let a = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-08",key:"2026-10-03"),fact("2026-10-09",key:"2026-10-03")], today: day("2026-10-09"), days: days)
        #expect(a.current?.target == 1 && a.current?.value == 2 && a.current?.met == true)
        #expect(a.current?.dueDays == [day("2026-10-08")])
        var count = rule("2026-10-07", frequency: .weekly); count.measure = .count; count.target = 7
        let b = try HabitEngine.evaluate(rules: [count], facts: [], today: day("2026-10-08"), days: days)
        #expect(b.current?.target == 3) // Wednesday–Friday: 3 of a seven-day target.
    }
    @Test func weekStartChangeKeepsCurrentWeekAndAbsorbsGapExactlyOnce() throws {
        let r = rule("2026-10-03", frequency: .weekly)
        let a = try HabitEngine.evaluate(rules: [r], facts: [], today: day("2026-10-19"), days: days, weekChanges: [.init(day: day("2026-10-06"), start: .sunday)])
        #expect(a.periods.map(\.start) == [day("2026-10-03"),day("2026-10-10"),day("2026-10-18")])
        #expect(a.periods[0].end == day("2026-10-10") && a.periods[1].end == day("2026-10-18"))
    }
    @Test func missingCalendarDaysClampWithoutDuplicateDueDays() throws {
        var r = rule("2027-02-08", frequency: .monthly); r.hijri = true; r.monthDays = [29,30]
        let a = try HabitEngine.evaluate(rules: [r], facts: [], today: day("2027-03-08"), days: days)
        #expect(a.current?.dueDays == [day("2027-03-08")]); #expect(a.current?.key == "h:1448-09")
        var leap = rule("2027-01-01", frequency: .yearly); leap.yearMonth = 2; leap.yearDay = 29
        let b = try HabitEngine.evaluate(rules: [leap], facts: [], today: day("2028-03-01"), days: days)
        #expect(b.periods[0].dueDays == [day("2027-02-28")]); #expect(b.current?.dueDays == [day("2028-02-29")])
    }
    @Test func independentEventsSumReplayDeduplicatesAndUndoSubtracts() throws {
        var r = rule("2026-10-01"); r.measure = .count; r.target = 4
        let baseline = fact("2026-10-01",2), a = fact("2026-10-01"), b = fact("2026-10-01")
        let result = try HabitEngine.evaluate(rules: [r], facts: [baseline,a,b,a], today: day("2026-10-01"), days: days)
        #expect(result.current?.value == 4)
        let undo = try HabitEngine.evaluate(rules: [r], facts: [baseline,a,b,fact("2026-10-01",-1)], today: day("2026-10-01"), days: days)
        #expect(undo.current?.value == 3)
    }
    @Test func hijriCorrectionDoesNotMoveARecordedRamadanPeriod() throws {
        var r=rule("2027-03-08",frequency:.monthly);r.hijri=true;r.monthDays=[30]
        let a=try HabitEngine.evaluate(rules:[r],facts:[fact("2027-03-08",key:"h:1448-09")],today:day("2027-03-09"),days:days,calendarChanges:[.init(day:day("2027-03-09"),source:.sighting,offset:1)])
        #expect(a.periods.first?.key=="h:1448-09" && a.periods.first?.value==1 && a.periods.first?.met==true)
        #expect(a.current?.key=="h:1448-10" && a.current?.value==0)
    }
    @Test func quantityUnitsNeverMix() throws {
        var r=rule("2026-10-01");r.measure = .duration;r.unit="minutes";r.target=30
        let values=[HabitFact(id:UUID(),day:day("2026-10-01"),periodKey:"2026-10-01",delta:6000,unit:"steps"),HabitFact(id:UUID(),day:day("2026-10-01"),periodKey:"2026-10-01",delta:15,unit:"minutes")]
        let a=try HabitEngine.evaluate(rules:[r],facts:values,today:day("2026-10-01"),days:days)
        #expect(a.current?.value==15 && a.current?.outcome == .waiting)
    }
    @Test func ownerStreakAndUnitsRemainAuthoritative() throws {
        var r = rule("2026-10-01"); r.measure = .health; r.unit = "exerciseMinutes"; r.target = 30
        try r.validate()
        let result = try HabitEngine.evaluate(rules: [r], facts: [], today: day("2026-10-01"), days: days, ownerStreak: 23)
        #expect(result.streak == 23)
        r.unit = "pages"; #expect(throws: CoreError.invalidCommand) { try r.validate() }
    }
    @Test func anchoredAndCrossMidnightWindowsUseActivePlace() throws {
        var r = rule("2026-10-01"); r.windowAnchor = .fajr; r.windowStart = 0; r.windowEnd = 90
        let place = try ActivePlace(latitude: 51.5074, longitude: -0.1278, timeZoneID: "Europe/London")
        let prayer = try #require(PrayerTimesEngine.calculate(day: day("2026-10-01"), place: place))
        let window = try #require(HabitEngine.window(rule:r, civilDay:day("2026-10-01"),place:place,prayer:prayer))
        #expect(window.start == prayer.fajr && window.duration == 5400)
        #expect(HabitEngine.window(rule:r,civilDay:day("2026-10-01"),place:.riyadh,prayer:prayer) == nil)
        r.windowAnchor = nil; r.windowStart = 1320; r.windowEnd = 60
        let night = try #require(HabitEngine.window(rule:r,civilDay:day("2026-10-01"),place:place,prayer:nil))
        #expect(night.duration == 10800)
        let current = try #require(HabitEngine.evaluate(rules:[r],facts:[],today:day("2026-10-01"),days:days).current)
        #expect(HabitEngine.isNow(current,today:day("2026-10-01"),instant:night.start,window:night,pauses:[]))
        #expect(!HabitEngine.isNow(current,today:day("2026-10-01"),instant:night.end,window:night,pauses:[]))
    }
}
