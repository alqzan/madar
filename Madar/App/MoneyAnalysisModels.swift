import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// `mal.analysisDefault`: the two periods the spec names («التقرير المخطوط، الدورة والأسبوع»).
enum MoneyAnalysisPeriod: String, CaseIterable, Identifiable {
    case cycle, week
    var id: String { rawValue }
}

struct MoneyAnalysisCategory: Identifiable, Equatable {
    var id: String
    var name: String
    /// V10's one definition: − Σ spend/refund allocations of the confirmed movements in this category for the period.
    var spentMinor: Int
    /// The cycle limit (cycle view) or its even share over the week's days (week view); nil = no limit.
    var capMinor: Int?
    /// Index in category order, so a category keeps the binding colour it has on its shelf; nil = uncategorized.
    var tint: Int?
}

struct MoneyAnalysisMerchant: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var amountMinor: Int
    var count: Int
}

struct MoneyAnalysisComparison: Equatable {
    var percent: Int
    var label: String
}

struct MoneyAnalysisReading {
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

extension AppMoneyService {
    var analysisFirstWeekday: Int { app.string("core.weekStart") == "sunday" ? 1 : 7 }
    func analysisWeekStart(_ day: GregorianDay) -> GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        let leading = (calendar.component(.weekday, from: day.date(in: calendar.timeZone).addingTimeInterval(43200)) - analysisFirstWeekday + 7) % 7
        return day.adding(days: -leading)
    }

    /// nil when there is no cycle yet: the screen then explains where its numbers will come from.
    func loadAnalysis(period: MoneyAnalysisPeriod, offset: Int = 0, at instant: Date? = nil) throws -> MoneyAnalysisReading? {
        let ledger = try moneyLedger(at: instant ?? app.prayerNow()), today = ledger.today, starts = ledger.starts
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
            first = s.first; last = s.last; title = "دورة " + cycleMonthName(start: s.first, end: s.last.adding(days: 1))
            canGoBack = target > 0 && span(target - 1) != nil
        case .week:
            target = min(0, offset)
            first = analysisWeekStart(today).adding(days: 7 * target); last = first.adding(days: 6)
            title = target == 0 ? "هذا الأسبوع" : target == -1 ? "الأسبوع الماضي" : "أسبوع"
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
            case .cycle: span(target - 1).map { ($0.first, $0.last, "دورة " + cycleMonthName(start: $0.first, end: $0.last.adding(days: 1))) }
            case .week: (first.adding(days: -7), first.adding(days: -1), target == 0 ? "الأسبوع الماضي" : "الأسبوع الذي قبله")
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
        let confirmed = try ledger.repo.confirmedTransactions()
        let byID = Dictionary(confirmed.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows: [MoneyTransaction] = switch period {
            case .cycle: confirmed.filter { $0.cycleID != nil && $0.cycleID == starts[target].0.id }
            case .week: confirmed.filter { row in
                let key = row.kind == "refund" ? row.relatedTransactionID.flatMap { byID[$0]?.dayKey } ?? row.dayKey : row.dayKey
                guard let day = try? GregorianDay(key) else { return false }
                return day >= first && day <= last
            }
        }
        let ordered = ledger.categories.filter { $0.mergedInto == nil }.sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let limits = try ModelContext(app.container).fetch(FetchDescriptor<CategoryLimit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        func mode(_ category: UUID) -> CategoryLimitMode? {
            let limit = limits.filter { $0.categoryID == category }.max { $0.updatedAt < $1.updatedAt }
            return switch limit?.mode {
                case "fixed": .fixed(limitMinor: limit?.limitMinor ?? 0)
                case "percent": .percent(basisPoints: limit?.percentBp ?? 0, base: limit?.base == "allowance" ? .allowance : .income)
                default: nil
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
            case .week:
                // Each week day takes its own cycle's even share of that cycle's limit.
                var total: Int?
                for index in starts.indices {
                    guard let s = span(index), s.last >= first, s.first <= last, let limit = cycleLimit(category, index) else { continue }
                    let from = MadarCalendarDays.distance(from: s.first, to: max(first, s.first)) + 1, through = MadarCalendarDays.distance(from: s.first, to: min(last, s.last)) + 1
                    total = (total ?? 0) + AnalysisEngine.limitShare(limitMinor: limit.limit, cycleLengthDays: limit.length, fromDay: from, throughDay: through)
                }
                return total
            }
        }
        var categories: [MoneyAnalysisCategory] = ordered.enumerated().compactMap { index, category in
            let spent = rows.filter { $0.categoryID == category.id }.reduce(0) { $0 + (charges[$1.id] ?? 0) }
            guard spent != 0 else { return nil }
            return .init(id: category.id.uuidString, name: category.name, spentMinor: spent, capMinor: cap(category.id), tint: index)
        }
        let filed = Set(ordered.map(\.id))
        let loose = rows.filter { $0.categoryID.map { !filed.contains($0) } ?? true }.reduce(0) { $0 + (charges[$1.id] ?? 0) }
        if loose != 0 { categories.append(.init(id: "none", name: "بلا تصنيف", spentMinor: loose, capMinor: nil, tint: nil)) }
        categories.sort { $0.spentMinor == $1.spentMinor ? $0.name < $1.name : $0.spentMinor > $1.spentMinor }

        var merchants: [String: (Int, Int)] = [:]
        for row in rows {
            guard let name = row.merchant ?? row.counterparty, let charge = charges[row.id], charge != 0 else { continue }
            merchants[name, default: (0, 0)].0 += charge
            if charge > 0 { merchants[name, default: (0, 0)].1 += 1 }
        }
        var top: [MoneyAnalysisMerchant] = []
        for (name, value) in merchants where value.0 > 0 { top.append(MoneyAnalysisMerchant(name: name, amountMinor: value.0, count: value.1)) }
        top.sort { (a: MoneyAnalysisMerchant, b: MoneyAnalysisMerchant) -> Bool in a.amountMinor == b.amountMinor ? a.name < b.name : a.amountMinor > b.amountMinor }

        let judged = elapsed.filter { $0.within == .met || $0.within == .missed }
        let remaining = period == .cycle && running ? days.filter { $0.day > today }.count : 0
        return .init(period: period, offset: period == .cycle ? target - current : target, canGoBack: canGoBack, title: title, first: first, last: last, today: today,
                     days: days, spentMinor: spent, allowanceMinor: allowance, running: running, comparison: comparison,
                     categories: categories, merchants: Array(top.prefix(5)), metDays: judged.filter { $0.within == .met }.count, judgedDays: judged.count,
                     pendingDays: elapsed.filter { $0.within == .pending }.count,
                     pace: AnalysisEngine.pace(spentMinor: known.reduce(0) { $0 + $1.spentMinor }, allowanceMinor: allowance, knownDays: known.count, remainingDays: remaining))
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
