import Foundation
import MadarQuran
import MadarCommands

extension AppQuranService {
    func index(_ unit: QuranUIIndexUnit) async throws -> [QuranUIIndexItem] {
        let v=try snapshot(),catalog=try QuranResources.catalog()
        let reviewed=Set(v.sessions.filter { [.review,.free,.qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) })
        let due=Set(v.pages.filter(\.isDue).map(\.page))
        var today=Set(v.review.allPages + v.partialRecent.map(\.page))
        if let portion=v.hifz?.portion {today.formUnion(try QuranPortionEngine.pages(for:portion,catalog:catalog).map(\.page))}
        let groups: [(String,String,[QuranAyahResourceRecord])]
        switch unit {
        case .surah: groups=Dictionary(grouping:catalog.ayahs,by:\.surahID).sorted { $0.key < $1.key }.map { (String($0.key),$0.value[0].surahNameArabic,$0.value) }
        case .ayah: groups=catalog.ayahs.map { (String($0.id),$0.surahNameArabic + " " + numerals.string($0.ayahNumber),[$0]) }
        case .juz: groups=Dictionary(grouping:catalog.ayahs,by:\.juz).sorted { $0.key < $1.key }.map { (String($0.key),"الجزء " + numerals.string($0.key),$0.value) }
        case .hizb: groups=try catalog.hizbSegments().map { s in (String(s.number),"الحزب " + numerals.string(s.number),Array(catalog.ayahs[(s.ayahs.first-1)..<s.ayahs.last])) }
        case .page: groups=(1...604).map { (String($0),"الوجه " + numerals.string($0),catalog.ayahs(on:$0)) }
        }
        return groups.map { id,title,ayahs in
            let ids=Set(ayahs.map(\.id)),pages=Set(ayahs.map(\.page)),covered=ids.intersection(v.coverage.coveredAyahs)
            let subtitle = unit == .ayah ? ayahs[0].uthmaniText : "التغطية " + numerals.string(covered.count) + "/" + numerals.string(ids.count) + "، الأوجه " + numerals.string(pages.min()!) + "–" + numerals.string(pages.max()!)
            return QuranUIIndexItem(id:id,title:title,subtitle:subtitle,firstPage:pages.min()!,fraction:Double(covered.count)/Double(ids.count),memorized:ids.isSubset(of:v.coverage.coveredAyahs),reviewed:!covered.isEmpty && !pages.isDisjoint(with:reviewed),due:!covered.isEmpty && !pages.isDisjoint(with:due),isToday:!pages.isDisjoint(with:today),weight:ids.count)
        }
    }
}
