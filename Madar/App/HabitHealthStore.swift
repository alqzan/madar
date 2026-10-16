import Foundation
import HealthKit
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer

/// HealthKit is read-only. Closed-day totals use HabitLog (the explicit walking exception in §7.1).
/// Today's live value stays in memory; missing/denied quantities never erase a saved total.
@MainActor enum HabitHealthStore {
    static let store=HKHealthStore()
    static var available:Bool { HKHealthStore.isHealthDataAvailable() }
    static func authorize(unit:String) async throws {
        guard available else{return}
        try await store.requestAuthorization(toShare:[],read:[HKQuantityType(unit == "steps" ? .stepCount : .appleExerciseTime)])
    }
    static func sum(unit:String,from:Date,to:Date) async throws -> Int? {
        let type=HKQuantityType(unit == "steps" ? .stepCount : .appleExerciseTime)
        let hkUnit=unit == "steps" ? HKUnit.count() : HKUnit.minute()
        return try await withCheckedThrowingContinuation { continuation in
            let query=HKStatisticsQuery(quantityType:type,quantitySamplePredicate:HKQuery.predicateForSamples(withStart:from,end:to,options:.strictStartDate),options:.cumulativeSum) { _,statistics,error in
                if let error {continuation.resume(throwing:error)}else{continuation.resume(returning:statistics?.sumQuantity().map{max(0,Int($0.doubleValue(for:hkUnit).rounded(.down)))})}
            }
            store.execute(query)
        }
    }
    static func refresh(session:AppSession,closedDays:Bool=true) async throws -> [UUID:Int] {
        guard available else{return[:]}
        let context=ModelContext(session.container),repo=try PrayerRepository(context:context),today=AppBahwService(session:session).today,now=session.prayerNow()
        let habits=try context.fetch(FetchDescriptor<Habit>()).filter{$0.deletedAt==nil && $0.mergedInto==nil && $0.archivedAt==nil && $0.linkedSource=="walking"}
        let policies=try context.fetch(FetchDescriptor<HabitPolicy>()).filter{$0.deletedAt==nil && $0.mergedInto==nil}.sorted{$0.effectiveFrom<$1.effectiveFrom}
        let boundary=DayBoundary(rawValue:session.string("core.dayStart")) ?? .fajr
        var live:[UUID:Int]=[:]
        for habit in habits {
            var closedByUnit:[String:[String:MadarCore.JSONValue]]=[:]
            for offset in 0...(closedDays ? 7 : 0) {
                let day=today.adding(days:-offset)
                guard let policy=policies.last(where:{$0.habitID==habit.id && $0.effectiveFrom<=day.description}),let unit=policy.unit,["steps","exerciseMinutes"].contains(unit) else{continue}
                let place=repo.place(at:day.date(in:repo.home.timeZone).addingTimeInterval(43200)),options=repo.activeTrip(at:day.date(in:repo.home.timeZone).addingTimeInterval(43200)) == nil ? repo.options : repo.tripOptions
                func start(_ d:GregorianDay)->Date? {
                    if boundary == .midnight{return d.date(in:place.timeZone)}
                    guard let prayers=PrayerTimesEngine.calculate(day:d,place:place,options:options)else{return nil}
                    return boundary == .fajr ? prayers.fajr : prayers.maghrib
                }
                guard let from=start(day),let end=start(day.adding(days:1)),from<min(end,now),let total=try await sum(unit:unit,from:from,to:min(end,now))else{continue}
                if offset==0{live[habit.id]=total}else{closedByUnit[unit,default:[:]][day.description] = .number(Double(total))}
            }
            for (unit,values) in closedByUnit {
                try await session.executeDiaryCommand("habit.refreshHealth",payload:["id":.string(habit.id.uuidString),"unit":.string(unit),"values":.object(values)])
            }
        }
        return live
    }
}
