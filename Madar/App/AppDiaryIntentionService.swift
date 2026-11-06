import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

struct DiaryIntention:Identifiable {let id:UUID;let text:String;let result:String?}
/// OR-15: where today stands between Fajr and Isha, so the morning and evening pages share one arc.
struct DiaryDayArc:Equatable {let progress:Double;let marks:[Double];let night:Bool}
extension AppDiaryService {
    func intentions(_ day:GregorianDay) throws -> [DiaryIntention] {
        try authorizeRead();let key=day.description
        return try ModelContext(app.container).fetch(FetchDescriptor<Niyya>(predicate:#Predicate{$0.dayKey==key && $0.deletedAt==nil && $0.mergedInto==nil},sortBy:[SortDescriptor(\.order),SortDescriptor(\.createdAt)])).map{.init(id:$0.id,text:$0.text,result:$0.result)}
    }
    func intentionEvening(_ day:GregorianDay) -> Bool {
        let now=clock()
        guard let repository=try? PrayerRepository(context:ModelContext(app.container)) else{return false}
        let place=repository.place(at:now),options=repository.calculationOptions(at:now)
        guard let prayers=PrayerTimesEngine.calculate(day:day,place:place,options:options) else{return false}
        return now>=prayers.isha
    }
    func dayArc(_ day:GregorianDay) -> DiaryDayArc? {
        let now=clock()
        guard let repository=try? PrayerRepository(context:ModelContext(app.container)) else{return nil}
        let place=repository.place(at:now),options=repository.calculationOptions(at:now)
        guard let p=PrayerTimesEngine.calculate(day:day,place:place,options:options) else{return nil}
        let span=p.isha.timeIntervalSince(p.fajr);guard span>0 else{return nil}
        let at:(Date)->Double={min(1,max(0,$0.timeIntervalSince(p.fajr)/span))}
        return .init(progress:at(now),marks:[0,at(p.dhuhr),at(p.asr),at(p.maghrib),1],night:now>=p.maghrib || now<p.fajr)
    }
    func saveIntention(_ text:String,id:UUID=UUID(),day:GregorianDay) async throws {
        try await app.executeDiaryCommand("diary.setIntention",payload:["id":.string(id.uuidString),"dayKey":.string(day.description),"text":.string(text)])
    }
    func deleteIntention(_ id:UUID) async throws {
        try await app.executeDiaryCommand("diary.deleteIntention",payload:["id":.string(id.uuidString)])
    }
    func setIntentionResult(_ id:UUID,result:String?) async throws {
        try await app.executeDiaryCommand("diary.setIntentionResult",payload:["id":.string(id.uuidString),"result":result.map{.string($0)} ?? .null])
    }
}
