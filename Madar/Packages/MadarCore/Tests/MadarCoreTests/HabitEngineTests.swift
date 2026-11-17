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
    /// B2-8 (10 Nov): an edit saved on 5 Oct (a rename or goal change keeps «كل ٣ أيام») must not restart the block counting.
    /// Blocks stay 1–3, 4–6, 7–9, 10–12 Oct, worked by hand.
    @Test func editingAnEveryThreeDaysHabitKeepsItsBlocks() throws {
        var first = rule("2026-10-01", frequency: .interval); first.intervalDays = 3
        var edited = rule("2026-10-05", frequency: .interval); edited.intervalDays = 3; edited.target = 1
        let result = try HabitEngine.evaluate(rules: [first, edited], facts: [], today: day("2026-10-10"), days: days)
        #expect(result.periods.map(\.key) == ["2026-10-01", "2026-10-04", "2026-10-07", "2026-10-10"])
    }
    @Test(arguments: [HabitFrequency.weekly, .monthly, .yearly])
    func twoMissedPeriodsBreakEachFrequency(_ frequency: HabitFrequency) throws {
        let r = rule("2022-01-01", frequency: frequency)
        let result = try HabitEngine.evaluate(rules: [r], facts: [fact("2022-01-01",key:frequency == .monthly ? "g:2022-01" : frequency == .yearly ? "g:2022" : "2022-01-01")], today: day("2026-01-01"), days: days)
        #expect(result.streak == 0 && result.consecutiveMisses >= 2)
    }
    /// FB-39 (owner, 6 Nov): «كل ٣ أيام» from 1 Oct. Periods 1–3, 4–6, 7–9, 10–12 Oct. Done on 2 Oct and 9 Oct only:
    /// complete, missed (one miss keeps the streak at breakAfter 2), complete, then waiting. Streak 2. Worked by hand.
    @Test func everyThreeDaysCountsAnyDayInsideEachBlock() throws {
        var r = rule("2026-10-01", frequency: .interval); r.intervalDays = 3
        let result = try HabitEngine.evaluate(rules: [r], facts: [fact("2026-10-02", key: ""), fact("2026-10-09", key: "")], today: day("2026-10-10"), days: days)
        #expect(result.periods.map(\.key) == ["2026-10-01", "2026-10-04", "2026-10-07", "2026-10-10"])
        #expect(result.periods.map(\.outcome) == [.complete, .missed, .complete, .waiting])
        #expect(result.periods.last?.dueDays == [day("2026-10-10"), day("2026-10-11"), day("2026-10-12")])
        #expect(result.streak == 2 && result.consecutiveMisses == 0)
        var missing = rule("2026-10-01", frequency: .interval)
        #expect(throws: CoreError.invalidCommand) { try missing.validate() }
        missing.intervalDays = 1
        #expect(throws: CoreError.invalidCommand) { try missing.validate() }
        var daily = rule("2026-10-01"); daily.intervalDays = 3
        #expect(throws: CoreError.invalidCommand) { try daily.validate() }
        // A rule saved before intervals existed still decodes, with no interval.
        let old = try JSONEncoder().encode(rule("2026-10-01"))
        var object = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any]); object.removeValue(forKey: "intervalDays")
        #expect(try JSONDecoder().decode(HabitRule.self, from: JSONSerialization.data(withJSONObject: object)).intervalDays == nil)
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
    @Test func indexedFactsKeepStoredKeysAndOriginalAdditionOrder() throws {
        var r = rule("2026-10-01"); r.measure = .count; r.target = 1
        let first = fact("2026-10-01", Int.max, key: "")
        let subtract = fact("2026-10-02", -1, key: "2026-10-01")
        let add = fact("2026-10-01", 1, key: "")
        let result = try HabitEngine.evaluate(rules: [r], facts: [first, subtract, add], today: day("2026-10-02"), days: days)
        #expect(result.periods.first?.value == Int.max)
        #expect(throws: CoreError.invalidCommand) {
            try HabitEngine.evaluate(rules: [r], facts: [first, add, subtract], today: day("2026-10-02"), days: days)
        }
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
    /// Review T14 item 14: the streak is derived, so deleting an old record changes it at once. Daily from 1 Oct, done 1–5 Oct, today 6 Oct:
    /// streak 5 (worked by hand). Removing the records of 2 and 3 Oct leaves two missed days in a row, which break it: only 4 and 5 Oct count, streak 2.
    @Test func deletingOldRecordsRecomputesTheStreak() throws {
        let r = rule("2026-10-01")
        let all = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"].map { fact($0) }
        #expect(try HabitEngine.evaluate(rules: [r], facts: all, today: day("2026-10-06"), days: days).streak == 5)
        let kept = all.filter { ![day("2026-10-02"), day("2026-10-03")].contains($0.day) }
        #expect(try HabitEngine.evaluate(rules: [r], facts: kept, today: day("2026-10-06"), days: days).streak == 2)
    }
    /// Owner, 17 Nov 2026 (idea 17): the Monday/Thursday fast is due only on those two weekdays (Foundation 2 and 5),
    /// and its question window opens the evening before, 8 hours ahead of Fajr, so the reminder comes the night before.
    /// Calendar facts: 5 and 8 October 2026 are a Monday and a Thursday; Riyadh is UTC+3.
    @Test func mondayThursdayFastIsDueOnlyThoseDaysAndAsksTheNightBefore() throws {
        let preset = HabitPresets.mondayThursdayFast(from: day("2026-10-01"))
        try preset.validate()
        #expect(preset.weekdays == [2, 5] && preset.frequency == .weekly)
        let result = try HabitEngine.evaluate(rules: [preset], facts: [], today: day("2026-10-09"), days: days)
        let dueDays = result.periods.flatMap(\.dueDays)
        #expect(dueDays == [day("2026-10-01"), day("2026-10-05"), day("2026-10-08")])
        #expect(dueDays.allSatisfy { [2, 5].contains(HabitEngine.weekday($0)) })
        let monday = day("2026-10-05")
        let prayer = try #require(PrayerTimesEngine.calculate(day: monday, place: .riyadh))
        let window = try #require(HabitEngine.window(rule: preset, civilDay: monday, place: .riyadh, prayer: prayer))
        #expect(window.start == prayer.fajr.addingTimeInterval(-480 * 60) && window.end == prayer.fajr.addingTimeInterval(720 * 60))
        var riyadh = Calendar(identifier: .gregorian); riyadh.timeZone = ActivePlace.riyadh.timeZone
        let parts = riyadh.dateComponents([.year, .month, .day, .hour], from: window.start)
        #expect(parts.day == 4 && parts.month == 10)   // Sunday evening, the day before the Monday fast
        #expect((parts.hour ?? 0) >= 18)
    }
    /// Owner, 17 Nov 2026 (idea 14): Health can also supply last night's sleep (minutes) and the number of workouts.
    /// Targets are the rule's: 7 hours = 420 minutes; one workout.
    @Test func sleepAndWorkoutsAreHealthUnitsWithTheirOwnTargets() throws {
        for unit in ["sleepMinutes", "workouts"] {
            var r = rule("2026-10-01"); r.measure = .health; r.unit = unit; r.target = unit == "sleepMinutes" ? 420 : 1
            try r.validate()
        }
        var bad = rule("2026-10-01"); bad.measure = .health; bad.unit = "calories"; #expect(throws: CoreError.invalidCommand) { try bad.validate() }
        var sleep = rule("2026-10-01"); sleep.measure = .health; sleep.unit = "sleepMinutes"; sleep.target = 420
        func sleepFact(_ d: String, _ minutes: Int, unit: String = "sleepMinutes") -> HabitFact { .init(id: UUID(), day: day(d), periodKey: "", delta: minutes, unit: unit) }
        let result = try HabitEngine.evaluate(rules: [sleep], facts: [sleepFact("2026-10-01", 450), sleepFact("2026-10-02", 419), sleepFact("2026-10-03", 420), sleepFact("2026-10-03", 9999, unit: "steps")], today: day("2026-10-04"), days: days)
        #expect(result.periods.map(\.outcome) == [.complete, .missed, .complete, .waiting])
        #expect(result.periods[2].value == 420)   // another unit's fact never adds to it
        var workouts = rule("2026-10-01"); workouts.measure = .health; workouts.unit = "workouts"; workouts.target = 1
        let w = try HabitEngine.evaluate(rules: [workouts], facts: [.init(id: UUID(), day: day("2026-10-01"), periodKey: "", delta: 2, unit: "workouts")], today: day("2026-10-01"), days: days)
        #expect(w.current?.outcome == .complete)
    }
    @Test func walkingHabitsAcceptTheNewHealthUnitsInCommands() throws {
        let id = JSONValue.string(UUID().uuidString)
        func save(_ unit: String) throws -> [String: JSONValue] {
            var r = rule("2026-10-01"); r.measure = .health; r.unit = unit; r.target = 420
            let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(r))
            return ["id": id, "name": .string("النوم"), "source": .string("walking"), "reminder": .string("none"), "rule": json]
        }
        for unit in ["steps", "exerciseMinutes", "sleepMinutes", "workouts"] { #expect(HabitCommand.parse("habit.save", try save(unit)) != nil) }
        #expect(HabitCommand.parse("habit.save", try save("calories")) == nil)
        #expect(HabitCommand.parse("habit.refreshHealth", ["id": id, "unit": .string("sleepMinutes"), "values": .object(["2026-10-14": .number(430)])]) != nil)
        #expect(HabitCommand.parse("habit.refreshHealth", ["id": id, "unit": .string("calories"), "values": .object([:])]) == nil)
    }
    /// Idea 12 (owner, 17 Nov 2026): 30 met days earn one rest day. Worked by hand with a daily habit from 1 Oct 2026,
    /// breaking after one miss (`breakAfter: 1`) so a spent rest day is visible: days 1–30 met (30 Oct), 31 Oct missed.
    @Test func thirtyMetDaysEarnOneRestDayThatASingleMissSpends() throws {
        let r = rule("2026-10-01")
        let met = (0..<30).map { fact(day("2026-10-01").adding(days: $0).description) }
        let without = try HabitEngine.evaluate(rules: [r], facts: met, today: day("2026-11-01"), days: days, breakAfter: 1)
        #expect(without.streak == 0)                      // no rest day: the miss on 31 Oct breaks it at once
        let with = try HabitEngine.evaluate(rules: [r], facts: met, today: day("2026-11-01"), days: days, breakAfter: 1, earnedRestEvery: 30)
        #expect(with.streak == 30 && with.consecutiveMisses == 0 && !with.atRisk)   // the rest day is spent, the streak stays
        // A second miss in a row has no credit left and breaks it.
        let twice = try HabitEngine.evaluate(rules: [r], facts: met, today: day("2026-11-02"), days: days, breakAfter: 1, earnedRestEvery: 30)
        #expect(twice.streak == 0)
        // Twenty-nine met days earn nothing.
        let short = try HabitEngine.evaluate(rules: [r], facts: Array(met.prefix(29)), today: day("2026-10-31"), days: days, breakAfter: 1, earnedRestEvery: 30)
        #expect(short.streak == 0)
        // The default keeps today's behaviour exactly.
        #expect(try HabitEngine.evaluate(rules: [r], facts: met, today: day("2026-11-01"), days: days, breakAfter: 1).streak == 0)
    }
    /// Idea 8 (owner, 17 Nov 2026): a goal that grows gradually is already expressible as dated rule versions — each daily period
    /// takes the target in force that day, closed days keep theirs. 5 pages from 1 Oct, 6 from 8 Oct, 7 from 15 Oct.
    @Test func datedRuleVersionsGrowTheGoalWithoutRewritingClosedDays() throws {
        func pages(_ from: String, _ target: Int) -> HabitRule { var r = rule(from); r.measure = .count; r.unit = "pages"; r.target = target; return r }
        let result = try HabitEngine.evaluate(rules: [pages("2026-10-01", 5), pages("2026-10-08", 6), pages("2026-10-15", 7)], facts: [], today: day("2026-10-16"), days: days)
        #expect(result.periods.map(\.target) == Array(repeating: 5, count: 7) + Array(repeating: 6, count: 7) + [7, 7])
        // A rule dated in the future is ignored until its day.
        let early = try HabitEngine.evaluate(rules: [pages("2026-10-01", 5), pages("2026-10-08", 6)], facts: [], today: day("2026-10-03"), days: days)
        #expect(early.periods.map(\.target) == [5, 5, 5])
    }
    /// Idea 16 (owner, 17 Nov 2026): Ramadan mode. 1 Ramadan 1447 fell on 18 or 19 Feb 2026 (Umm al-Qura: 19 Feb), 1 Shawwal on 20 Mar.
    @Test func ramadanPresetsFollowTheHijriMonthAndAnchorToIshaAndFajr() throws {
        let umm = MadarCalendarDays(zone: ActivePlace.riyadh.timeZone, source: .ummAlQura)
        #expect(HabitPresets.isRamadan(day("2026-03-01"), days: umm) && !HabitPresets.isRamadan(day("2026-04-01"), days: umm) && !HabitPresets.isRamadan(day("2026-01-15"), days: umm))
        let qiyam = HabitPresets.ramadanQiyam(from: day("2026-03-01")), suhoor = HabitPresets.ramadanSuhoor(from: day("2026-03-01"))
        try qiyam.validate(); try suhoor.validate()
        let prayer = try #require(PrayerTimesEngine.calculate(day: day("2026-03-01"), place: .riyadh))
        let night = try #require(HabitEngine.window(rule: qiyam, civilDay: day("2026-03-01"), place: .riyadh, prayer: prayer))
        #expect(night.start == prayer.isha.addingTimeInterval(90 * 60) && night.duration == 270 * 60)   // after Taraweeh
        let before = try #require(HabitEngine.window(rule: suhoor, civilDay: day("2026-03-01"), place: .riyadh, prayer: prayer))
        #expect(before.end == prayer.fajr && before.duration == 90 * 60)
        #expect(HabitPresets.named("preset.fast", from: day("2026-03-01"))?.name == HabitPresets.mondayThursdayFastName && HabitPresets.named("custom", from: day("2026-03-01")) == nil)
    }
}
