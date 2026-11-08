import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// `mal.analysisDefault`: the two periods the spec names («التقرير المخطوط، الدورة والأسبوع»).
/// FB-39 (owner, 6 Nov): also the calendar month and year, each compared with the one before.
enum MoneyAnalysisPeriod: String, CaseIterable, Identifiable, Sendable {
    case cycle, week, month, year
    var id: String { rawValue }
}

struct MoneyAnalysisCategory: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// V10's one definition: − Σ spend/refund allocations of the confirmed movements in this category for the period.
    var spentMinor: Int
    /// The cycle limit (cycle view) or its even share over the week's days (week view); nil = no limit.
    var capMinor: Int?
    /// Index in category order, so a category keeps the binding colour it has on its shelf; nil = uncategorized.
    var tint: Int?
}

struct MoneyAnalysisMerchant: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var amountMinor: Int
    var count: Int
}

struct MoneyAnalysisComparison: Equatable, Sendable {
    var percent: Int
    var label: String
}

struct MoneyAnalysisReading: Sendable {
    var period: MoneyAnalysisPeriod
    var offset: Int
    var canGoBack: Bool
    var title: String
    var first: GregorianDay
    var last: GregorianDay
    var today: GregorianDay
    /// Every day of the period; days after today have no result.
    var days: [MoneyLogDay]
    var spentMinor: Int
    var allowanceMinor: Int
    var running: Bool
    var comparison: MoneyAnalysisComparison?
    var categories: [MoneyAnalysisCategory]
    var merchants: [MoneyAnalysisMerchant]
    var metDays: Int
    var judgedDays: Int
    var pendingDays: Int
    var pace: AnalysisEngine.Pace?
    var dailyLineMinor: Int? { days.last { $0.day <= today && $0.dailyMinor != nil }?.dailyMinor }
    var categoriesTotalMinor: Int { categories.reduce(0) { $0 + $1.spentMinor } }
}

struct MadarAIMoneyMetric: Identifiable, Sendable {
    enum Kind: Sendable { case category, merchant }
    let id: String
    let name: String
    let amountMinor: Int
    let kind: Kind
}

struct MadarAIMoneyFact: Identifiable, Sendable {
    let id: String
    let title: String
    let amountMinor: Int
}

struct MadarAIMoneyCategoryMerchant: Identifiable, Sendable {
    let id: String
    let categoryID: String
    let categoryName: String
    let merchantID: String
    let merchantName: String
    let amountMinor: Int
}

struct MadarAIMoneySnapshot: Sendable {
    let firstDayKey: String
    let lastDayKey: String
    let rangeTitle: String
    let confirmedCount: Int
    let pendingCount: Int
    let totalMinor: Int
    let categories: [MadarAIMoneyMetric]
    let merchants: [MadarAIMoneyMetric]
    let previousTotalMinor: Int?
    let previousCategories: [MadarAIMoneyMetric]?
    let previousMerchants: [MadarAIMoneyMetric]?
    let categoryMerchants: [MadarAIMoneyCategoryMerchant]
    let previousCategoryMerchants: [MadarAIMoneyCategoryMerchant]?

    /// The model receives labels and already-computed trends only. Amounts stay in the UI's deterministic reading.
    var modelContextArabic: String {
        var lines = ["النطاق: \(rangeTitle)."]
        let leadingCategories = categories.filter { $0.amountMinor > 0 }.prefix(8).map(\.name)
        if !leadingCategories.isEmpty { lines.append("أعلى التصنيفات المسجلة: " + leadingCategories.joined(separator: "، ") + ".") }
        let leadingMerchants = merchants.filter { $0.amountMinor > 0 }.prefix(5).map(\.name)
        if !leadingMerchants.isEmpty { lines.append("أبرز الجهات المسجلة: " + leadingMerchants.joined(separator: "، ") + ".") }
        else { lines.append("لا توجد حركات مؤكدة مرتبطة بجهة مسجلة في هذا النطاق.") }
        for category in categories.filter({ $0.amountMinor > 0 }).prefix(8) {
            if let merchant = categoryMerchants.first(where: { $0.categoryID == category.id && $0.amountMinor > 0 }) {
                lines.append("أبرز جهة في تصنيف \(category.name): \(merchant.merchantName).")
            }
        }
        if let previousTotalMinor {
            lines.append("صافي المصروف " + Self.comparisonDirection(current: totalMinor, previous: previousTotalMinor) + ".")
        }
        for category in categories.filter({ $0.amountMinor > 0 }).prefix(8) {
            if let previous = previousCategories?.first(where: { $0.id == category.id }) {
                lines.append("صافي تصنيف \(category.name) " + Self.comparisonDirection(current: category.amountMinor, previous: previous.amountMinor) + ".")
            }
        }
        for merchant in merchants.filter({ $0.amountMinor > 0 }).prefix(5) {
            if let previous = previousMerchants?.first(where: { $0.id == merchant.id }) {
                lines.append("صافي المصروف لدى \(merchant.name) " + Self.comparisonDirection(current: merchant.amountMinor, previous: previous.amountMinor) + ".")
            }
        }
        if pendingCount > 0 { lines.append("توجد حركات تنتظر قرار المستخدم، ولم تدخل المصروف المؤكد.") }
        if confirmedCount == 0 { lines.append("لا توجد حركات مؤكدة في النطاق المحدد.") }
        return lines.joined(separator: "\n")
    }

