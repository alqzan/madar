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
        var bridgeAyahs: [Int] = []
        var reviewSections: [QuranReviewSection]?
        switch kind {
        case .hifz, .bridge:
            guard let portion = kind == .bridge ? snapshot.hifz?.bridge : snapshot.hifz?.portion else { throw DataError.invalidValue("لا يوجد ورد جديد الآن") }
            if kind == .bridge, let wird = snapshot.hifz?.portion {
                bridgeAyahs = Array(portion.first...portion.last)
                portions = [wird]
            } else { portions = [portion] }
            storedKind = .hifz
        case .review:
            try await command("quran.freezeTest")
            let fresh = try self.snapshot()
            let recent = Set(fresh.recentPages)
            let sections = QuranReviewSection.make(regular: fresh.review.regularPages, recent: recent,
                partialRecent: fresh.partialRecent.map(\.page), tests: fresh.review.testPages)
            reviewSections = sections
            let partialByPage = Dictionary(uniqueKeysWithValues: fresh.partialRecent.map { ($0.page, $0.memorizedRanges) })
            for page in sections.flatMap(\.pages) {
                if let ranges = partialByPage[page] { portions += ranges; continue }
                let ids = catalog.ayahs(on: page).map(\.id)
                guard let first = ids.min(), let last = ids.max() else { continue }
                portions.append(try QuranAyahRange(first: first, last: last))
            }
            storedKind = .review
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
            // §7.4 order and the shared 3/5/8 allowance: today's spots first, then «أخطائي».
            let queue = snapshot.drillBoard.todayQueue + snapshot.drillBoard.mineQueue
            let spot = queue.first { spotID == nil || Self.spotID($0.key) == spotID }
            guard let spot else { throw DataError.invalidValue("لا يوجد موضع تدريب") }
            drillKey = spot.key
            portions = [try QuranAyahRange(first: spot.key.ayahID, last: spot.key.ayahID)]; storedKind = .drill
        }
        guard let first = portions.first, let firstPage = catalog.ayah(id: first.first)?.page else { throw DataError.invalidValue("لا يوجد مقطع لهذه الجلسة") }
        var draft = QuranSessionDraft(planID: snapshot.plan?.plan.id, kind: storedKind, storedDay: snapshot.day,
            startedAt: clock(), portions: portions, page: firstPage, ayahID: first.first)
        if storedKind != .hifz { draft.coachStage = .blindRecitation }
        var value = QuranDraftPayload(draft: draft, method: storedKind == .hifz ? "coach" : "continuous", nightKey: nightKey, rakats: rakaat, drillKey: drillKey, testPages: storedKind == .review ? snapshot.review.testPages : [])
        if storedKind == .hifz { value.coach = QuranCoachProgress(bridgeAyahs: bridgeAyahs, intensity: snapshot.plan?.plan.intensity ?? .balanced) }
        value.reviewSections = reviewSections
        if storedKind == .qiyam { value.qiyamRakahIndex = 0 }
        try await save(value)
        return try await sessionState(value)
    }
    func resume(draftID: UUID) async throws -> QuranUISessionState { try await sessionState(savedDraft(draftID)) }
    func session(draftID: UUID, action: QuranUISessionAction) async throws -> QuranUISessionResult {
        var value = try savedDraft(draftID), draft = value.draft
        let catalog = try QuranResources.catalog()
        if draft.storedDay.date != (try snapshot().day.date) {
            switch action {
            case .commitPartial, .discard, .saveProgress: break
            default: throw DataError.invalidValue("احفظ ما تمّ من الجلسة السابقة أو تجاهلها")
            }
        }
        let planned = Set(draft.portions.flatMap { Array($0.first...$0.last) })
        switch action {
        case .discard:
            try await command("quran.discardDraft", ["draftID": .string(draftID.uuidString)]); return .discarded
        case .commit, .commitPartial:
            if case .commitPartial = action, draft.grades.isEmpty, draft.blindPassedAyahs.isEmpty, draft.kind != .drill {
                try await command("quran.discardDraft", ["draftID": .string(draftID.uuidString)])
                return .discarded
            }
            let wasKhatm: Bool
            if draft.kind == .hifz { wasKhatm = try snapshot().coverage.isKhatm } else { wasKhatm = false }
            var payload: [String: MadarCore.JSONValue] = ["draftID": .string(draftID.uuidString)]
            if draft.kind == .qiyam, case .commitPartial = action { payload["partial"] = .bool(true) }
            try await command("quran.commitSession", payload)
            let state = try await load()
            let reachedKhatm: Bool
            if draft.kind == .hifz, !wasKhatm { reachedKhatm = try snapshot().coverage.isKhatm } else { reachedKhatm = false }
            return .completed(summary: state.summary, reachedKhatm: reachedKhatm)
        case .saveProgress: break
        case .changeMethod(let method):
            guard draft.kind == .hifz ? QuranLearningMethod(rawValue: method) != nil : method == "continuous" else { throw DataError.invalidValue("هذه الطريقة غير متاحة للجلسة") }
            if method == "link", draft.page == 1 { throw QuranPlanError.invalidPages }
            if method == "next", draft.ayahID == 1 { throw QuranPlanError.invalidSession }
            value.method = method
            if value.coach != nil, [.repetition, .lineStarts, .promptedRecall].contains(draft.coachStage) {
                value.coach?.repetitions = 0; draft.coachStage = .repetition; value.revealedAyahs = []
            }
        case .reveal(let ayah, let word), .mistake(let ayah, let word):
            guard planned.contains(ayah), let record = catalog.ayah(id: ayah), word.map({ record.wordTokens.indices.contains($0) }) ?? true else { throw QuranPlanError.invalidSession }
            if case .reveal = action {
                if value.revealedAyahs?.contains(ayah) == true { return .active(try await sessionState(value)) }
                value.revealedAyahs = (value.revealedAyahs ?? []).union([ayah])
                if draft.coachStage != .blindRecitation { value.coach?.learningHints += 1 }
            }
            // Coach learning reveals stay hints. Only blind recitation records a slip.
            let explicitMistake: Bool = if case .mistake = action { true } else { false }
            // A word slip is recorded once per session; pressing the same word again does not add a second slip.
            if let word, explicitMistake, draft.mistakes.contains(where: { $0.kind == .mistake && $0.key == QuranMistakeKey(ayahID: ayah, wordIndex: word) }) {
                return .active(try await sessionState(value))
            }
            if draft.coachStage == .blindRecitation && (draft.kind == .hifz || explicitMistake) {
                let coverage = try snapshot().coverage
                if draft.kind != .free || coverage.completedPages.contains(draft.page) {
                    draft.mistakes.append(QuranDraftMistake(key: QuranMistakeKey(ayahID: ayah, wordIndex: word), at: clock(), kind: .mistake))
                }
            }
        case .chooseAnswer(let answer):
            guard draft.kind == .drill, ["pass", "fail"].contains(answer) else { throw QuranPlanError.invalidSession }
            // One result per drill session: a second tap replaces the first, it never counts as a second success.
            draft.mistakes.removeAll { $0.kind != .mistake }
            draft.mistakes.append(QuranDraftMistake(key: value.drillKey ?? QuranMistakeKey(ayahID: draft.ayahID, wordIndex: nil), at: clock(), kind: answer == "pass" ? .drillPass : .drillFail))
        case .grade(let page, let grade):
            guard let rating = QuranReviewRating(storedRaw: grade.rawValue),
                  try draft.portions.contains(where: { try QuranPortionEngine.pages(for: $0, catalog: catalog).contains { $0.page == page } }) else { throw QuranPlanError.invalidPages }
            if try draft.kind == .free && !snapshot().coverage.completedPages.contains(page) { throw DataError.invalidValue("هذا الوجه للقراءة فقط؛ لم يُحفظ بعد") }
            let isTest = value.testPages?.contains(page) == true && draft.kind == .review
            draft.grades.removeAll { $0.page == page }; draft.grades.append(QuranDraftGrade(page: page, rating: rating, isTest: isTest))
        case .advance:
            if draft.kind == .qiyam {
                let pages = qiyamPages(draft, catalog: catalog), total = value.rakats ?? 2
                let index = value.qiyamRakahIndex ?? draft.grades.count
                guard index < total else { throw QuranPlanError.invalidSession }
                if pages.indices.contains(index), !draft.grades.contains(where: { $0.page == pages[index] }) {
                    draft.grades.append(QuranDraftGrade(page: pages[index], rating: .good))
                }
                value.qiyamRakahIndex = index + 1
                if index + 1 == total { draft.coachStage = .rating }
                else {
                    draft.coachStage = .blindRecitation
                    if pages.indices.contains(index + 1) { draft.page = pages[index + 1]; draft.ayahID = catalog.ayahs(on: draft.page).first!.id }
                }
            } else if draft.kind == .hifz {
                if var coach = value.coach, coach.bridgePending {
                    coach.bridgePending = false; value.coach = coach; value.draft = draft
                    try await save(value); return .active(try await sessionState(value))
                }
                if var coach = value.coach, [.repetition, .lineStarts, .promptedRecall].contains(draft.coachStage) {
                    let pageAyahs = catalog.ayahs(on: draft.page).map(\.id).filter { planned.contains($0) }
                    coach.advanceLearning(stage: &draft.coachStage, ayahID: &draft.ayahID, pageAyahs: pageAyahs,
                        intensity: coach.intensity, method: QuranLearningMethod(rawValue: value.method) ?? .coach)
                    value.coach = coach
                } else {
                switch draft.coachStage {
                case .repetition: draft.coachStage = .lineStarts
                case .lineStarts: draft.coachStage = .promptedRecall
                case .promptedRecall: draft.coachStage = .blindRecitation
                case .blindRecitation:
                    let completed = Set(catalog.ayahs(on: draft.page).map(\.id)).intersection(planned)
                    draft.blindPassedAyahs.formUnion(completed)
                    draft.coachStage = .rating
                    for page in [draft.page] {
                        let ayahs = Set(catalog.ayahs(on: page).map(\.id)).intersection(planned)
                        let slips = draft.mistakes.filter { $0.kind == .mistake && ayahs.contains($0.key.ayahID) }.count
                        let rating = QuranMistakeEngine.gradeFromBlindSlips(slips, ayatCount: ayahs.count)
                        if !draft.grades.contains(where: { $0.page == page }) { draft.grades.append(QuranDraftGrade(page: page, rating: rating)) }
                    }
                case .rating:
                    let pages = Set(try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }).sorted()
                    if let current = pages.firstIndex(of: draft.page), pages.indices.contains(current + 1) {
                        draft.page = pages[current + 1]
                        draft.ayahID = catalog.ayahs(on: draft.page).first(where: { planned.contains($0.id) })?.id ?? draft.ayahID
                        draft.coachStage = .repetition
                        value.coach?.repetitions = 0
                    }
                }
                }
                value.revealedAyahs = []
            } else if draft.kind == .review || draft.kind == .free {
                var seen = Set<Int>()
                let pages = try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }.filter { seen.insert($0).inserted }
                if draft.coachStage == .blindRecitation {
                    let ayahs = Set(catalog.ayahs(on: draft.page).map(\.id)).intersection(planned)
                    let slips = draft.mistakes.filter { $0.kind == .mistake && ayahs.contains($0.key.ayahID) }.count
                    let canGrade = draft.kind != .free ? true : try snapshot().coverage.completedPages.contains(draft.page)
                    if canGrade && !draft.grades.contains(where: { $0.page == draft.page }) {
                        draft.grades.append(QuranDraftGrade(page: draft.page, rating: QuranMistakeEngine.gradeFromBlindSlips(slips, ayatCount: ayahs.count), isTest: value.testPages?.contains(draft.page) == true))
                    }
                    draft.coachStage = .rating
                    // Grading shows the page it grades: a whole-page check uncovers everything in the same save.
                    value.revealedAyahs = (value.revealedAyahs ?? []).union(ayahs)
                } else if let current = pages.firstIndex(of: draft.page), pages.indices.contains(current + 1) {
                    draft.page = pages[current + 1]
                    draft.ayahID = catalog.ayahs(on: draft.page).first(where: { planned.contains($0.id) })?.id ?? draft.ayahID
                    draft.coachStage = .blindRecitation; value.revealedAyahs = []
                }
            } else if draft.kind != .drill {
                let coverage = try snapshot().coverage
                let covered = Set(catalog.ayahs(on: draft.page).map(\.id)).intersection(planned).intersection(coverage.coveredAyahs)
                if !covered.isEmpty && (draft.kind != .free || coverage.completedPages.contains(draft.page)) && !draft.grades.contains(where: { $0.page == draft.page }) {
                    let slips = draft.mistakes.filter { $0.kind == .mistake && covered.contains($0.key.ayahID) }.count
                    let rating = draft.kind == .qiyam ? QuranReviewRating.good : QuranMistakeEngine.gradeFromBlindSlips(slips, ayatCount: covered.count)
                    draft.grades.append(QuranDraftGrade(page: draft.page, rating: rating, isTest: value.testPages?.contains(draft.page) == true))
                }
                var seen = Set<Int>()
                let pages = try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }.filter { seen.insert($0).inserted }
                if let current = pages.firstIndex(of: draft.page), pages.indices.contains(current + 1) {
                    draft.page = pages[current + 1]; draft.ayahID = catalog.ayahs(on: draft.page).first?.id ?? draft.ayahID
                } else { draft.coachStage = .rating }
                value.revealedAyahs = []
            }
        }
        value.draft = draft; try await save(value)
        return .active(try await sessionState(value))
    }
    func sessionState(_ value: QuranDraftPayload) async throws -> QuranUISessionState {
        let draft = value.draft, catalog = try QuranResources.catalog()
        let ids = Set(draft.portions.flatMap { Array($0.first...$0.last) })
        let verses = catalog.ayahs(on: draft.page).filter { ids.contains($0.id) }.map { ayah in
            QuranUIVerse(id: ayah.id, title: ayah.surahNameArabic + " " + numerals.string(ayah.ayahNumber), text: draft.coachStage == .lineStarts ? (ayah.wordTokens.first?.text ?? "") : ayah.uthmaniText,
                hidden: (draft.coachStage == .blindRecitation || draft.coachStage == .promptedRecall) && !(value.revealedAyahs?.contains(ayah.id) ?? false), canReveal: draft.coachStage != .rating)
        }
        let stage: QuranUISessionStage = switch draft.kind {
        case .hifz: switch draft.coachStage { case .repetition: .repetition; case .lineStarts: .lineStarts; case .promptedRecall: .recall; case .blindRecitation: .covered; case .rating: .grading }
        case .drill: .drill
        case .qiyam: draft.coachStage == .rating ? .grading : .qiyam
        default: draft.coachStage == .rating ? .grading : .review
        }
        var displayGrades = draft.grades.filter { $0.page == draft.page }
        let canGrade = draft.kind != .free ? true : try snapshot().coverage.completedPages.contains(draft.page)
        if displayGrades.isEmpty && draft.kind != .drill && canGrade {
            displayGrades = [QuranDraftGrade(page: draft.page, rating: draft.kind == .qiyam ? .good : .mastered)]
        }
        let grades = displayGrades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "التقييم المقترح؛ يمكنك تغييره") }
        let hifzComplete = draft.kind == .hifz && ids.isSubset(of: draft.blindPassedAyahs)
        var orderedSeen = Set<Int>()
        let orderedPages = try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }.filter { orderedSeen.insert($0).inserted }
        let finished = draft.coachStage == .rating && (draft.kind != .hifz || hifzComplete) && (![.review, .free].contains(draft.kind) || draft.page == orderedPages.last) || draft.kind == .drill && !draft.mistakes.isEmpty
        let readOnlyFinished = finished && draft.kind == .free && draft.grades.isEmpty
        var state = QuranUISessionState(id: draft.id, title: draft.kind == .hifz ? "الورد" : "المراجعة", segmentTitle: "الوجه " + numerals.string(draft.page), stage: stage,
            progress: ids.isEmpty ? 0 : Double(draft.blindPassedAyahs.count) / Double(ids.count), prompt: "أكمل ثم سجّل ما تمّ", verses: verses,
            page: try await page(draft.page), answers: draft.kind == .drill ? [QuranUIAnswer(id: "pass", text: "أتقنت الموضع"), QuranUIAnswer(id: "fail", text: "أحتاج تدريبًا")] : [],
            grades: grades, primaryTitle: readOnlyFinished ? "أغلق القراءة" : finished ? "أنهِ وسجّل" : "تابع", primaryAction: readOnlyFinished ? .discard : finished ? .commit : .advance,
            canAdvance: true, mistakeAyahID: draft.ayahID, method: value.method, availableMethods: [:], similar: nil, resourceError: nil)
        state.startedAt = draft.startedAt; state.numeralLocale = app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab"
        if draft.kind == .drill, let card = try await drillCard(value, catalog: catalog) {
            state.title = "اختبار مواضع الخطأ"; state.drill = card
        }
        if let coach = value.coach {
            let record = catalog.ayah(id: draft.ayahID)!
            let target = QuranCoachProgress.repetitionTarget(coach.intensity)
            let ayahNumber = numerals.string(record.ayahNumber)
            let pages = Set(try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) }).sorted()
            let isBridge = coach.bridgePending
            if isBridge, let id = coach.bridgeAyahs.last, let bridge = catalog.ayah(id: id) { state.page = try await page(bridge.page) }
            state.title = isBridge ? "الجسر" : "الحفظ الجديد · الورد"
            state.segmentTitle = MadarInlineText.joined([portionTitle(try QuranAyahRange(first: ids.min()!, last: ids.max()!), catalog: catalog), QuranLearningMethod(rawValue: value.method)?.title ?? "المدرّب الموجّه"])
            let stageTitle: String = switch draft.coachStage { case .repetition: "التكرار"; case .lineStarts: "أوائل الأسطر"; case .promptedRecall: "استرجاع بالتلقين"; case .blindRecitation: "تسميع مستور"; case .rating: "تقييمك" }
            var caption: String = switch draft.coachStage {
            case .repetition: "كرّر الآية " + ayahNumber + " وهي أمامك"
            case .lineStarts: "استعن بأوائل الأسطر، واللمس يكشف التلقين"
            case .promptedRecall: "سمّع الآية من حفظك؛ التلقين هنا بلا خطأ"
            case .blindRecitation: "سمّع الورد مستورًا؛ اللمس يسجّل تعثّرًا"
            case .rating: "تقييم مقترح من تعثّرك؛ يمكنك تغييره"
            }
            if isBridge { caption = switch coach.bridgeAyahs.count {
            case 1: "اقرأ الآية المحفوظة السابقة، ثم ابدأ الورد"
            case 2: "اقرأ الآيتين المحفوظتين السابقتين، ثم ابدأ الورد"
            default: "اقرأ آخر " + numerals.string(coach.bridgeAyahs.count) + " آيات محفوظة، ثم ابدأ الورد"
            } }
            else if draft.coachStage == .repetition {
                switch value.method {
                case "completeAyah": caption = "أكمل الآية من كلمتيها الأوليين؛ اللمس تلقين"
                case "next": caption = "ما الآية التي تلي هذا الموضع؟"
                case "gradual": caption = "أُخفي " + ["ربع الآية", "نصف الآية", "ثلاثة أرباع الآية", "الآية كلها"][min(3, coach.repetitions)] + "؛ اللمس تلقين"
                case "link": caption = "صل آخر سطر من الوجه السابق بأول هذا الوجه"
                default: break
                }
            }
            let reference: String?
            if value.method == "link", draft.page > 1 { reference = try await page(draft.page - 1).lines.last?.glyphs }
            else if value.method == "next", draft.ayahID > 1 { reference = catalog.ayah(id: draft.ayahID - 1)?.uthmaniText }
            else { reference = nil }
            state.coach = QuranUICoach(activeAyahID: draft.ayahID, activeAyahNumber: ayahNumber,
                plannedAyahs: isBridge ? Set(coach.bridgeAyahs) : ids, revealedAyahs: value.revealedAyahs ?? [],
                repetition: coach.repetitions, target: target, bridge: isBridge, method: value.method, stageTitle: stageTitle,
                pageProgress: "الوجه " + numerals.string((pages.firstIndex(of: draft.page) ?? 0) + 1) + " من " + numerals.string(pages.count), caption: caption, pages: pages, referenceText: reference, pastDay: draft.storedDay.date != (try snapshot().day.date))
            state.availableMethods = Dictionary(uniqueKeysWithValues: QuranLearningMethod.allCases.filter { ($0 != .link || draft.page > 1) && ($0 != .next || draft.ayahID > 1) }.map { ($0.rawValue, $0.title) })
            if isBridge { state.primaryTitle = "ابدأ الورد" }
            else if !finished { state.primaryTitle = switch draft.coachStage {
            case .repetition: value.method == "coach" ? "كرّرتها " + numerals.string(coach.repetitions) + " من " + numerals.string(target) : "سمّعتها"
            case .lineStarts: "عرفت أوائل الأسطر"
            case .promptedRecall: "سمّعت الآية"
            case .blindRecitation: "سمّعت الورد"
            case .rating: "الوجه التالي"
            } }
            if value.method == "gradual", draft.coachStage == .repetition, coach.repetitions < 3 { state.primaryTitle = "أخفِ المزيد" }
        }
        if draft.kind == .review || draft.kind == .free {
            let sections = value.reviewSections ?? [QuranReviewSection(kind: .due, pages: orderedPages)]
            let sectionIndex = sections.firstIndex { $0.pages.contains(draft.page) } ?? 0
            let section = sections[sectionIndex]
            let currentAyahs = catalog.ayahs(on: draft.page).filter { ids.contains($0.id) }
            let revealed = value.revealedAyahs ?? []
            let next = currentAyahs.first { !revealed.contains($0.id) }
            let revealedCount = currentAyahs.filter { revealed.contains($0.id) }.count
            state.title = draft.kind == .free ? "مراجعة حرة" : "المراجعة · " + faceCount(orderedPages.count) + " في خطوة واحدة"
            let range = section.pages.first == section.pages.last ? numerals.string(section.pages.first ?? draft.page) : numerals.string(section.pages.first ?? draft.page) + "–" + numerals.string(section.pages.last ?? draft.page)
            state.segmentTitle = section.title + " " + range + "، الوجه " + numerals.string(draft.page)
            let record = try snapshot().pages.first { $0.page == draft.page }
            let far = record?.isFar == true, quick = canGrade && record.map { $0.grade == .mastered && !$0.isFar } == true
            let progressLine = "كشفت " + numerals.string(revealedCount) + " من " + numerals.string(currentAyahs.count)
            let caption = draft.kind == .free && !canGrade ? "قراءة فقط؛ هذا الوجه غير مكتمل في صدرك" : stage == .grading ? "تقييم مقترح من تعثّرك؛ يمكنك تغييره"
                : revealedCount > 0 ? progressLine : quick ? "وجه متقن؛ سمّعه كله ثم اكشفه مرة واحدة" : far ? "وجه بعُد عهدك به؛ خذه آية آية" : "اسحب جانبًا لتكشف الآية التالية"
            state.coach = QuranUICoach(activeAyahID: next?.id ?? currentAyahs.last?.id ?? draft.ayahID, activeAyahNumber: numerals.string(next?.ayahNumber ?? 0),
                plannedAyahs: ids, revealedAyahs: revealed, repetition: 0, target: 0, bridge: false, method: "continuous", stageTitle: stage == .grading ? "تقييمك" : "المراجعة المستورة",
                pageProgress: "المقطع " + numerals.string(sectionIndex + 1) + " من " + numerals.string(sections.count), caption: caption, pages: orderedPages, referenceText: nil,
                pastDay: draft.storedDay.date != (try snapshot().day.date), review: true, flaggedAyahs: Set(draft.mistakes.filter { $0.key.wordIndex == nil }.map { $0.key.ayahID }), quickCheck: quick, farPage: far, pageAyahs: currentAyahs.map(\.id))
            state.availableMethods = ["continuous": "سرد متصل"]
            if stage == .review {
                if let next { state.primaryTitle = "كشفت التالية"; state.primaryAction = .reveal(ayahID: next.id, wordIndex: nil) }
                else { state.primaryTitle = "قيّم هذا الوجه"; state.primaryAction = .advance }
            } else if !finished { state.primaryTitle = "تابع" }
        }
        if draft.kind == .qiyam {
            state.qiyam = try qiyamSession(value, catalog: catalog)
            state.title = "ورد القيام"
            state.grades = draft.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page), grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "جيد مقترح؛ عدّل تقييمك") }
        }
        state.coach?.flaggedWords = Set(draft.mistakes.compactMap { mistake in mistake.key.wordIndex.map { QuranUICoach.wordKey(mistake.key.ayahID, $0) } })
        return state
    }
}
