import Foundation
import SwiftData
import MadarCore
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

private struct QuranSessionLogProjectionConfiguration: Sendable {
    let timeZone: TimeZone
    let firstCalendar: FirstCalendar
    let hijriSource: HijriSource
    let sightingOffset: Int
    let numerals: MadarNumberFormatter
}

private enum QuranSessionLogProjection {
    static func project(snapshot: QuranDataSnapshot, catalog: QuranResourceCatalog,
                        events: [MistakeEvent], configuration: QuranSessionLogProjectionConfiguration) throws -> QuranUISessionLog {
        try Task.checkCancellation()
        let today = snapshot.day.date, yesterday = today.adding(days: -1)
        let sessionIDs = Set(snapshot.sessions.map(\.id))
        let mistakesBySession = events.reduce(into: [UUID: [MistakeEvent]]()) { grouped, event in
            guard let sessionID = event.sessionID, sessionIDs.contains(sessionID), ["mistake", "drillFail"].contains(event.kind) else { return }
            grouped[sessionID, default: []].append(event)
        }
        let records = snapshot.sessions.reversed().map { row in
            let title = switch row.kind { case .hifz: "حفظ"; case .review: "مراجعة"; case .free: "مراجعة حرة"; case .qiyam: "ورد القيام"; case .drill: "مواضع الخطأ" }
            let mistakes = (mistakesBySession[row.id] ?? []).sorted { $0.at < $1.at }.map { event in
                let ayah = catalog.ayah(id: event.ayahId)
                let location = ayah.map { "سورة " + $0.surahNameArabic + "، الآية " + configuration.numerals.string($0.ayahNumber) } ?? "موضع قرآني محفوظ"
                let word = event.wordIndex.flatMap { index in ayah?.wordTokens.first(where: { $0.wordIndex == index })?.text }
                let detail = word.map { location + "، كلمة «" + $0 + "»" } ?? location
                return QuranUILogMistake(id: event.id, title: event.kind == "drillFail" ? "لم يثبت" : "موضع تعثّر", detail: detail)
            }
            let date = DualDate(instant: row.dayKey.date(in: configuration.timeZone).addingTimeInterval(43_200),
                timeZone: configuration.timeZone, source: configuration.hijriSource, sightingOffset: configuration.sightingOffset)
                .labels(firstCalendar: configuration.firstCalendar, numerals: configuration.numerals.style).combined
            return QuranUILogRecord(id: row.id, day: date, relative: row.dayKey == today ? "اليوم" : row.dayKey == yesterday ? "أمس" : nil,
                title: title + "، " + faceCount(row.pages.count, numerals: configuration.numerals),
                detail: portionTitle(row.ayahs, catalog: catalog, numerals: configuration.numerals),
                kind: QuranUIKind(rawValue: row.kind.rawValue) ?? .free,
                grades: row.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + configuration.numerals.string($0.page),
                    grade: QuranUIGrade(rawValue: $0.rating.storedRaw) ?? .good, explanation: "تقييمك") },
                warning: row.kind == .hifz && row.grades.contains { $0.rating == .needsMastery } ? "يحتاج هذا الورد تثبيتًا؛ يتغيّر مسار الحفظ التالي بحسب تقييمك" : nil,
                mistakes: mistakes)
        }
        let frontier = try snapshot.coverage.frontier(from: snapshot.plan?.plan.startAyah ?? 1)
        let gap = frontier.flatMap { first in
            snapshot.coverage.coveredAyahs.contains(where: { $0 > first })
                ? "في حفظك فجوة تبدأ من " + (catalog.ayah(id: first)?.surahNameArabic ?? "") + "؛ تُقدَّم في الورد القادم"
                : nil
        }
        return QuranUISessionLog(records: records, coverage: coverageTitle(snapshot.coverage, numerals: configuration.numerals),
            fraction: Double(snapshot.coverage.completedPages.count) / 604,
            nextDue: snapshot.pages.reduce(into: [:]) { $0[$1.page] = displayDate($1.nextDue, configuration: configuration) }, gap: gap)
    }

    private static func displayDate(_ day: GregorianDay, configuration: QuranSessionLogProjectionConfiguration) -> String {
        DualDate(instant: day.date(in: configuration.timeZone).addingTimeInterval(43_200), timeZone: configuration.timeZone,
            source: configuration.hijriSource, sightingOffset: configuration.sightingOffset)
            .labels(firstCalendar: configuration.firstCalendar, numerals: configuration.numerals.style).combined
    }

    private static func count(_ value: Int, singular: String, dual: String, plural: String, numerals: MadarNumberFormatter) -> String {
        switch value {
        case 1: return singular
        case 2: return dual
        default:
            let counted = value != 0 && !(3...10).contains(value % 100)
                ? ["أجزاء": "جزءًا", "أوجه": "وجهًا", "أيام": "يومًا", "آيات": "آيةً", "مواضع": "موضعًا", "مرات": "مرةً"][plural] ?? plural
                : plural
            return "\(numerals.string(value)) \(counted)"
        }
    }

    private static func faceCount(_ value: Int, numerals: MadarNumberFormatter) -> String {
        count(value, singular: "وجه واحد", dual: "وجهان", plural: "أوجه", numerals: numerals)
    }

    private static func coverageTitle(_ coverage: QuranCoverage, numerals: MadarNumberFormatter) -> String {
        let completed = coverage.completedPages.count, juz = coverage.completedJuz.count, outside = coverage.pagesOutsideCompletedJuz.count
        return completed == 0 ? "أول الطريق" : (juz == 0 ? faceCount(outside, numerals: numerals)
            : count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء", numerals: numerals)
                + (outside > 0 ? " و" + faceCount(outside, numerals: numerals) : ""))
    }

    private static func portionTitle(_ portion: QuranAyahRange, catalog: QuranResourceCatalog,
                                     numerals: MadarNumberFormatter) -> String {
        guard let first = catalog.ayah(id: portion.first), let last = catalog.ayah(id: portion.last) else { return "" }
        return first.surahNameArabic + " " + numerals.string(first.ayahNumber) + "–"
            + (first.surahID == last.surahID ? "" : last.surahNameArabic + " ") + numerals.string(last.ayahNumber)
    }
}

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
            return QuranUILogRecord(id: row.id, day: displayDate(row.dayKey), relative: row.dayKey == today ? "اليوم" : row.dayKey == yesterday ? "أمس" : nil, title: title + "، " + faceCount(row.pages.count), detail: portionTitle(row.ayahs, catalog: catalog), kind: (QuranUIKind(rawValue: row.kind.rawValue) ?? .free),
                grades: row.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: (QuranUIGrade(rawValue: $0.rating.storedRaw) ?? .good), explanation: "تقييمك") },
                warning: row.kind == .hifz && row.grades.contains { $0.rating == .needsMastery } ? "يحتاج هذا الورد تثبيتًا؛ يتغيّر مسار الحفظ التالي بحسب تقييمك" : nil,
                mistakes: mistakes)
        }
        let frontier = try v.coverage.frontier(from: v.plan?.plan.startAyah ?? 1)
        let gap = frontier.flatMap { first in v.coverage.coveredAyahs.contains(where: { $0 > first }) ? "في حفظك فجوة تبدأ من " + (catalog.ayah(id: first)?.surahNameArabic ?? "") + "؛ تُقدَّم في الورد القادم" : nil }
        return QuranUISessionLog(records: records, coverage: coverageTitle(v.coverage), fraction: Double(v.coverage.completedPages.count) / 604,
            nextDue: v.pages.reduce(into: [:]) { $0[$1.page] = displayDate($1.nextDue) }, gap: gap)
    }
    func sessionLogOffMain(at instant: Date? = nil) async throws -> QuranUISessionLog {
        let app = app, evaluatedAt = instant ?? clock()
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        let container = app.container, generation = app.storeGeneration, revision = app.prayerRevision
        let configuration = QuranSessionLogProjectionConfiguration(timeZone: app.activePlace.timeZone,
            firstCalendar: FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri,
            hijriSource: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura,
            sightingOffset: Int(app.number("core.hijriOffset")), numerals: numerals)
        let (snapshots, catalog, _) = try await snapshotsOffMain(at: evaluatedAt, hifzLevels: [nil])
        guard let snapshot = snapshots.first else { throw DataError.invalidValue("Quran history snapshot") }
        let readTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<MistakeEvent>(predicate: #Predicate {
                $0.deletedAt == nil && $0.mergedInto == nil && $0.sessionID != nil
            }))
            try Task.checkCancellation()
            let result = try QuranSessionLogProjection.project(snapshot: snapshot, catalog: catalog,
                events: events, configuration: configuration)
            try Task.checkCancellation()
            return result
        }
        let result = try await withTaskCancellationHandler { try await readTask.value } onCancel: { readTask.cancel() }
        try Task.checkCancellation()
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.prayerRevision == revision, app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        return result
    }
    /// The same «في صدرك» phrase as the room's home: whole parts first, then the faces outside them.
    func coverageTitle(_ coverage: QuranCoverage) -> String {
        let completed = coverage.completedPages.count, juz = coverage.completedJuz.count, outside = coverage.pagesOutsideCompletedJuz.count
        return completed == 0 ? "أول الطريق" : (juz == 0 ? faceCount(outside) : count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء") + (outside > 0 ? " و" + faceCount(outside) : ""))
    }
}
