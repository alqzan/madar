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
        let settings=try SettingsStore(context:context);_ = try settings.stage(["core.dayStart":.string("midnight"),"core.faceIDLock":.string("none")])
        let marker=DeviceSetting();marker.key="sys.onboardingCompleted";marker.valueJSON=Data("true".utf8);context.insert(marker)
        let atRisk = variant == "atRisk"
        guard variant == "showcase" || atRisk else{try context.save();return}
        let today=GregorianDay.containing(prayerNow(),in:activePlace.timeZone)
        let names=["الماء","أذكار الصباح","مذاكرة","الاتصال بالأخوال","زيارة الوالدين","صدقة الشهر","العمرة"]
        for (index,name) in names.enumerated(){
            let habit=Habit();habit.id=StableIdentity.uuid(for:"habit-fixture-\(index)");habit.name=name;habit.order=index;habit.startDate=today.adding(days:-20).date(in:ActivePlace.riyadh.timeZone);context.insert(habit)
            let p=HabitPolicy();p.habitID=habit.id;p.effectiveFrom=today.adding(days:-20).description;p.frequency=index<3 ? "daily" : index<5 ? "weekly" : index==5 ? "monthly" : "yearly";p.measure=index==0 ? "count" : "once";p.target=index==0 ? 8 : 1;p.unit=index==0 ? "كوب" : nil;p.minimum=index==0 ? 1 : nil;p.monthCalendar="gregorian";p.yearMonth=12;p.yearDay=15;context.insert(p)
            for offset in 1...18 where (offset+index)%5 != 0 && !(atRisk && index == 0 && offset == 1) {
                let event=HabitEvent();event.habitID=habit.id;event.dayKey=today.adding(days:-offset).description;let d=today.adding(days:-offset);event.periodKey=index<3 ? d.description : index<5 ? MadarYear.week(d,start:.saturday).start.description : index==5 ? String(format:"g:%04d-%02d",d.year,d.month) : String(format:"g:%04d",d.year);event.delta=index==0 ? 8 : 1;event.eventAt=today.adding(days:-offset).date(in:ActivePlace.riyadh.timeZone).addingTimeInterval(43200);event.tzID="Asia/Riyadh";event.dayPolicy="midnight@1";context.insert(event)
            }
        }
        try context.save()
    }
}
#endif
