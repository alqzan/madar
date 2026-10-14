import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer
import MadarQuran

extension AppQuranService {
    func savedDraft(_ id: UUID) throws -> QuranDraftPayload {
        let context = try repository().context
        guard let row = try context.fetch(FetchDescriptor<SessionDraft>()).first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("تعذّر العثور على المسودة") }
        return try JSONDecoder().decode(QuranDraftPayload.self, from: row.provisionalJSON)
    }
    func save(_ value: QuranDraftPayload) async throws {
        try await command("quran.saveDraft", ["draft": .string(JSONEncoder().encode(value).base64EncodedString())])
    }
    func start(kind: QuranUIKind, stepID: String?, range: QuranUIRange?, rakaat: Int?, spotID: String?) async throws -> QuranUISessionState {
        let snapshot = try snapshot(), catalog = try QuranResources.catalog()
        guard snapshot.drafts.isEmpty else { throw DataError.invalidValue("تابع المسودة الحالية أو تجاهلها أولًا") }
        var portions: [QuranAyahRange] = []
        let storedKind: QuranSessionKind
        var drillKey: QuranMistakeKey?
        var nightKey: GregorianDay?
        switch kind {
        case .hifz, .bridge:
            guard let portion = kind == .bridge ? snapshot.hifz?.bridge : snapshot.hifz?.portion else { throw DataError.invalidValue("لا يوجد ورد جديد الآن") }
            if kind == .bridge, let wird = snapshot.hifz?.portion {
                portions = [try QuranAyahRange(first: portion.first, last: wird.last)]
            } else { portions = [portion] }
            storedKind = .hifz
        case .review:
            try await command("quran.freezeTest")
            let fresh = try self.snapshot()
            for page in fresh.review.allPages {
                let ids = catalog.ayahs(on: page).map(\.id)
                guard let first = ids.min(), let last = ids.max() else { continue }
                portions.append(try QuranAyahRange(first: first, last: last))
            }
            portions += fresh.partialRecent.flatMap(\.memorizedRanges); storedKind = .review
        case .free:
            guard let range, (1...604).contains(range.fromPage), (range.fromPage...604).contains(range.toPage),
                  let first = catalog.ayahs(on: range.fromPage).first?.id, let last = catalog.ayahs(on: range.toPage).last?.id else { throw QuranPlanError.invalidPages }
            portions = [try QuranAyahRange(first: first, last: last)]; storedKind = .free
        case .qiyam:
            let assignment = try QuranQiyamEngine.assignment(rakats: rakaat ?? 2, pages: snapshot.pages)
            for page in assignment.pagesToRecord {
                guard let first = catalog.ayahs(on: page).first?.id, let last = catalog.ayahs(on: page).last?.id else { continue }
                portions.append(try QuranAyahRange(first: first, last: last))
            }
            nightKey = try PrayerRepository(context: repository().context).defaultNight(at: clock()); storedKind = .qiyam
        case .drill:
            let spot = snapshot.mistakes.first { $0.isOpen && $0.hits > 0 && (spotID == nil || "\($0.key.ayahID):\($0.key.wordIndex.map(String.init) ?? "ayah")" == spotID) }
            guard let spot else { throw DataError.invalidValue("لا يوجد موضع تدريب") }
            drillKey = spot.key
            portions = [try QuranAyahRange(first: spot.key.ayahID, last: spot.key.ayahID)]; storedKind = .drill
        }
        guard let first = portions.first, let firstPage = catalog.ayah(id: first.first)?.page else { throw DataError.invalidValue("لا يوجد مقطع لهذه الجلسة") }
        var draft = QuranSessionDraft(planID: snapshot.plan?.plan.id, kind: storedKind, storedDay: snapshot.day,
            startedAt: clock(), portions: portions, page: firstPage, ayahID: first.first)
        if storedKind != .hifz { draft.coachStage = .blindRecitation }
        let value = QuranDraftPayload(draft: draft, method: storedKind == .hifz ? "coach" : "continuous", nightKey: nightKey, rakats: rakaat, drillKey: drillKey, testPages: storedKind == .review ? snapshot.review.testPages : [])
        try await save(value)
        return try await sessionState(value)
    }
    func resume(draftID: UUID) async throws -> QuranUISessionState { try await sessionState(savedDraft(draftID)) }
    func session(draftID: UUID, action: QuranUISessionAction) async throws -> QuranUISessionResult {
        var value = try savedDraft(draftID), draft = value.draft
        let catalog = try QuranResources.catalog()
        let planned = Set(draft.portions.flatMap { Array($0.first...$0.last) })
        switch action {
        case .discard:
            try await command("quran.discardDraft", ["draftID": .string(draftID.uuidString)]); return .discarded
        case .commit, .commitPartial:
            try await command("quran.commitSession", ["draftID": .string(draftID.uuidString)])
            let state = try await load(); return .completed(summary: state.summary)
        case .saveProgress: break
        case .changeMethod(let method):
            guard ["coach", "continuous"].contains(method), (draft.kind == .hifz ? method == "coach" : method == "continuous") else { throw DataError.invalidValue("هذه الطريقة غير متاحة للجلسة") }
            value.method = method
        case .reveal(let ayah, let word), .mistake(let ayah, let word):
            guard planned.contains(ayah), let record = catalog.ayah(id: ayah), word.map({ record.wordTokens.indices.contains($0) }) ?? true else { throw QuranPlanError.invalidSession }
            // Coach learning reveals stay hints. Only blind recitation records a slip.
            if draft.coachStage == .blindRecitation {
                let coverage = try snapshot().coverage
                if draft.kind != .free || coverage.completedPages.contains(draft.page) {
                    draft.mistakes.append(QuranDraftMistake(key: QuranMistakeKey(ayahID: ayah, wordIndex: word), at: clock(), kind: .mistake))
                }
            }
        case .chooseAnswer(let answer):
            guard draft.kind == .drill, ["pass", "fail"].contains(answer) else { throw QuranPlanError.invalidSession }
            draft.mistakes.append(QuranDraftMistake(key: value.drillKey ?? QuranMistakeKey(ayahID: draft.ayahID, wordIndex: nil), at: clock(), kind: answer == "pass" ? .drillPass : .drillFail))
        case .grade(let page, let grade):
            guard let rating = QuranReviewRating(storedRaw: grade.rawValue),
                  try draft.portions.contains(where: { try QuranPortionEngine.pages(for: $0, catalog: catalog).contains { $0.page == page } }) else { throw QuranPlanError.invalidPages }
            if try draft.kind == .free && !snapshot().coverage.completedPages.contains(page) { throw DataError.invalidValue("هذا الوجه للقراءة فقط؛ لم يُحفظ بعد") }
            let isTest = value.testPages?.contains(page) == true && draft.kind == .review
            draft.grades.removeAll { $0.page == page }; draft.grades.append(QuranDraftGrade(page: page, rating: rating, isTest: isTest))
        case .advance:
            if draft.kind == .hifz {
                switch draft.coachStage {
                case .repetition: draft.coachStage = .lineStarts
                case .lineStarts: draft.coachStage = .promptedRecall
                case .promptedRecall: draft.coachStage = .blindRecitation
                case .blindRecitation:
                    draft.blindPassedAyahs.formUnion(planned)
                    draft.coachStage = .rating
                    for page in Set(try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }).sorted() {
                        let ayahs = Set(catalog.ayahs(on: page).map(\.id)).intersection(planned)
                        let slips = draft.mistakes.filter { $0.kind == .mistake && ayahs.contains($0.key.ayahID) }.count
                        let rating = QuranMistakeEngine.gradeFromBlindSlips(slips, ayatCount: ayahs.count)
                        if !draft.grades.contains(where: { $0.page == page }) { draft.grades.append(QuranDraftGrade(page: page, rating: rating)) }
                    }
                case .rating: break
                }
            } else {
                let pages = try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }
                if let current = pages.firstIndex(of: draft.page), pages.indices.contains(current + 1) {
                    draft.page = pages[current + 1]; draft.ayahID = catalog.ayahs(on: draft.page).first?.id ?? draft.ayahID
                }
            }
        }
        value.draft = draft; try await save(value)
        return .active(try await sessionState(value))
    }
    func sessionState(_ value: QuranDraftPayload) async throws -> QuranUISessionState {
        let draft = value.draft, catalog = try QuranResources.catalog()
        let ids = Set(draft.portions.flatMap { Array($0.first...$0.last) })
        let verses = catalog.ayahs(on: draft.page).filter { ids.contains($0.id) }.map { ayah in
            QuranUIVerse(id: ayah.id, title: ayah.surahNameArabic + " " + numerals.string(ayah.ayahNumber), text: ayah.uthmaniText,
                hidden: draft.coachStage == .blindRecitation, canReveal: draft.coachStage != .rating)
        }
        let stage: QuranUISessionStage = switch draft.kind {
        case .hifz: switch draft.coachStage { case .repetition: .repetition; case .lineStarts: .lineStarts; case .promptedRecall: .recall; case .blindRecitation: .covered; case .rating: .grading }
        case .drill: .drill
        case .qiyam: .qiyam
        default: .review
        }
        let grades = draft.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "التقييم المقترح؛ يمكنك تغييره") }
        return QuranUISessionState(id: draft.id, title: draft.kind == .hifz ? "الورد" : "المراجعة", segmentTitle: "الوجه " + numerals.string(draft.page), stage: stage,
            progress: ids.isEmpty ? 0 : Double(draft.blindPassedAyahs.count) / Double(ids.count), prompt: "أكمل ثم سجّل ما تمّ", verses: verses,
            page: try await page(draft.page), answers: draft.kind == .drill ? [QuranUIAnswer(id: "pass", text: "أتقنت الموضع"), QuranUIAnswer(id: "fail", text: "أحتاج تدريبًا")] : [],
            grades: grades, primaryTitle: draft.coachStage == .rating ? "أنهِ وسجّل" : "تابع", primaryAction: draft.coachStage == .rating ? .commit : .advance,
            canAdvance: true, mistakeAyahID: draft.ayahID, method: value.method, availableMethods: [:], similar: nil, resourceError: nil)
    }
}
