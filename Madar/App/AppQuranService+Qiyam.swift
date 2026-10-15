import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarQuran
import MadarPrayer

struct QuranUIQiyamRakah:Identifiable,Sendable {var id:Int;var page:Int?;var title:String;var status:String}
struct QuranUIQiyamBoard:Sendable {var assignments:[QuranUIQiyamRakah];var unavailable:String?;var night:String}
struct QuranUIQiyamSession:Sendable {var assignments:[QuranUIQiyamRakah];var current:Int;var completed:Int;var total:Int;var finished:Bool;var pastDay:Bool}
extension AppQuranService {
    func qiyamBoard(rakaat:Int) throws ->QuranUIQiyamBoard {
        let v=try snapshot(),catalog=try QuranResources.catalog(),repository=try repository()
        let night=try PrayerRepository(context:repository.context).defaultNight(at:clock())
        let row=try repository.context.fetch(FetchDescriptor<QiyamNight>()).filter {$0.nightKey == night.description && $0.mergedInto == nil}.max {$0.updatedAt < $1.updatedAt}
        let assignments=try QuranQiyamEngine.assignment(rakats:rakaat,pages:v.pages)
        let unavailable = v.pages.isEmpty ? "يظهر ورد القيام بعد حفظ وجه كامل" : row?.deletedAt != nil ? "أعد تسجيل الليلة صراحة من قسم الصلاة أولًا" : row?.quranSessionID != nil ? "سُجّل ورد هذه الليلة؛ تجده في سجل الجلسات" : nil
        return QuranUIQiyamBoard(assignments:qiyamRows(assignments.pageByRakah,catalog:catalog,pages:v.pages),unavailable:unavailable,night:displayDate(night))
    }
    func qiyamPages(_ draft:QuranSessionDraft,catalog:QuranResourceCatalog)->[Int] {
        var seen=Set<Int>()
        return draft.portions.flatMap { portion in catalog.ayahs.filter {portion.first <= $0.id && $0.id <= portion.last}.map(\.page) }.filter {seen.insert($0).inserted}
    }
    private func qiyamRows(_ assigned:[Int?],catalog:QuranResourceCatalog,pages:[QuranPlanningPage])->[QuranUIQiyamRakah] {
        assigned.enumerated().map { i,page in
            let title=page.map {n in (catalog.ayahs(on:n).first?.surahNameArabic ?? "") + "، " + numerals.string(n)} ?? "أعد ما شئت"
            let record=pages.first {$0.page == page}
            return QuranUIQiyamRakah(id:i,page:page,title:title,status:page == nil ? "لا يُكرّر تسجيل الوجه" : record?.isDue == true ? "مستحق" : "في صدرك")
        }
    }
    func qiyamSession(_ value:QuranDraftPayload,catalog:QuranResourceCatalog) throws ->QuranUIQiyamSession {
        let pages=qiyamPages(value.draft,catalog:catalog),total=value.rakats ?? 2
        let assigned=pages.prefix(total).map(Optional.some)+Array<Int?>(repeating:nil,count:max(0,total-pages.count))
        let count=min(total,value.qiyamRakahIndex ?? value.draft.grades.count)
        return QuranUIQiyamSession(assignments:qiyamRows(assigned,catalog:catalog,pages:try snapshot().pages),current:min(count,total-1),completed:count,total:total,finished:count == total,pastDay:value.draft.storedDay.date != (try snapshot().day.date))
    }
}
