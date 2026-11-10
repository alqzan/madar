#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    func prepareHabitFixture(group:URL) throws {
        guard let variant=ProcessInfo.processInfo.environment["MADAR_UI_HABIT_FIXTURE"],group.deletingLastPathComponent().lastPathComponent == "UITestStores" else{return}
        let context=ModelContext(container)
        guard try context.fetchCount(FetchDescriptor<Habit>()) == 0 else{return}
        let settings=try SettingsStore(context:context)
        var initialSettings: [String: JSONValue] = ["core.dayStart": .string("midnight")]
        if let firstCalendar = ProcessInfo.processInfo.environment["MADAR_UI_FIRST_CALENDAR"], ["hijri", "gregorian"].contains(firstCalendar) {
            initialSettings["core.firstCalendar"] = .string(firstCalendar)
        }
        _ = try settings.stage(initialSettings)
        let marker=DeviceSetting();marker.key="sys.onboardingCompleted";marker.valueJSON=Data("true".utf8);context.insert(marker)
        if variant == "partialDuration" {
            let today = GregorianDay.containing(prayerNow(), in: activePlace.timeZone)
            let habit = Habit(); habit.name = "قراءة هادئة"; habit.startDate = today.adding(days: -6).date(in: activePlace.timeZone); context.insert(habit)
            let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = today.adding(days: -6).description
            policy.frequency = "daily"; policy.measure = "duration"; policy.unit = "minutes"; policy.target = 30; context.insert(policy)
            let event = HabitEvent(); event.habitID = habit.id; event.dayKey = today.adding(days: -1).description; event.periodKey = event.dayKey; event.delta = 1; event.unit = "minutes"; context.insert(event)
            try context.save(); return
        }
        if variant == "sameDayTrip" {
            let today = GregorianDay.containing(prayerNow(), in: activePlace.timeZone)
            _ = try settings.stage(["bahw.travelFreezesHome": .bool(true)])
            let habit = Habit(); habit.name = "عادة البيت"; habit.homeOnly = true
            habit.startDate = today.adding(days: -3).date(in: activePlace.timeZone); context.insert(habit)
            let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = today.adding(days: -3).description
            policy.frequency = "daily"; policy.measure = "once"; policy.target = 1; context.insert(policy)
            let trip = Trip(); trip.city = "الخبر"; trip.tzID = activePlace.timeZoneID; trip.lat = 26.4207; trip.lon = 50.0888
            trip.start = today.date(in: activePlace.timeZone).addingTimeInterval(10 * 3600)
            trip.end = today.date(in: activePlace.timeZone).addingTimeInterval(12 * 3600)
            trip.createdAt = prayerNow(); trip.updatedAt = prayerNow(); context.insert(trip)
            try context.save(); return
        }
        if variant == "pastZeroTarget" {
            let today = GregorianDay.containing(prayerNow(), in: activePlace.timeZone)
            let start = today.adding(days: -7)
            let habit = Habit(); habit.name = "مشي يومي"; habit.startDate = start.date(in: activePlace.timeZone); context.insert(habit)
            let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = start.description
            policy.frequency = "daily"; policy.measure = "once"; policy.target = 1; policy.restWeekdays = ["wed"]
            context.insert(policy); try context.save(); return
        }
        if variant == "pausedLater" || variant == "pausedLaterMixed" {
            let today = GregorianDay.containing(prayerNow(), in: activePlace.timeZone)
            for (index, frequency) in ["daily", "weekly", "monthly"].enumerated() {
                if index == 2 && variant != "pausedLaterMixed" { continue }
                let habit = Habit(); habit.name = ["الماء", "صلة الأرحام", "صدقة الشهر"][index]
                habit.startDate = today.adding(days: -20).date(in: activePlace.timeZone); context.insert(habit)
                let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = today.adding(days: -20).description
                policy.frequency = frequency; policy.measure = "once"; policy.target = 1; policy.monthCalendar = "gregorian"; context.insert(policy)
                if index == 1 {
                    let pause = HabitPause(); pause.habitID = habit.id; pause.fromDayKey = today.adding(days: -3).description; context.insert(pause)
                } else if index == 2 {
                    let event = HabitEvent(); event.habitID = habit.id; event.dayKey = today.adding(days: -1).description
                    event.periodKey = String(format: "g:%04d-%02d", today.year, today.month); event.delta = 1; context.insert(event)
                }
            }
            try context.save(); return
        }
        if variant == "scheduledToday" || variant == "scheduledEarly" || variant == "scheduledRisk" {
            let today = GregorianDay.containing(prayerNow(), in: activePlace.timeZone)
            for (name, frequency) in [("صدقة شهرية محددة", "monthly"), ("موعد سنوي محدد", "yearly"), ("هدف شهري مرن", "monthly")] {
                let historyStart = variant == "scheduledRisk" ? today.adding(days: frequency == "monthly" ? -100 : -730) : today.adding(days: -35)
                let habit = Habit(); habit.name = name; habit.startDate = historyStart.date(in: ActivePlace.riyadh.timeZone); context.insert(habit)
                let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = historyStart.description
                policy.frequency = frequency; policy.measure = "once"; policy.target = 1; policy.monthCalendar = "gregorian"
                if name == "صدقة شهرية محددة" { policy.monthDays = [variant == "scheduledEarly" || variant == "scheduledRisk" ? 31 : today.day] }
                else if frequency == "yearly" {
                    policy.yearMonth = variant == "scheduledEarly" || variant == "scheduledRisk" ? 12 : today.month
                    policy.yearDay = variant == "scheduledEarly" || variant == "scheduledRisk" ? 31 : today.day
                }
                context.insert(policy)
                if variant == "scheduledRisk", ["monthly", "yearly"].contains(frequency) {
                    let eventDay = frequency == "monthly" ? (try GregorianDay(year: 2026, month: 10, day: 31)) : (try GregorianDay(year: 2024, month: 12, day: 31))
                    let event = HabitEvent(); event.habitID = habit.id; event.dayKey = eventDay.description
                    event.periodKey = frequency == "monthly" ? "g:2026-10" : "g:2024"
                    event.delta = 1; event.eventAt = eventDay.date(in: ActivePlace.riyadh.timeZone).addingTimeInterval(43200)
                    event.tzID = "Asia/Riyadh"; event.dayPolicy = "midnight@1"; context.insert(event)
                }
            }
            try context.save(); return
        }
        let comingWidget = variant == "widgetComing"
        let atRisk = variant == "atRisk", overdue = variant == "sinceOverdue"
        let since = variant == "since" || overdue
        let lobbySix = variant == "lobbySix"
        guard variant == "showcase" || atRisk || since || lobbySix || comingWidget else{try context.save();return}
        let today=GregorianDay.containing(prayerNow(),in:activePlace.timeZone)
        let names=comingWidget ? ["مشوار الأربعاء","ورد الشهر","مراجعة السنة"] : ["الماء","أذكار الصباح","مذاكرة","الاتصال بالأخوال","زيارة الوالدين","صدقة الشهر",since ? "إهداء من تحب" : "العمرة"]
        for (index,name) in names.enumerated(){
            let habit=Habit();habit.id=StableIdentity.uuid(for:"habit-fixture-\(index)");habit.name=name;habit.order=index;habit.startDate=today.adding(days:-20).date(in:ActivePlace.riyadh.timeZone);context.insert(habit)
            let p=HabitPolicy();p.habitID=habit.id;p.effectiveFrom=today.adding(days:-20).description
            if comingWidget { p.frequency=index == 0 ? "weekly" : index == 1 ? "monthly" : "yearly";p.measure="once";p.target=1;p.weekdays=index == 0 ? ["wed"] : [];p.monthDays=index == 1 ? [15] : [] }
            else { p.frequency=(lobbySix && index<6) || index<3 ? "daily" : index<5 ? "weekly" : index==5 ? "monthly" : "yearly";p.measure=index==0 ? "count" : "once";p.target=index==0 ? 8 : 1;p.unit=index==0 ? "كوب" : nil;p.minimum=index==0 ? 1 : nil }
            p.monthCalendar="gregorian";p.yearMonth=12;p.yearDay=15;context.insert(p)
            if since && index == 6 {
                // Item 26 «ج»: a yearly habit kept by «آخر مرة», two times long ago with that day's diary lines.
                p.effectiveFrom=today.adding(days:-700).description
                let latestOffset = overdue ? 400 : 240
                for (offset,line) in [(latestOffset,"أهديت أمي عطرها الذي تحبه، وفرحت به كثيرًا."),(600,"اشتريت لأبي كتابًا كان يبحث عنه.")] {
                    let d=today.adding(days:-offset),entry=Entry();entry.id=StableIdentity.uuid(for:"habit-since-entry-\(offset)");entry.dayKey=d.description;entry.text=line;entry.eventAt=d.date(in:ActivePlace.riyadh.timeZone).addingTimeInterval(64800);entry.createdAt=entry.eventAt;entry.tzID="Asia/Riyadh";entry.dayPolicy="midnight@1";context.insert(entry)
                    let event=HabitEvent();event.habitID=habit.id;event.dayKey=d.description;event.periodKey=String(format:"g:%04d",d.year);event.delta=1;event.entryID=offset == latestOffset ? entry.id : nil;event.eventAt=entry.eventAt;event.tzID="Asia/Riyadh";event.dayPolicy="midnight@1";context.insert(event)
                }
                let quiet=Entry();quiet.dayKey=today.adding(days:-3).description;quiet.text="مشيت مع أخي بعد العصر.";quiet.eventAt=today.adding(days:-3).date(in:ActivePlace.riyadh.timeZone).addingTimeInterval(57600);quiet.tzID="Asia/Riyadh";quiet.dayPolicy="midnight@1";context.insert(quiet)
                continue
            }
            if comingWidget {
                let done=today.adding(days:index == 0 ? -3 : -2)
                let periodKey=p.frequency == "weekly" ? MadarYear.week(done,start:.saturday).start.description : p.frequency == "monthly" ? String(format:"g:%04d-%02d",done.year,done.month) : String(format:"g:%04d",done.year)
                let event=HabitEvent();event.habitID=habit.id;event.dayKey=done.description;event.periodKey=periodKey;event.delta=1;event.eventAt=done.date(in:ActivePlace.riyadh.timeZone).addingTimeInterval(43200);event.tzID="Asia/Riyadh";event.dayPolicy="midnight@1";context.insert(event)
                continue
            }
            for offset in 1...18 where (offset+index)%5 != 0 && !(atRisk && index == 0 && offset == 1) {
                let event=HabitEvent();event.habitID=habit.id;event.dayKey=today.adding(days:-offset).description;let d=today.adding(days:-offset);event.periodKey=(lobbySix && index<6) || index<3 ? d.description : index<5 ? MadarYear.week(d,start:.saturday).start.description : index==5 ? String(format:"g:%04d-%02d",d.year,d.month) : String(format:"g:%04d",d.year);event.delta=index==0 ? 8 : 1;event.eventAt=today.adding(days:-offset).date(in:ActivePlace.riyadh.timeZone).addingTimeInterval(43200);event.tzID="Asia/Riyadh";event.dayPolicy="midnight@1";context.insert(event)
            }
        }
        try context.save()
    }
}
#endif
