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
    /// What each unit reads: quantities by cumulative sum; sleep and workouts are samples (owner, 17 Nov 2026, idea 14).
    private static func readTypes(_ unit:String) -> Set<HKObjectType> {
        switch unit {
        case "sleepMinutes": [HKCategoryType(.sleepAnalysis)]
        case "workouts": [HKObjectType.workoutType()]
        default: [HKQuantityType(unit == "steps" ? .stepCount : .appleExerciseTime)]
        }
    }
    static func authorize(unit:String) async throws {
        guard available else{return}
        try await store.requestAuthorization(toShare:[],read:readTypes(unit))
    }
    static func sum(unit:String,from:Date,to:Date) async throws -> Int? {
        if unit == "sleepMinutes" || unit == "workouts" { return try await sampleTotal(unit:unit,from:from,to:to) }
        let type=HKQuantityType(unit == "steps" ? .stepCount : .appleExerciseTime)
        let hkUnit=unit == "steps" ? HKUnit.count() : HKUnit.minute()
        return try await withCheckedThrowingContinuation { continuation in
            let query=HKStatisticsQuery(quantityType:type,quantitySamplePredicate:HKQuery.predicateForSamples(withStart:from,end:to,options:.strictStartDate),options:.cumulativeSum) { _,statistics,error in
                if let error {continuation.resume(throwing:error)}else{continuation.resume(returning:statistics?.sumQuantity().map{max(0,Int($0.doubleValue(for:hkUnit).rounded(.down)))})}
            }
            store.execute(query)
        }
    }
    /// Sleep is the asleep time that ENDED inside the Madar day (last night, counted on the morning it ended); workouts are those that started in it.
    private static func sampleTotal(unit:String,from:Date,to:Date) async throws -> Int? {
        let sleep = unit == "sleepMinutes"
        let type:HKSampleType = sleep ? HKCategoryType(.sleepAnalysis) : HKObjectType.workoutType()
        return try await withCheckedThrowingContinuation { continuation in
            let query=HKSampleQuery(sampleType:type,predicate:HKQuery.predicateForSamples(withStart:from,end:to,options:sleep ? [] : .strictStartDate),limit:HKObjectQueryNoLimit,sortDescriptors:nil) { _,samples,error in
                if let error {continuation.resume(throwing:error);return}
                guard let samples else {continuation.resume(returning:nil);return}
                if !sleep {continuation.resume(returning:samples.count);return}
                let asleep:Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,HKCategoryValueSleepAnalysis.asleepCore.rawValue,HKCategoryValueSleepAnalysis.asleepDeep.rawValue,HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                // A Watch, the iPhone and other apps write overlapping stages: merge the intervals before adding them up.
                let spans=samples.compactMap{$0 as? HKCategorySample}.filter{asleep.contains($0.value) && $0.endDate >= from && $0.endDate < to}.map{($0.startDate,$0.endDate)}.sorted{$0.0 < $1.0}
                var seconds=0.0,open:(Date,Date)?
                for span in spans {
                    if let current=open,span.0 <= current.1 { open=(current.0,max(current.1,span.1)) }
                    else { if let current=open { seconds+=current.1.timeIntervalSince(current.0) }; open=span }
                }
                if let current=open { seconds+=current.1.timeIntervalSince(current.0) }
                continuation.resume(returning:Int(seconds/60))
            }
            store.execute(query)
        }
    }
    /// The closed days last written per habit and unit in this launch (a cache, never a record).
    @MainActor private static var writtenClosedDays:[String:[String:MadarCore.JSONValue]]=[:]
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
                guard let policy=policies.last(where:{$0.habitID==habit.id && $0.effectiveFrom<=day.description}),let unit=policy.unit,HabitRule.healthUnits.contains(unit) else{continue}
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
                // FB-32 (owner: no freezes): opening the room re-reads Health; an unchanged week is not written again,
                // so it does not reload the store and reschedule reminders on every visit.
                let key="\(habit.id):\(unit)"
                guard writtenClosedDays[key] != values else { continue }
                try await session.executeDiaryCommand("habit.refreshHealth",payload:["id":.string(habit.id.uuidString),"unit":.string(unit),"values":.object(values)])
                writtenClosedDays[key]=values
            }
        }
        return live
    }
}