    /// Exact amounts are selected and formatted by the app, never generated or totalled by the model.
    func answerFacts(for question: String) -> [MadarAIMoneyFact] {
        let q = Self.normalized(question)
        let asksComparison = ["مقارن", "تغير", "السابق", "قبل", "ارتفع", "انخفض"].contains { q.contains(Self.normalized($0)) }
        let merchantChoices = Dictionary((merchants + (previousMerchants ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let matchedMerchant = merchantChoices
            .filter { q.contains(Self.normalized($0.name)) }
            .max { Self.normalized($0.name).count < Self.normalized($1.name).count }
        let scopedCategories = categories.filter { Self.questionScopesCategory(q, name: $0.name, merchantName: matchedMerchant?.name) }
        guard scopedCategories.count <= 1 else { return [] }
        let matchedCategory = scopedCategories.first ?? categories.first { Self.question(q, matches: $0.name) }
        let explicitlyScopedCategory = !scopedCategories.isEmpty
        if let matchedCategory, explicitlyScopedCategory, !Self.asksTopCategory(q),
           Self.asksMerchant(q) || matchedMerchant != nil {
            if Self.asksTopMerchant(q) {
                guard let largest = categoryMerchants.first(where: { $0.categoryID == matchedCategory.id && $0.amountMinor > 0 }) else { return [] }
                if asksComparison {
                    guard previousTotalMinor != nil else { return [] }
                    let previous = previousCategoryMerchants?.first { $0.id == largest.id }?.amountMinor ?? 0
                    return comparisonFacts(
                        id: largest.id,
                        subject: "صافي المصروف لدى \(largest.merchantName) في تصنيف \(largest.categoryName)",
                        currentTitle: "أعلى جهة في تصنيف \(largest.categoryName): \(largest.merchantName) في \(rangeTitle)", current: largest.amountMinor,
                        previousTitle: "صافي \(largest.merchantName) في تصنيف \(largest.categoryName) خلال الفترة المقارنة", previous: previous
                    )
                }
                return [.init(id: largest.id, title: "أعلى جهة في تصنيف \(largest.categoryName): \(largest.merchantName)", amountMinor: largest.amountMinor)]
            }
            guard let matchedMerchant else { return [] }
            let id = matchedCategory.id + "|" + matchedMerchant.id
            let current = categoryMerchants.first { $0.id == id }?.amountMinor ?? 0
            if asksComparison {
                guard previousTotalMinor != nil else { return [] }
                let previous = previousCategoryMerchants?.first { $0.id == id }?.amountMinor ?? 0
                return comparisonFacts(
                    id: id,
                    subject: "صافي المصروف لدى \(matchedMerchant.name) في تصنيف \(matchedCategory.name)",
                    currentTitle: "صافي \(matchedMerchant.name) في تصنيف \(matchedCategory.name) خلال \(rangeTitle)", current: current,
                    previousTitle: "صافي \(matchedMerchant.name) في تصنيف \(matchedCategory.name) خلال الفترة المقارنة", previous: previous
                )
            }
            return [.init(id: id, title: "صافي \(matchedMerchant.name) في تصنيف \(matchedCategory.name)", amountMinor: current)]
        }
        if !Self.asksTopCategory(q), let matchedMerchant {
            let current = merchants.first { $0.id == matchedMerchant.id }?.amountMinor ?? 0
            if asksComparison {
                guard previousTotalMinor != nil else { return [] }
                let previous = previousMerchants?.first { $0.id == matchedMerchant.id }?.amountMinor ?? 0
                return comparisonFacts(
                    id: matchedMerchant.id,
                    subject: "صافي المصروف لدى \(matchedMerchant.name)",
                    currentTitle: "صافي المصروف لدى \(matchedMerchant.name) في \(rangeTitle)", current: current,
                    previousTitle: "صافي المصروف لدى \(matchedMerchant.name) في الفترة المقارنة", previous: previous
                )
            }
            return [.init(id: matchedMerchant.id, title: "صافي المصروف لدى \(matchedMerchant.name)", amountMinor: current)]
        }
        if let matchedCategory {
            if asksComparison {
                guard previousTotalMinor != nil else { return [] }
                let previous = previousCategories?.first { $0.id == matchedCategory.id }?.amountMinor ?? 0
                return comparisonFacts(
                    id: matchedCategory.id,
                    subject: "صافي المصروف في تصنيف \(matchedCategory.name)",
                    currentTitle: "صافي تصنيف \(matchedCategory.name) في \(rangeTitle)", current: matchedCategory.amountMinor,
                    previousTitle: "صافي تصنيف \(matchedCategory.name) في الفترة المقارنة", previous: previous
                )
            }
            return [.init(id: matchedCategory.id, title: "صافي المصروف في تصنيف \(matchedCategory.name)", amountMinor: matchedCategory.amountMinor)]
        }

        if Self.asksTopMerchant(q), let largest = merchants.first(where: { $0.amountMinor > 0 }) {
            if asksComparison {
                guard previousTotalMinor != nil else { return [] }
                let previous = previousMerchants?.first { $0.id == largest.id }?.amountMinor ?? 0
                return comparisonFacts(
                    id: largest.id,
                    subject: "صافي المصروف لدى \(largest.name)",
                    currentTitle: "أعلى جهة صرفًا: \(largest.name) في \(rangeTitle)", current: largest.amountMinor,
                    previousTitle: "صافي المصروف لدى \(largest.name) في الفترة المقارنة", previous: previous
                )
            }
            return [.init(id: largest.id, title: "أعلى جهة صرفًا: \(largest.name)", amountMinor: largest.amountMinor)]
        }

        let asksNamedBreakdown = ["تصنيف", "فئه", "لدى", "عند", "في"].contains { q.contains(Self.normalized($0)) }
        if asksComparison, asksNamedBreakdown { return [] }
        if asksComparison, let previousTotalMinor {
            return comparisonFacts(
                id: "total", subject: "صافي المصروف",
                currentTitle: "صافي المصروف في \(rangeTitle)", current: totalMinor,
                previousTitle: "صافي المصروف في الفترة السابقة", previous: previousTotalMinor
            )
        }

        let asksLargest = ["اكثر", "أكثر", "اكبر", "أكبر", "اعلى", "أعلى", "اين ذهب", "أين ذهب", "وين راح"].contains { q.contains(Self.normalized($0)) }
        if asksLargest, let largest = categories.first(where: { $0.amountMinor > 0 }) {
            return [.init(id: largest.id, title: "أعلى تصنيف في هذا النطاق: \(largest.name)", amountMinor: largest.amountMinor)]
        }

        let asksOverall = ["اجمالي", "إجمالي", "المجموع", "كامل", "كل المصروف", "صافي المصروف"].contains { q.contains(Self.normalized($0)) }
        if asksOverall {
            return [.init(id: "total", title: "صافي المصروف المسجل في هذا النطاق", amountMinor: totalMinor)]
        }
        return []
    }

    private func comparisonFacts(id: String, subject: String,
                                 currentTitle: String, current: Int,
                                 previousTitle: String, previous: Int) -> [MadarAIMoneyFact] {
        let values = [
            MadarAIMoneyFact(id: id, title: currentTitle, amountMinor: current),
            MadarAIMoneyFact(id: id + ".previous", title: previousTitle, amountMinor: previous),
        ]
        let (difference, overflow) = current.subtractingReportingOverflow(previous)
        guard !overflow, let magnitude = Int(exactly: difference.magnitude) else { return values }
        let title: String
        if difference > 0 { title = "زاد \(subject) عن الفترة السابقة" }
        else if difference < 0 { title = "انخفض \(subject) عن الفترة السابقة" }
        else { title = "لم يتغيّر \(subject) عن الفترة السابقة" }
        return values + [.init(id: id + ".change", title: title, amountMinor: magnitude)]
    }

    private static func comparisonDirection(current: Int, previous: Int) -> String {
        if current > previous { "أعلى من الفترة المقارنة" }
        else if current < previous { "أقل من الفترة المقارنة" }
        else { "مماثل للفترة المقارنة" }
    }

    func questionNeedsFigure(_ question: String) -> Bool {
        let q = Self.normalized(question)
        return ["كم", "مبلغ", "اجمالي", "المجموع", "كم صرف", "قيمة"]
            .contains { q.contains(Self.normalized($0)) }
    }

    func questionAsksComparison(_ question: String) -> Bool {
        let q = Self.normalized(question)
        return ["مقارن", "تغير", "السابق", "قبل", "ارتفع", "انخفض"].contains { q.contains(Self.normalized($0)) }
    }

    func questionAsksTopMerchant(_ question: String) -> Bool {
        Self.asksTopMerchant(Self.normalized(question))
    }

    func questionMentionsCategory(_ question: String) -> Bool {
        let q = Self.normalized(question)
        return categories.contains { Self.question(q, matches: $0.name) }
    }

    private static func asksTopMerchant(_ question: String) -> Bool {
        let asksLargest = ["اكثر", "اكبر", "اعلى", "الاعلى"].contains { question.contains(Self.normalized($0)) }
        return asksLargest && asksMerchant(question)
    }

    private static func asksTopCategory(_ question: String) -> Bool {
        let asksLargest = ["اكثر", "اكبر", "اعلى", "الاعلى"].contains { question.contains(Self.normalized($0)) }
        return asksLargest && ["تصنيف", "فئه"].contains { question.contains(Self.normalized($0)) }
    }

    private static func asksMerchant(_ question: String) -> Bool {
        ["جهه", "جهات", "تاجر", "متجر", "عند", "لدى"].contains { question.contains(Self.normalized($0)) }
    }

    private static func questionScopesCategory(_ question: String, name: String, merchantName: String?) -> Bool {
        let category = normalized(name)
        guard !category.isEmpty else { return false }
        let words = question.split(whereSeparator: \.isWhitespace).map(String.init)
        let explicitLabels = Set(["تصنيف", "فئه"])
        let scopeWords = explicitLabels.union(["في", "ضمن", "داخل"])
        for (index, word) in words.enumerated() where scopeWords.contains(word) {
            let scopedName = words.dropFirst(index + 1).joined(separator: " ")
            guard Self.question(scopedName, matches: name) else { continue }
            let namesMerchantInsideScope = merchantName.map { scopedName.contains(normalized($0)) } ?? false
            if namesMerchantInsideScope && !explicitLabels.contains(word) { continue }
            return true
        }
        return words.contains("ب" + category) || category.split(whereSeparator: \.isWhitespace)
            .filter { $0.count >= 3 }.contains { token in
                words.contains(where: { $0.hasPrefix("ب") && String($0.dropFirst()) == token })
            }
    }

    private static func question(_ question: String, matches name: String) -> Bool {
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { return false }
        if question.contains(normalizedName) { return true }
        return normalizedName.split(whereSeparator: { $0.isWhitespace }).contains { token in
            token.count >= 3 && question.contains(token)
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ـ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MoneyAnalysisReadRequest: Sendable {
    let log: MoneyLogReadRequest
    let period: MoneyAnalysisPeriod
    let offset: Int
    let firstWeekday: Int
    let cycleCalendarIdentifier: String
}

@ModelActor private actor MoneyAnalysisReadActor {
    func read(_ request: MoneyAnalysisReadRequest) async throws -> MoneyAnalysisReading? {
        try Task.checkCancellation()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_UI_MONEY_ANALYSIS_READ_FAIL_PERIOD"] == request.period.rawValue {
            throw BackupOperationError.busy
        }
        if let raw = ProcessInfo.processInfo.environment["MADAR_UI_MONEY_ANALYSIS_READ_HOLD_MS"],
           let milliseconds = UInt64(raw), milliseconds > 0 {
            try await Task.sleep(for: .milliseconds(min(5_000, milliseconds)))
        }
        #endif
        try Task.checkCancellation()
        return try MoneyAnalysisReadingBuilder.load(context: modelContext, request: request)
    }
}

enum MoneyAnalysisReadingBuilder {
    static func weekStart(_ day: GregorianDay, request: MoneyAnalysisReadRequest) -> GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = request.log.timeZone
        let leading = (calendar.component(.weekday, from: day.date(in: calendar.timeZone).addingTimeInterval(43_200)) - request.firstWeekday + 7) % 7
        return day.adding(days: -leading)
    }

    static func calendarSpan(_ period: MoneyAnalysisPeriod, today: GregorianDay, offset: Int, request: MoneyAnalysisReadRequest) -> (first: GregorianDay, last: GregorianDay, title: String) {
        let digits = MadarNumberFormatter(style: request.log.numerals)
        if period == .year {
            let year = today.year + offset
            let first = (try? GregorianDay(year: year, month: 1, day: 1)) ?? today, last = (try? GregorianDay(year: year, month: 12, day: 31)) ?? today
            return (first, last, "سنة " + digits.string(year))
        }
        var year = today.year, month = today.month + offset
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        let first = (try? GregorianDay(year: year, month: month, day: 1)) ?? today
        let next = month == 12 ? (try? GregorianDay(year: year + 1, month: 1, day: 1)) : (try? GregorianDay(year: year, month: month + 1, day: 1))
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = .gmt; formatter.dateFormat = "MMMM"
        return (first, (next ?? first.adding(days: 31)).adding(days: -1), formatter.string(from: first.date(in: .gmt).addingTimeInterval(43_200)) + " " + digits.string(year))
    }

    static func cycleMonthName(start: GregorianDay, end: GregorianDay, request: MoneyAnalysisReadRequest) -> String {
        let calendarID: Calendar.Identifier = request.cycleCalendarIdentifier == "hijri" ? .islamicUmmAlQura : .gregorian
        let middle = start.adding(days: MadarCalendarDays.distance(from: start, to: end) / 2).date(in: request.log.timeZone)
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: calendarID); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = request.log.timeZone; formatter.dateFormat = "MMMM"
        return formatter.string(from: middle)
    }

    static func load(context: ModelContext, request: MoneyAnalysisReadRequest) throws -> MoneyAnalysisReading? {
        let period = request.period, offset = request.offset
        let ledger = try MoneyLogReadingBuilder.makeLedger(context: context, request: request.log, retainAllLiveTransactionsForAnalysis: true)
        let today = ledger.today, starts = ledger.starts
        guard let current = starts.lastIndex(where: { $0.1 <= today }) else { return nil }
        func span(_ index: Int) -> (first: GregorianDay, last: GregorianDay, length: Int)? {
            guard starts.indices.contains(index), let reading = ledger.reading(of: starts[index].0) else { return nil }
            let first = starts[index].1, length = max(1, reading.input.expectedLengthDays)
            var last = index + 1 < starts.count ? starts[index + 1].1.adding(days: -1) : first.adding(days: length - 1)
            if index + 1 == starts.count && starts[index].0.end == nil { last = max(last, today) }
            return (first, max(first, last), length)
        }
        func range(_ first: GregorianDay, _ last: GregorianDay) -> [GregorianDay] { (0...max(0, MadarCalendarDays.distance(from: first, to: last))).map { first.adding(days: $0) } }

        // The period.
        let target: Int, first: GregorianDay, last: GregorianDay, title: String, canGoBack: Bool
        switch period {
        case .cycle:
            target = max(0, current + min(0, offset))
            guard let s = span(target) else { return nil }
            first = s.first; last = s.last; title = "دورة " + cycleMonthName(start: s.first, end: s.last.adding(days: 1), request: request)
            canGoBack = target > 0 && span(target - 1) != nil
        case .week:
            target = min(0, offset)
            first = weekStart(today, request: request).adding(days: 7 * target); last = first.adding(days: 6)
            title = target == 0 ? "هذا الأسبوع" : target == -1 ? "الأسبوع الماضي" : "أسبوع"
            canGoBack = starts[0].1 < first
        case .month, .year:
            target = min(0, offset)
            let span = calendarSpan(period, today: today, offset: target, request: request)
            first = span.first; last = span.last; title = span.title
            canGoBack = starts[0].1 < first
        }
        let days = ledger.days(range(first, last))
        let elapsed = days.filter { $0.day <= today }
        let known = elapsed.filter { $0.dailyMinor != nil }
        let spent = elapsed.reduce(0) { $0 + $1.spentMinor }, allowance = known.reduce(0) { $0 + ($1.dailyMinor ?? 0) }
        let running = last >= today

        // Like for like: the earlier period's first N days against this period's N elapsed days.
        var comparison: MoneyAnalysisComparison?
        let previous: (first: GregorianDay, last: GregorianDay, name: String)? = switch period {
            case .cycle: span(target - 1).map { ($0.first, $0.last, "دورة " + cycleMonthName(start: $0.first, end: $0.last.adding(days: 1), request: request)) }
            case .week: (first.adding(days: -7), first.adding(days: -1), target == 0 ? "الأسبوع الماضي" : "الأسبوع الذي قبله")
            case .month, .year: { let s = calendarSpan(period, today: today, offset: target - 1, request: request); return (s.first, s.last, s.title) }()
        }
        if let previous, !elapsed.isEmpty {
            let aligned = Array(ledger.days(range(previous.first, previous.last)).prefix(elapsed.count))
            if aligned.count == elapsed.count, aligned.allSatisfy({ $0.dailyMinor != nil }),
               let percent = AnalysisEngine.percentChange(currentMinor: spent, previousMinor: aligned.reduce(0) { $0 + $1.spentMinor }) {
                comparison = .init(percent: percent, label: running ? "عن الأيام نفسها من " + previous.name : "عن " + previous.name)
            }
        }

        // Categories and merchants: V10's definition, on the period's movements.
        let allocations = ledger.allocations.filter { ["spend", "refund"].contains($0.kind) }
        let charges = Dictionary(grouping: allocations.compactMap { a in a.transactionID.map { ($0, a.amountMinor) } }, by: \.0).mapValues { -$0.reduce(0) { $0 + $1.1 } }
        let liveTransactions = try ledger.allLiveTransactionsForAnalysis ?? ledger.repo.confirmedTransactions()
        let confirmed = liveTransactions.filter { $0.reviewState == "ok" }
        let byID = Dictionary(confirmed.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [MoneyTransaction] = []
        rows.reserveCapacity(confirmed.count)
        for (index, row) in confirmed.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            switch period {
            case .cycle:
                if row.cycleID == starts[target].0.id { rows.append(row) }
            case .week, .month, .year:
                let key = row.kind == "refund" ? row.relatedTransactionID.flatMap { byID[$0]?.dayKey } ?? row.dayKey : row.dayKey
                guard let day = try? GregorianDay(key), day >= first, day <= last else { continue }
                rows.append(row)
            }
        }
        let ordered = ledger.categories.filter { $0.mergedInto == nil }.sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let limits = try context.fetch(FetchDescriptor<CategoryLimit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let latestLimitByCategory = limits.reduce(into: [UUID: CategoryLimit]()) { latest, limit in
            guard let categoryID = limit.categoryID else { return }
            guard let current = latest[categoryID] else { latest[categoryID] = limit; return }
            if current.updatedAt < limit.updatedAt { latest[categoryID] = limit }
        }
        func mode(_ category: UUID) -> CategoryLimitMode? {
            guard let limit = latestLimitByCategory[category] else { return nil }
            switch limit.mode {
            case "fixed": return .fixed(limitMinor: limit.limitMinor)
            case "percent": return .percent(basisPoints: limit.percentBp ?? 0, base: limit.base == "allowance" ? .allowance : .income)
            default: return nil
            }
        }
        func cycleLimit(_ category: UUID, _ index: Int) -> (limit: Int, length: Int)? {
            guard let mode = mode(category), let reading = ledger.reading(of: starts[index].0) else { return nil }
            let length = max(1, reading.input.expectedLengthDays)
            return LimitEngine.effectiveLimit(mode, cycleIncomeMinor: starts[index].0.incomeMinor, cycleAllowanceMinor: CycleEngine.accruedDaily(through: length, reading.input)).map { ($0, length) }
        }
        func cap(_ category: UUID) -> Int? {
            switch period {
            case .cycle: return cycleLimit(category, target)?.limit
            case .week, .month, .year:
                // Each day takes its own cycle's even share of that cycle's limit.
                var total: Int?
                for index in starts.indices {
                    guard let s = span(index), s.last >= first, s.first <= last, let limit = cycleLimit(category, index) else { continue }
                    let from = MadarCalendarDays.distance(from: s.first, to: max(first, s.first)) + 1, through = MadarCalendarDays.distance(from: s.first, to: min(last, s.last)) + 1
                    total = (total ?? 0) + AnalysisEngine.limitShare(limitMinor: limit.limit, cycleLengthDays: limit.length, fromDay: from, throughDay: through)
                }
                return total
            }
        }
        let filed = Set(ordered.map(\.id))
        var categoryTotals: [UUID: Int] = [:], loose = 0, merchantTotals: [String: (Int, Int)] = [:]
        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let charge = charges[row.id] ?? 0
            if let categoryID = row.categoryID, filed.contains(categoryID) { categoryTotals[categoryID, default: 0] += charge }
            else { loose += charge }
            guard let name = row.merchant ?? row.counterparty, charge != 0 else { continue }
            merchantTotals[name, default: (0, 0)].0 += charge
            if charge > 0 { merchantTotals[name, default: (0, 0)].1 += 1 }
        }
        var categories: [MoneyAnalysisCategory] = ordered.enumerated().compactMap { index, category in
            let spent = categoryTotals[category.id, default: 0]
            guard spent != 0 else { return nil }
            return .init(id: category.id.uuidString, name: category.name, spentMinor: spent, capMinor: cap(category.id), tint: index)
        }
        if loose != 0 { categories.append(.init(id: "none", name: "بلا تصنيف", spentMinor: loose, capMinor: nil, tint: nil)) }
        categories.sort { $0.spentMinor == $1.spentMinor ? $0.name < $1.name : $0.spentMinor > $1.spentMinor }

        var top: [MoneyAnalysisMerchant] = []
        for (name, value) in merchantTotals where value.0 > 0 { top.append(MoneyAnalysisMerchant(name: name, amountMinor: value.0, count: value.1)) }
        top.sort { (a: MoneyAnalysisMerchant, b: MoneyAnalysisMerchant) -> Bool in a.amountMinor == b.amountMinor ? a.name < b.name : a.amountMinor > b.amountMinor }

        let judged = elapsed.filter { $0.within == .met || $0.within == .missed }
        let remaining = period == .cycle && running ? days.filter { $0.day > today }.count : 0
        return .init(period: period, offset: period == .cycle ? target - current : target, canGoBack: canGoBack, title: title, first: first, last: last, today: today,
                     days: days, spentMinor: spent, allowanceMinor: allowance, running: running, comparison: comparison,
                     categories: categories, merchants: Array(top.prefix(5)), metDays: judged.filter { $0.within == .met }.count, judgedDays: judged.count,
                     pendingDays: elapsed.filter { $0.within == .pending }.count,
                     pace: AnalysisEngine.pace(spentMinor: known.reduce(0) { $0 + $1.spentMinor }, allowanceMinor: allowance, knownDays: known.count, remainingDays: remaining))
    }

}

extension AppMoneyService {
    /// A read-only summary using the same confirmed spend/refund allocations as M5-V14.
    /// Refunds stay on their original purchase day, matching the existing report.
    func aiSnapshot(from first: GregorianDay?, through requestedLast: GregorianDay?, title: String,
                    comparing comparison: (GregorianDay, GregorianDay)? = nil) throws -> MadarAIMoneySnapshot? {
        let ledger = try moneyLedger(at: app.prayerNow())
        let byID = Dictionary(ledger.transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func effectiveDay(_ row: MoneyTransaction) -> GregorianDay? {
            let key = row.kind == "refund" ? row.relatedTransactionID.flatMap { byID[$0]?.dayKey } ?? row.dayKey : row.dayKey
            return try? GregorianDay(key)
        }
        let last = requestedLast ?? ledger.today
        let historyDays = ledger.transactions.compactMap(effectiveDay).filter { $0 <= last }
        guard let first = first ?? historyDays.min() else { return nil }
        func inRange(_ row: MoneyTransaction, _ range: (GregorianDay, GregorianDay)) -> Bool {
            guard let day = effectiveDay(row) else { return false }
            return day >= range.0 && day <= range.1
        }
        let rangeRows = ledger.transactions.filter { inRange($0, (first, last)) }
        let confirmed = rangeRows.filter { $0.reviewState == "ok" }
        let activeCategories = Dictionary(ledger.categories.filter { $0.mergedInto == nil }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        typealias CategoryTotals = [String: (name: String, total: Int)]
        typealias CategoryMerchantTotals = [String: (categoryID: String, categoryName: String, merchantID: String, merchantName: String, total: Int)]
        typealias Aggregates = (total: Int, categories: CategoryTotals, merchants: [String: Int], categoryMerchants: CategoryMerchantTotals)
        func aggregate(_ rows: [MoneyTransaction]) -> Aggregates {
            let rowIDs = Set(rows.map(\.id))
            var parts: [UUID: [Allocation]] = [:]
            for allocation in ledger.allocations where ["spend", "refund"].contains(allocation.kind) {
                guard let id = allocation.transactionID, rowIDs.contains(id) else { continue }
                parts[id, default: []].append(allocation)
            }
            var categoryTotals: CategoryTotals = [:]
            for (id, name) in activeCategories {
                categoryTotals["category." + id.uuidString] = (name, 0)
            }
            categoryTotals["category.uncategorized"] = ("بلا تصنيف", 0)
            var merchantTotals: [String: Int] = [:]
            var categoryMerchantTotals: CategoryMerchantTotals = [:]
            var total = 0
            for row in rows {
                let value = -(parts[row.id] ?? []).reduce(0) { $0 + $1.amountMinor }
                total += value
                let categoryID = row.categoryID.flatMap { activeCategories[$0] == nil ? nil : $0 }
                let key = categoryID.map { "category." + $0.uuidString } ?? "category.uncategorized"
                let name = categoryID.flatMap { activeCategories[$0] } ?? "بلا تصنيف"
                categoryTotals[key, default: (name, 0)].total += value
                if let merchant = row.merchant ?? row.counterparty, !merchant.isEmpty {
                    merchantTotals[merchant, default: 0] += value
                    let merchantID = "merchant." + merchant
                    let pairID = key + "|" + merchantID
                    categoryMerchantTotals[pairID, default: (key, name, merchantID, merchant, 0)].total += value
                }
            }
            return (total, categoryTotals, merchantTotals, categoryMerchantTotals)
        }
        func categoryMetrics(_ totals: CategoryTotals) -> [MadarAIMoneyMetric] {
            totals.map { id, value in
                MadarAIMoneyMetric(id: id, name: value.name, amountMinor: value.total, kind: .category)
            }.sorted { $0.amountMinor == $1.amountMinor ? $0.name < $1.name : $0.amountMinor > $1.amountMinor }
        }
        func merchantMetrics(_ totals: [String: Int]) -> [MadarAIMoneyMetric] {
            totals.map { name, value in
                MadarAIMoneyMetric(id: "merchant." + name, name: name, amountMinor: value, kind: .merchant)
            }.sorted { $0.amountMinor == $1.amountMinor ? $0.name < $1.name : $0.amountMinor > $1.amountMinor }
        }
        func categoryMerchantMetrics(_ totals: CategoryMerchantTotals) -> [MadarAIMoneyCategoryMerchant] {
            totals.map { id, value in
                MadarAIMoneyCategoryMerchant(id: id, categoryID: value.categoryID, categoryName: value.categoryName,
                                             merchantID: value.merchantID, merchantName: value.merchantName,
                                             amountMinor: value.total)
            }.sorted { $0.amountMinor == $1.amountMinor ? $0.merchantName < $1.merchantName : $0.amountMinor > $1.amountMinor }
        }
        let current = aggregate(confirmed)
        let categories = categoryMetrics(current.categories)
        let previous: Aggregates? = comparison.map { range in
            aggregate(ledger.transactions.filter { inRange($0, range) && $0.reviewState == "ok" })
        }
        let merchants = merchantMetrics(current.merchants)
        let previousCategories = previous.map { categoryMetrics($0.categories) }
        let previousMerchants = previous.map { merchantMetrics($0.merchants) }
        let categoryMerchants = categoryMerchantMetrics(current.categoryMerchants)
        let previousCategoryMerchants = previous.map { categoryMerchantMetrics($0.categoryMerchants) }
        return .init(firstDayKey: first.description, lastDayKey: last.description, rangeTitle: title,
                     confirmedCount: confirmed.count, pendingCount: rangeRows.count - confirmed.count,
                     totalMinor: current.total, categories: categories, merchants: merchants,
                     previousTotalMinor: previous?.total, previousCategories: previousCategories,
                     previousMerchants: previousMerchants, categoryMerchants: categoryMerchants,
                     previousCategoryMerchants: previousCategoryMerchants)
    }
}

extension AppMoneyService {
    var analysisFirstWeekday: Int { app.string("core.weekStart") == "sunday" ? 1 : 7 }
    func analysisWeekStart(_ day: GregorianDay) -> GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        let leading = (calendar.component(.weekday, from: day.date(in: calendar.timeZone).addingTimeInterval(43200)) - analysisFirstWeekday + 7) % 7
        return day.adding(days: -leading)
    }

    /// nil when there is no cycle yet: the screen then explains where its numbers will come from.
    func loadAnalysis(period: MoneyAnalysisPeriod, offset: Int = 0, at instant: Date? = nil) throws -> MoneyAnalysisReading? {
        try requireReadableStore()
        let now = instant ?? app.prayerNow(), request = analysisReadRequest(period: period, offset: offset, at: now)
        return try MoneyAnalysisReadingBuilder.load(context: ModelContext(app.container), request: request)
    }

    func loadAnalysisOffMain(period: MoneyAnalysisPeriod, offset: Int = 0, at instant: Date? = nil) async throws -> MoneyAnalysisReading? {
        let session = app, now = instant ?? app.prayerNow()
        for attempt in 0..<4 {
            do {
                try requireReadableStore()
                guard !session.settingsWriteInProgress else { throw BackupOperationError.busy }
                let revision = session.prayerRevision, generation = session.storeGeneration, container = session.container
                let request = analysisReadRequest(period: period, offset: offset, at: now)
                let readTask = Task.detached(priority: .userInitiated) {
                    let worker = MoneyAnalysisReadActor(modelContainer: container)
                    return try await worker.read(request)
                }
                let reading = try await withTaskCancellationHandler { try await readTask.value } onCancel: { readTask.cancel() }
                try Task.checkCancellation()
                try requireReadableStore()
                guard !session.settingsWriteInProgress, session.prayerRevision == revision,
                      session.storeGeneration == generation, session.container === container else { throw CancellationError() }
                return reading
            } catch is CancellationError {
                try Task.checkCancellation()
                guard attempt < 3 else { throw CancellationError() }
            } catch BackupOperationError.busy where attempt < 3 {
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BackupOperationError.busy
    }

    func analysisReadRequest(period: MoneyAnalysisPeriod, offset: Int, at now: Date) -> MoneyAnalysisReadRequest {
        .init(log: logReadRequest(at: now), period: period, offset: offset,
              firstWeekday: analysisFirstWeekday, cycleCalendarIdentifier: app.string("mal.cycleCalendar"))
    }

    /// The Gregorian month or year `offset` steps back from today's: «نوفمبر ٢٠٢٦»، «سنة ٢٠٢٦».
    func calendarSpan(_ period: MoneyAnalysisPeriod, today: GregorianDay, offset: Int) -> (first: GregorianDay, last: GregorianDay, title: String) {
        if period == .year {
            let year = today.year + offset
            let first = (try? GregorianDay(year: year, month: 1, day: 1)) ?? today, last = (try? GregorianDay(year: year, month: 12, day: 31)) ?? today
            return (first, last, "سنة " + digits.string(year))
        }
        var year = today.year, month = today.month + offset
        while month < 1 { month += 12; year -= 1 }
        let first = (try? GregorianDay(year: year, month: month, day: 1)) ?? today
        let next = month == 12 ? (try? GregorianDay(year: year + 1, month: 1, day: 1)) : (try? GregorianDay(year: year, month: month + 1, day: 1))
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = .gmt; formatter.dateFormat = "MMMM"
        return (first, (next ?? first.adding(days: 31)).adding(days: -1), formatter.string(from: first.date(in: .gmt).addingTimeInterval(43200)) + " " + digits.string(year))
    }

    /// «٢١ مرة»، «مرتان»، «٣ مرات».
    func times(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.times", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
    /// «٢٤ يومًا»: whole days as a count (not «بعد/خلال»).
    func dayCount(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.dayCount", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
}
