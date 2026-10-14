import Foundation
import SwiftData
import CoreText
import MadarCore
import MadarData
import MadarCommands
import MadarQuran
import MadarPrayer

@MainActor final class AppQuranService: QuranUIService {
    private static var registeredPageFontName: String?
    private static var printedGlyphs: QuranPrintedGlyphs?
    private static var printedFontNames: [Int: String] = [:]
    unowned let app: AppSession
    let clock: @MainActor () -> Date
    init(session: AppSession, clock: @escaping @MainActor () -> Date = { prayerUITestClock(.now) }) { app = session; self.clock = clock }
    func repository() throws -> QuranRepository {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        return try QuranRepository(context: ModelContext(app.container), catalog: QuranResources.catalog())
    }
    func snapshot() throws -> QuranDataSnapshot { try repository().snapshot(at: clock()) }
    func command(_ name: String, _ payload: [String: MadarCore.JSONValue] = [:]) async throws {
        _ = try await app.executeQuranCommand(name, payload: payload)
    }
    var numerals: MadarNumberFormatter { MadarNumberFormatter(style: app.values["core.numerals"]?.string == "western" ? .western : .hindi) }
    func count(_ value: Int, singular: String, dual: String, plural: String) -> String {
        switch value {
        case 1: return singular
        case 2: return dual
        default:
            let counted = value >= 11 ? ["أجزاء": "جزءًا", "أوجه": "وجهًا", "أيام": "يومًا", "آيات": "آيةً", "مواضع": "موضعًا"][plural] ?? plural : plural
            return "\(numerals.string(value)) \(counted)"
        }
    }
    func faceCount(_ value: Int) -> String { count(value, singular: "وجه واحد", dual: "وجهان", plural: "أوجه") }
    func dayCount(_ value: Int) -> String { count(value, singular: "يوم واحد", dual: "يومان", plural: "أيام") }
    func range(_ portion: QuranAyahRange, catalog: QuranResourceCatalog) throws -> QuranUIRange {
        let pages = try QuranPortionEngine.pages(for: portion, catalog: catalog)
        guard let first = pages.first?.page, let last = pages.last?.page else { throw QuranPlanError.invalidPages }
        return QuranUIRange(fromPage: first, toPage: last)
    }
    func serviceWeekRatio(_ completed: Int, _ eligible: Int) -> String {
        numerals.string(completed) + " من " + numerals.string(eligible) + " أيام الحفظ"
    }
    func portionTitle(_ portion: QuranAyahRange, catalog: QuranResourceCatalog) -> String {
        guard let first = catalog.ayah(id: portion.first), let last = catalog.ayah(id: portion.last) else { return "" }
        return first.surahNameArabic + " " + numerals.string(first.ayahNumber) + "–" + (first.surahID == last.surahID ? "" : last.surahNameArabic + " ") + numerals.string(last.ayahNumber)
    }
    func load() async throws -> QuranRoomState {
        let snapshot = try snapshot(), catalog = try QuranResources.catalog(), today = snapshot.day.date
        let coverage = snapshot.coverage, completed = coverage.completedPages.count
        let juz = coverage.completedJuz.count, outside = coverage.pagesOutsideCompletedJuz.count
        let coverageTitle = completed == 0 ? "أول الطريق" : (juz == 0 ? faceCount(outside) : count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء") + (outside > 0 ? " و" + faceCount(outside) : ""))
        let streak = QuranProgressEngine.streak(activities: snapshot.activities, through: today, restDay: snapshot.restDay)
        let alreadyHifz = snapshot.sessions.contains { $0.kind == .hifz && $0.dayKey == today }
        var steps: [QuranUIStep] = []
        if let bridge = snapshot.hifz?.bridge {
            steps.append(QuranUIStep(id: "bridge", title: "الجسر", detail: portionTitle(bridge, catalog: catalog), kind: .bridge,
                completed: alreadyHifz, available: true, range: try range(bridge, catalog: catalog)))
        }
        if let portion = snapshot.hifz?.portion {
            steps.append(QuranUIStep(id: "hifz", title: snapshot.hifz?.balance == .consolidation ? "تثبيت الورد" : "الورد",
                detail: portionTitle(portion, catalog: catalog), kind: .hifz,
                completed: alreadyHifz, available: true, range: try range(portion, catalog: catalog)))
        }
        if !snapshot.review.allPages.isEmpty || !snapshot.partialRecent.isEmpty {
            let all = snapshot.review.allPages + snapshot.partialRecent.map(\.page)
            let detail = snapshot.review.allPages.isEmpty ? "الآيات المحفوظة من وجه جزئي" : faceCount(Set(snapshot.review.allPages).count) + " في خطوة واحدة"
            steps.append(QuranUIStep(id: "review", title: "المراجعة", detail: detail,
                kind: .review, completed: false, available: true, range: QuranUIRange(fromPage: all.min()!, toPage: all.max()!)))
        }
        let open = snapshot.mistakes.filter { $0.isOpen && $0.hits > 0 }
        if !open.isEmpty {
            steps.append(QuranUIStep(id: "drill", title: "مواضع الخطأ", detail: count(open.count, singular: "موضع واحد", dual: "موضعان", plural: "مواضع"), kind: .drill,
                completed: false, available: true, range: nil))
        }
        var heat: [QuranUIHeatDay] = []
        let firstHifzDay = snapshot.sessions.filter { $0.kind == .hifz }.map(\.dayKey).min()
        for offset in (-13)...0 {
            let key = today.adding(days: offset)
            guard let firstHifzDay, key >= firstHifzDay else { continue }
            let sessions = snapshot.sessions.filter { $0.dayKey == key }
            let memorized = snapshot.completedOn.values.filter { $0 == key }.count
            let reviewed = Set(sessions.filter { [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) }).count
            heat.append(QuranUIHeatDay(id: key.description, title: numerals.string(key.day), hifzFraction: Double(memorized),
                reviewFraction: Double(reviewed) / 8, accessibilityLabel: numerals.localized(key.description) + "، حفظ " + faceCount(memorized) + "، مراجعة " + faceCount(reviewed)))
        }
        let weekStart = today.adding(days: -6)
        let memorizedThisWeek = snapshot.completedOn.values.filter { $0 >= weekStart && $0 <= today }.count
        let weekReviews = snapshot.sessions.filter { $0.dayKey >= weekStart && $0.dayKey <= today && [.review, .free, .qiyam].contains($0.kind) }
        let reviewedThisWeek = Dictionary(grouping: weekReviews, by: \.dayKey).values.reduce(0) { total, sessions in
            total + Set(sessions.flatMap { $0.grades.map(\.page) }).count
        }
        let eligibleWeekDays = (0..<7).map { weekStart.adding(days: $0) }.filter { day in
            !snapshot.restDay.contains(day) && firstHifzDay.map { day >= $0 } == true
        }
        let activeDays = Set(snapshot.activities.filter(\.countsForStreak).map(\.dayKey))
        let completedDays = eligibleWeekDays.filter { activeDays.contains($0) }.count
        let weeklySummary = firstHifzDay == nil || firstHifzDay == today ? "أول يوم" : "آخر " + numerals.string(7) + " أيام: حفظت " + faceCount(memorizedThisWeek) + "، راجعت " + faceCount(reviewedThisWeek)
            + "، " + serviceWeekRatio(completedDays, eligibleWeekDays.count)
        let historySessions = snapshot.sessions.reversed().map { fact in
            QuranUIHistorySession(id: fact.id, title: fact.kind == .hifz ? "حفظ" : "مراجعة", dateLabel: numerals.localized(fact.dayKey.description),
                detail: faceCount(fact.pages.count), grades: fact.grades.map { QuranUIPageGrade(page: $0.page, title: "الوجه " + numerals.string($0.page),
                    grade: QuranUIGrade(rawValue: $0.rating.storedRaw)!, explanation: "تقييمك") }, warning: nil)
        }
        let plan = try snapshot.plan.map { record in
            let input = QuranUIPlanInput(startAyah: record.plan.startAyah, unit: QuranUIUnit(rawValue: record.plan.unit.rawValue)!, amount: record.plan.amount,
                rhythm: QuranUIRhythm(rawValue: record.plan.intensity.rawValue)!, restDay: snapshot.restDay.rawValue, missPolicy: record.missPolicy)
            return QuranUIPlan(title: "خطّتك", input: input, forecast: try forecast(input, snapshot: snapshot),
                nextAyah: try coverage.frontier(from: record.plan.startAyah) ?? 6236, versionLabel: "الخطة " + numerals.string(record.version))
        }
        let balance = switch snapshot.hifz?.balance { case .half: "نصف ورد"; case .consolidation: "تثبيت"; case .rest: "يوم راحة"; case .complete: "اكتمل نطاق الخطّة"; default: "ورد كامل" }
        let draft = snapshot.drafts.sorted { $0.startedAt > $1.startedAt }.first.map { QuranUIDraft(id: $0.id, title: "تابع جلستك", isPastDay: $0.storedDay.date != today) }
        var missedDay: GregorianDay?
        if let plan = snapshot.plan, plan.missPolicy == "ask" {
            var previous = today.adding(days: -1)
            while snapshot.restDay.contains(previous) { previous = previous.adding(days: -1) }
            let firstDay = GregorianDay.containing(plan.activeFrom, in: TimeZone(identifier: snapshot.day.timeZoneID)!)
            if previous >= firstDay && !snapshot.sessions.contains(where: { $0.dayKey == previous && $0.kind == .hifz }) && !snapshot.allotments.contains(where: { $0.origin == .missPolicy && $0.originDayKey == previous }) { missedDay = previous }
        }
        let surahs = Dictionary(grouping: catalog.ayahs, by: \.surahID).sorted { $0.key < $1.key }.map { id, ayahs in
            QuranUISurah(id: id, title: ayahs[0].surahNameArabic, firstAyah: ayahs[0].id, ayahCount: ayahs.count)
        }
        let strength = try catalog.juzCycleSegments().map { segment -> QuranUIStrength in
            let ayahs = Set(segment.ayahs.first...segment.ayahs.last)
            let pages = snapshot.pages.filter { catalog.ayahs(on: $0.page).contains { ayahs.contains($0.id) } }
            let mean = QuranProgressEngine.meanStrength(pages)
            return QuranUIStrength(id: segment.number, title: "الجزء " + numerals.string(segment.number), value: mean.map { Int($0.rounded()) },
                pageDetails: pages.map { "الوجه " + numerals.string($0.page) + "، " + numerals.percent($0.strength) }, canRaise: pages.contains(where: \.isFar), reviewRange: nil)
        }
        let errors = open.map { value in QuranUIErrorSpot(id: "\(value.key.ayahID):\(value.key.wordIndex.map(String.init) ?? "ayah")", title: "آية " + numerals.string(value.key.ayahID),
            detail: value.key.wordIndex == nil ? "الآية كاملة" : "موضع كلمة", isToday: false, closed: !value.isOpen, canDrill: true) }
        return QuranRoomState(coverageTitle: coverageTitle, coverageFraction: Double(completed) / 604,
            percentageLabel: numerals.percent(coverage.percent), streakLabel: "سلسلة " + dayCount(streak.days), balanceTitle: balance,
            balanceExplanation: "تتبع الخطة حاجة المراجعة ومقدار حفظك", hifzLevel: QuranUILevel(rawValue: snapshot.hifzLevel.rawValue)!,
            reviewLevel: QuranUILevel(rawValue: snapshot.reviewLevel.rawValue)!, steps: steps, recentDays: heat, plan: plan, surahs: surahs, draft: draft,
            missedDayKey: missedDay?.description, missedDayTitle: missedDay.map { "لو فاتك يوم " + numerals.localized($0.description) },
            summary: ["في صدرك " + coverageTitle], history: QuranUIHistory(weekSummary: [weeklySummary], yearSummary: [], allSummary: [], days: heat, coverage: [], sessions: historySessions),
            strengthTitle: "مؤشر وصفي من تقييمك ومواعيد المراجعة", strength: strength,
            recovery: QuranUIRecovery(distantLabel: faceCount(snapshot.pages.filter(\.isFar).count) + " بعيدة", activeTitle: snapshot.recovery == nil ? nil : "خطة استرداد", canCreate: snapshot.pages.contains(where: \.isFar), previews: [:]),
            errors: errors, toolsOrder: [], availableTools: [], blockOrder: ["sadr", "path", "log14", "tools"], hiddenBlocks: [],
            sessionUnavailableReason: nil, readerUnavailableReason: nil, numeralLocale: app.values["core.numerals"]?.string == "western" ? "en" : "ar")
    }
    func perform(_ value: QuranUICommand) async throws {
        switch value {
        case .setTodayLevel(let kind, let level): try await command("quran.setTodayLevel", ["kind": .string(kind.rawValue), "level": .string(level.rawValue)])
        case .forceNewHifz: try await command("quran.forceNewHifz")
        case .savePlan(let input): try await command("quran.savePlan", ["startAyah": .number(Double(input.startAyah)), "unit": .string(input.unit.rawValue), "amount": .number(input.amount), "rhythm": .string(input.rhythm.rawValue), "restDay": .string(input.restDay), "missPolicy": .string(input.missPolicy)])
        case .resolveMissed(let key, let choice): try await command("quran.resolveMissedDay", ["dayKey": .string(key), "choice": .string(choice.rawValue)])
        case .editSessionGrade(let id, let page, let grade): try await command("quran.editSessionGrade", ["sessionID": .string(id.uuidString), "page": .number(Double(page)), "grade": .string(grade.rawValue)])
        case .deleteSession(let id): try await command("quran.deleteSession", ["sessionID": .string(id.uuidString)])
        case .createRecovery(let days): try await command("quran.createRecovery", ["days": .number(Double(days))])
        case .cancelRecovery: try await command("quran.cancelRecovery")
        case .raisePages(let juz): try await command("quran.raisePages", ["juz": .number(Double(juz))])
        }
    }
    func previewPlan(_ input: QuranUIPlanInput) async throws -> QuranUIForecast { try forecast(input, snapshot: snapshot()) }
    func forecast(_ input: QuranUIPlanInput, snapshot: QuranDataSnapshot) throws -> QuranUIForecast {
        guard let unit = QuranHifzUnit(rawValue: input.unit.rawValue), let rest = QuranRestDay(rawValue: input.restDay), input.amount.isFinite, input.amount > 0, (1...6236).contains(input.startAyah) else { throw QuranPlanError.invalidAmount }
        let remainingAyahs = (input.startAyah...6236).filter { !snapshot.coverage.coveredAyahs.contains($0) }.count
        let catalog = try QuranResources.catalog()
        let remainingPages = Set(catalog.ayahs.filter { $0.id >= input.startAyah }.map(\.page)).subtracting(snapshot.coverage.completedPages).count
        let unitFaces = unit == .ayah ? (remainingAyahs == 0 ? 0 : Double(remainingPages) / Double(remainingAyahs)) : (unit == .half ? 0.5 : unit == .quarter ? 0.25 : 1)
        let result = QuranProgressEngine.forecast(remainingPages: Double(remainingPages), dailyPages: input.amount * unitFaces * snapshot.hifzLevel.hifzFactor,
            startingOn: snapshot.day.date, restDay: rest, allotments: snapshot.allotments, pagesPerPlanUnit: unitFaces)
        let title: String
        switch result {
        case .complete: title = snapshot.coverage.isKhatm ? "ختمت" : "اكتمل نطاق خطّتك"
        case .unavailable: title = "لم تتضح الوتيرة بعد"
        case .estimated(let day): title = DualDate(instant: day.date(in: .gmt).addingTimeInterval(43200), timeZone: .gmt).text(firstCalendar: .hijri, numerals: numerals.style)
        }
        return QuranUIForecast(title: title, assumptions: "تقدير بافتراض إتمام أيام الحفظ بلا فوت أو تثبيت، حُسب في " + numerals.localized(snapshot.day.dayKey),
            warning: input.amount * unitFaces > 2 ? "المقدار يتجاوز وجهين في يوم الحفظ" : nil, portions: [])
    }
    func index(_ unit: QuranUIIndexUnit) async throws -> [QuranUIIndexItem] {
        let snapshot = try snapshot(), catalog = try QuranResources.catalog()
        return (1...604).map { number in
            let ids = Set(catalog.ayahs(on: number).map(\.id)), count = ids.intersection(snapshot.coverage.coveredAyahs).count
            let page = snapshot.pages.first { $0.page == number }
            return QuranUIIndexItem(id: String(number), title: "الوجه " + numerals.string(number), subtitle: "", firstPage: number,
                fraction: ids.isEmpty ? 0 : Double(count) / Double(ids.count), memorized: snapshot.coverage.completedPages.contains(number),
                reviewed: snapshot.sessions.contains { [.review, .free, .qiyam].contains($0.kind) && $0.pages.contains(number) }, due: page?.isDue ?? false,
                isToday: snapshot.review.allPages.contains(number))
        }
    }
    func page(_ number: Int) async throws -> QuranUIPage {
        let catalog = try QuranResources.catalog()
        guard let layout = catalog.layout?.page(number), let fontURL = QuranResourceCatalog.bundledFontURL() else { throw QuranPlanError.invalidPages }
        let name: String
        if let cached = Self.registeredPageFontName { name = cached }
        else {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else { throw QuranPlanError.invalidPages }
            name = CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 23.3, nil)) as String
            Self.registeredPageFontName = name
        }
        let printed: QuranPrintedGlyphs
        if let cached = Self.printedGlyphs { printed = cached }
        else { printed = try QuranPrintedGlyphs.bundled(); Self.printedGlyphs = printed }
        let printPage = printed.pages[number - 1]
        let printName: String
        if let cached = Self.printedFontNames[number] { printName = cached }
        else {
            let url = try QuranPrintedGlyphs.fontURL(page: number)
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else { throw QuranPlanError.invalidPages }
            printName = CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 23.3, nil)) as String
            guard printName == printPage.fontName else { throw QuranPlanError.invalidPages }
            Self.printedFontNames[number] = printName
        }
        let glyphs = Dictionary(uniqueKeysWithValues: printPage.entries.map { ("\($0.ayahID):\($0.wordIndex.map(String.init) ?? "end")", $0.glyphs) })
        let lines = try layout.lines.map { line -> QuranUILine in
            var parts: [String] = []
            var words: [QuranUIWord] = []
            for word in line.words {
                guard let ayah = catalog.ayah(id: word.ayahID) else { throw QuranPlanError.invalidPages }
                let tokens = ayah.wordTokens
                guard tokens.indices.contains(word.wordIndex) else { throw QuranPlanError.invalidPages }
                parts.append(tokens[word.wordIndex].text)
                guard let printedWord = glyphs["\(ayah.id):\(word.wordIndex)"] else { throw QuranPlanError.invalidPages }
                words.append(QuranUIWord(ayahID: ayah.id, index: word.wordIndex, text: tokens[word.wordIndex].text, ayahWordCount: tokens.count, printedGlyphs: printedWord))
                if word.wordIndex == tokens.count - 1, line.ayahEnds.contains(ayah.id) {
                    let marker = (ayah.uthmaniText as NSString).substring(from: tokens[word.wordIndex].utf16Range.upperBound).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !marker.isEmpty {
                        guard let printedMark = glyphs["\(ayah.id):end"] else { throw QuranPlanError.invalidPages }
                        parts.append(marker); words.append(QuranUIWord(ayahID: ayah.id, index: nil, text: marker, printedGlyphs: printedMark))
                    }
                }
            }
            let text = line.kind == .surah ? (catalog.ayahs.first { $0.surahID == line.surahID }?.surahNameArabic ?? "") : line.kind == .basmala ? "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ" : parts.joined(separator: " ")
            return QuranUILine(id: line.number, glyphs: text, semanticText: text, words: words, centered: line.kind != .ayah || number <= 2, surahOpening: line.kind == .surah)
        }
        return QuranUIPage(page: number, title: "الوجه " + numerals.string(number), postScriptName: name, lines: lines,
            semanticAyat: catalog.ayahs(on: number).map { QuranUIVerse(id: $0.id, title: $0.surahNameArabic + " " + numerals.string($0.ayahNumber), text: $0.uthmaniText, hidden: false, canReveal: false) },
            surahTitle: catalog.ayahs(on: number).first?.surahNameArabic ?? "", juzTitle: "الجزء " + numerals.string(catalog.ayahs(on: number).first?.juz ?? 1), numberLabel: numerals.string(number), printedPostScriptName: printName)
    }
    func qiyamPreview(rakaat: Int) async throws -> QuranUIQiyamPreview {
        let snapshot = try snapshot(), result = try QuranQiyamEngine.assignment(rakats: rakaat, pages: snapshot.pages)
        return QuranUIQiyamPreview(rakaat: rakaat, nightKey: try PrayerRepository(context: repository().context).defaultNight(at: clock()).description, title: "ورد القيام", assignments: result.pageByRakah.map { $0.map { "الوجه " + numerals.string($0) } ?? "أعد ما شئت" }, canBegin: !result.pagesToRecord.isEmpty)
    }
}

func quranUserMessage(_ error: any Error) -> String {
    if let data = error as? DataError, case .invalidValue(let message) = data,
       message.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) { return message }
    if case BackupOperationError.busy = error { return "انتظر انتهاء العملية الحالية، ثم حاول مرة أخرى" }
    return "تعذّر إتمام العملية. حاول مرة أخرى"
}
