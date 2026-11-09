import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

struct DiaryIntention:Identifiable {let id:UUID;let text:String;let result:String?}
enum DiaryIntentionReviewPeriod: String, Equatable, Sendable {
    case weekly, monthly
    var days: Int { self == .weekly ? 7 : 30 }
    var title: String { self == .weekly ? "مضى أسبوع على نيّتك" : "مضى شهر على نيّتك" }
    var question: String { self == .weekly ? "ما الخطوة التي نجحت؟ وما الذي يحتاج إلى تبسيط؟" : "ما الذي تغيّر منذ كتبت هذه النيّة؟" }
}
struct DiaryIntentionFollowUp: Identifiable, Sendable {
    let id: UUID
    let intention: String
    let period: DiaryIntentionReviewPeriod
    let writtenDay: GregorianDay
    let dueDay: GregorianDay
}
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
    func setIntentionReview(_ id: UUID, period: DiaryIntentionReviewPeriod, text: String) async throws {
        try await app.executeDiaryCommand("diary.setIntentionReview", payload: ["id": .string(id.uuidString), "period": .string(period.rawValue), "text": .string(text)])
    }
    func dueIntentionFollowUpsOffMain() async throws -> [DiaryIntentionFollowUp] {
        try authorizeRead()
        let today = try await currentDayOffMain(), todayKey = today.description
        let container = app.container, revision = app.prayerRevision, generation = app.storeGeneration
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Niyya>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.dayKey < todayKey })
            let rows = try context.fetch(descriptor)
            var due: [DiaryIntentionFollowUp] = []
            for row in rows {
                try Task.checkCancellation()
                guard let written = try? GregorianDay(row.dayKey) else { continue }
                let period: DiaryIntentionReviewPeriod?
                if row.weeklyReview == nil { period = .weekly }
                else if row.monthlyReview == nil { period = .monthly }
                else { period = nil }
                guard let period else { continue }
                let dueDay = written.adding(days: period.days)
                if dueDay <= today { due.append(.init(id: row.id, intention: row.text, period: period, writtenDay: written, dueDay: dueDay)) }
            }
            return due.sorted { lhs, rhs in
                lhs.dueDay == rhs.dueDay ? lhs.id.uuidString < rhs.id.uuidString : lhs.dueDay < rhs.dueDay
            }
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard app.prayerRevision == revision, app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        try authorizeRead()
        return result
    }
}
