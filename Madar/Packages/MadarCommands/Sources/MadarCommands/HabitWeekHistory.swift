import Foundation
import SwiftData
import MadarCore
import MadarData

/// B02: a week-start setting change is an epoch, including a later undo; it never regroups an older week.
@MainActor enum HabitWeekHistory {
    struct Change:Codable {let day:String;let start:String}
    struct History:Codable {let initial:String;var changes:[Change]}
    static let key="sys.habitWeekHistory"
    static func load(_ context:ModelContext) throws -> History? {
        guard let row=try context.fetch(FetchDescriptor<DeviceSetting>()).first(where:{$0.key==key && $0.deletedAt==nil && $0.mergedInto==nil})else{return nil}
        return try JSONDecoder().decode(History.self,from:row.valueJSON)
    }
    static func record(_ values:[String:MadarData.JSONValue],store:SettingsStore,context:ModelContext,now:Date,writer:String) throws {
        guard let new=values["core.weekStart"]?.string else{return}
        let old=try store.value(for:"core.weekStart").string ?? "saturday"
        guard old != new else{return}
        let today=try DiaryLineRenderer.today(context:context,now:now).description
        let existing=try context.fetch(FetchDescriptor<DeviceSetting>()).first{$0.key==key && $0.deletedAt==nil && $0.mergedInto==nil}
        var history=try load(context) ?? History(initial:old,changes:[])
        history.changes.removeAll{$0.day==today};history.changes.append(.init(day:today,start:new))
        let row=existing ?? DeviceSetting();row.key=key;row.valueJSON=try JSONEncoder().encode(history);row.writerID=writer;row.updatedAt=StableIdentity.monotonic(now:now,previous:row.updatedAt)
        if existing==nil{row.createdAt=now;context.insert(row)}
    }
}
