import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

/// The context is immutable policy provenance, carried by the same append-only habit ledger.
/// Zero deltas never complete anything. Keeping it in synced facts also keeps it through export/restore.
@MainActor enum HabitContextProvenance {
    struct Value { let source:String;let offset:Int;let week:String }
    static func current(_ store:SettingsStore) throws->Value {
        .init(source:try store.value(for:"core.hijriSource").string ?? "ummAlQura",offset:Int(try store.value(for:"core.hijriOffset").number ?? 0),week:try store.value(for:"core.weekStart").string ?? "saturday")
    }
    @discardableResult static func ensureOrigin(habit:Habit,context:ModelContext,now:Date,writer:String) throws->HabitEvent? {
        guard habit.linkedSource == nil || habit.linkedSource == "walking" else{return nil}
        guard try context.fetch(FetchDescriptor<HabitEvent>()).contains(where:{$0.habitID==habit.id && $0.deletedAt==nil && $0.mergedInto==nil && $0.calendarSource != nil}) == false else{return nil}
        let policies=try context.fetch(FetchDescriptor<HabitPolicy>()).filter{$0.habitID==habit.id && $0.deletedAt==nil && $0.mergedInto==nil}
        guard let day=policies.map(\.effectiveFrom).min() else{return nil}
        let value=try current(SettingsStore(context:context))
        return append(habit:habit.id,day:day,value:value,context:context,now:now,writer:writer)
    }
    @discardableResult private static func append(habit:UUID,day:String,value:Value,context:ModelContext,now:Date,writer:String)->HabitEvent {
        let row=HabitEvent();row.habitID=habit;row.dayKey=day;row.delta=0;row.calendarSource=value.source;row.calendarOffset=value.offset;row.weekStart=value.week
        row.eventAt=now;row.tzID=(try? PrayerRepository(context:context).place(at:now).timeZoneID) ?? "UTC";row.dayPolicy=((try? SettingsStore(context:context).value(for:"core.dayStart").string) ?? "fajr")+"@1";row.createdAt=now;row.updatedAt=now;row.writerID=writer;context.insert(row);return row
    }
    static func recordSettingChange(_ values:[String:MadarData.JSONValue],store:SettingsStore,context:ModelContext,now:Date,writer:String) throws {
        guard !Set(values.keys).isDisjoint(with:["core.weekStart","core.hijriSource","core.hijriOffset"])else{return}
        let old=try current(store),new=Value(source:values["core.hijriSource"]?.string ?? old.source,offset:values["core.hijriOffset"]?.number.map(Int.init) ?? old.offset,week:values["core.weekStart"]?.string ?? old.week)
        guard new.source != old.source || new.offset != old.offset || new.week != old.week else{return}
        let day=try DiaryLineRenderer.today(context:context,now:now).description
        for habit in try context.fetch(FetchDescriptor<Habit>()) where habit.deletedAt==nil && habit.mergedInto==nil && (habit.linkedSource==nil || habit.linkedSource=="walking") {
            try ensureOrigin(habit:habit,context:context,now:now,writer:writer)
            let latest=try context.fetch(FetchDescriptor<HabitEvent>()).filter{$0.habitID==habit.id && $0.calendarSource != nil}.map(\.updatedAt).max() ?? .distantPast
            append(habit:habit.id,day:day,value:new,context:context,now:StableIdentity.monotonic(now:now,previous:latest),writer:writer)
        }
    }
}
