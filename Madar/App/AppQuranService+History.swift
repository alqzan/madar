import Foundation
import SwiftData
import MadarQuran
import MadarCommands
import MadarData

struct QuranUILogMistake: Identifiable, Sendable {
    let id: UUID
    let title: String
    let detail: String
}
struct QuranUILogRecord: Identifiable, Sendable {
    var id: UUID; var day: String; var relative: String? = nil; var title: String; var detail: String; var kind: QuranUIKind
    var grades: [QuranUIPageGrade]; var warning: String?; var mistakes: [QuranUILogMistake] = []
}
struct QuranUISessionLog: Sendable { var records: [QuranUILogRecord]; var coverage: String; var fraction: Double; var nextDue: [Int: String]; var gap: String? }
extension AppQuranService {
    func sessionLog() throws -> QuranUISessionLog {
        let v = try snapshot(), catalog = try QuranResources.catalog()
        let today = v.day.date, yesterday = today.adding(days: -1)
        let sessionIDs = Set(v.sessions.map(\.id))
        let events = try ModelContext(app.container).fetch(FetchDescriptor<MistakeEvent>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.sessionID != nil }))
        let mistakesBySession = events.reduce(into: [UUID: [MistakeEvent]]()) { grouped, event in
            guard let sessionID = event.sessionID, sessionIDs.contains(sessionID), ["mistake", "drillFail"].contains(event.kind) else { return }
            grouped[sessionID, default: []].append(event)
        }
        let records = v.sessions.reversed().map { row in
            let title = switch row.kind { case .hifz: "حفظ"; case .review: "مراجعة"; case .free: "مراجعة حرة"; case .qiyam: "ورد القيام"; case .drill: "مواضع الخطأ" }
            let mistakes = (mistakesBySession[row.id] ?? []).sorted { $0.at < $1.at }.map { event in
                let ayah = catalog.ayah(id: event.ayahId)
                let location = ayah.map { "سورة " + $0.surahNameArabic + "، الآية " + numerals.string($0.ayahNumber) } ?? "موضع قرآني محفوظ"
                let word = event.wordIndex.flatMap { index in ayah?.wordTokens.first(where: { $0.wordIndex == index })?.text }
                let detail = word.map { location + "، كلمة «" + $0 + "»" } ?? location
                return QuranUILogMistake(id: event.id, title: event.kind == "drillFail" ? "لم يثبت" : "موضع تعثّر", detail: detail)
            }
            return QuranUILogRecord(id: row.id, day: displayDate(row.dayKey), relative: row.dayKey == today ? "اليوم" : row.dayKey == yesterday ? "أمس" : nil, title: title + "، " + faceCount(row.pages.count), detail: portionTitle(row.ayahs, catalog: catalog), kind: QuranUIKind(rawValue: row.kind.rawValue)!,
                grades: row.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "تقييمك") },
                warning: row.kind == .hifz && row.grades.contains { $0.rating == .needsMastery } ? "يحتاج هذا الورد تثبيتًا؛ يتغيّر مسار الحفظ التالي بحسب تقييمك" : nil,
                mistakes: mistakes)
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
