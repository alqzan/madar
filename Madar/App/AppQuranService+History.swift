import Foundation
import MadarQuran
import MadarCommands

struct QuranUILogRecord: Identifiable, Sendable {
    var id: UUID; var day: String; var relative: String? = nil; var title: String; var detail: String; var kind: QuranUIKind
    var grades: [QuranUIPageGrade]; var warning: String?
}
struct QuranUISessionLog: Sendable { var records: [QuranUILogRecord]; var coverage: String; var fraction: Double; var nextDue: [Int: String]; var gap: String? }
extension AppQuranService {
    func sessionLog() throws -> QuranUISessionLog {
        let v = try snapshot(), catalog = try QuranResources.catalog()
        let today = v.day.date, yesterday = today.adding(days: -1)
        let records = v.sessions.reversed().map { row in
            let title = switch row.kind { case .hifz: "حفظ"; case .review: "مراجعة"; case .free: "مراجعة حرة"; case .qiyam: "ورد القيام"; case .drill: "مواضع الخطأ" }
            return QuranUILogRecord(id: row.id, day: displayDate(row.dayKey), relative: row.dayKey == today ? "اليوم" : row.dayKey == yesterday ? "أمس" : nil, title: title + "، " + faceCount(row.pages.count), detail: portionTitle(row.ayahs, catalog: catalog), kind: QuranUIKind(rawValue: row.kind.rawValue)!,
                grades: row.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "تقييمك") },
                warning: row.kind == .hifz && row.grades.contains { $0.rating == .needsMastery } ? "يحتاج هذا الورد تثبيتًا؛ يتغيّر مسار الحفظ التالي بحسب تقييمك" : nil)
        }
        let frontier = try v.coverage.frontier(from: v.plan?.plan.startAyah ?? 1)
        let gap = frontier.flatMap { first in v.coverage.coveredAyahs.contains(where: { $0 > first }) ? "في حفظك فجوة تبدأ من " + (catalog.ayah(id: first)?.surahNameArabic ?? "") + "؛ تُقدَّم في الورد القادم" : nil }
        return QuranUISessionLog(records: records, coverage: coverageTitle(v.coverage), fraction: Double(v.coverage.completedPages.count) / 604,
            nextDue: v.pages.reduce(into: [:]) { $0[$1.page] = displayDate($1.nextDue) }, gap: gap)
    }
    /// The same «في صدرك» phrase as the room's home: whole parts first, then the faces outside them.
    func coverageTitle(_ coverage: QuranCoverage) -> String {
        let completed = coverage.completedPages.count, juz = coverage.completedJuz.count, outside = coverage.pagesOutsideCompletedJuz.count
        return completed == 0 ? "أول الطريق" : (juz == 0 ? faceCount(outside) : count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء") + (outside > 0 ? " و" + faceCount(outside) : ""))
    }
}
