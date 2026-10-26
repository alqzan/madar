import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

struct DiaryIntention:Identifiable {let id:UUID;let text:String;let result:String?}
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
    func saveIntention(_ text:String,id:UUID=UUID(),day:GregorianDay) async throws {
        try await app.executeDiaryCommand("diary.setIntention",payload:["id":.string(id.uuidString),"dayKey":.string(day.description),"text":.string(text)])
    }
    func setIntentionResult(_ id:UUID,result:String?) async throws {
        try await app.executeDiaryCommand("diary.setIntentionResult",payload:["id":.string(id.uuidString),"result":result.map{.string($0)} ?? .null])
    }
}
