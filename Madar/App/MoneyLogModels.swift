import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyLogMovement: Identifiable {
    var id: UUID
    var day: GregorianDay
    var at: Date
    var title: String
    var category: String
    var payment: String
    var kind: String
    var cardID: UUID?
    var cash: Bool
    var bnpl: Bool
    var amountMinor: Int
    var confirmed: Bool
    var budgetLabel: String
    var detail: MoneySourceDetail
}
struct MoneyLogDay: Identifiable {
    var id: String { day.description }
    var day: GregorianDay
    var dailyMinor: Int?
    var spentMinor: Int
    var otherMinor: Int
    var cashOutMinor: Int?
    var pending: Int
    var within: WithinDay? { dailyMinor.map { WithinDayEngine.evaluate(dailySpentMinor: spentMinor, dailyMinor: $0, hasUnresolvedMessage: pending > 0) } }
}
/// The confirmed per-day budget ledger behind the log and the analysis: one definition of a day's
/// «صرف من يومك» and «يومك». Read-only; nothing here writes.
@MainActor final class MoneyLedger {
    let now: Date
    let today: GregorianDay
    let repo: MoneyRepository
    let movements: [MoneyLogMovement]
    /// The rows the ledger kept (owned accounts and cards only), confirmed or not.
    let transactions: [MoneyTransaction]
    let allocations: [Allocation]
    let categories: [MadarData.Category]
    let cards: [Card]
    let pending: [String: Int]
    /// Cycles with a policy, by their first stored day (never recomputed).
    let starts: [(Cycle, GregorianDay)]
    private let spent: [String: Int], other: [String: Int], cashOut: [String: Int], unknownCash: Set<String>, drips: [String: Int]
    private var cache: [UUID: MoneyCycleReading] = [:]
    private var attempted: Set<UUID> = []
    init(now: Date, today: GregorianDay, repo: MoneyRepository, movements: [MoneyLogMovement], transactions: [MoneyTransaction], allocations: [Allocation],
         categories: [MadarData.Category], cards: [Card], pending: [String: Int], starts: [(Cycle, GregorianDay)],
         spent: [String: Int], other: [String: Int], cashOut: [String: Int], unknownCash: Set<String>, drips: [String: Int]) {
        self.now = now; self.today = today; self.repo = repo; self.movements = movements; self.transactions = transactions; self.allocations = allocations
        self.categories = categories; self.cards = cards; self.pending = pending; self.starts = starts
        self.spent = spent; self.other = other; self.cashOut = cashOut; self.unknownCash = unknownCash; self.drips = drips
    }
    /// The cycle reading as it stood on its last day, or now for the open cycle.
    func reading(of cycle: Cycle) -> MoneyCycleReading? {
        if !attempted.contains(cycle.id) {
            attempted.insert(cycle.id)
            let sample = cycle.end.map { min(now, $0.addingTimeInterval(-1)) } ?? now
            cache[cycle.id] = try? repo.cycle(at: sample)
        }
        return cache[cycle.id]
    }
    func days(_ list: [GregorianDay]) -> [MoneyLogDay] {
        list.map { day in
            var allowance: Int?
            if day <= today, let (cycle, first) = starts.last(where: { $0.1 <= day }) {
                if let reading = reading(of: cycle), cycle.end == nil || day <= reading.today {
                    let index = MadarCalendarDays.distance(from: first, to: day) + 1
                    allowance = max(0, CycleEngine.day(index, reading.input).allowanceMinor - (drips[cycle.id.uuidString + ":" + day.description] ?? 0))
                }
            }
            return .init(day: day, dailyMinor: allowance, spentMinor: spent[day.description] ?? 0, otherMinor: other[day.description] ?? 0,
                cashOutMinor: unknownCash.contains(day.description) ? nil : cashOut[day.description] ?? 0, pending: pending[day.description] ?? 0)
        }
    }
}
struct MoneyLogFilter: Identifiable {
    var id: String
    var title: String
}
struct MoneyLogReading {
    var today: GregorianDay
    var monthStart: GregorianDay
    var days: [MoneyLogDay]
    var arcadeDays: [MoneyLogDay]
    var monthStarts: [GregorianDay]
    var movements: [MoneyLogMovement]
    var filters: [MoneyLogFilter]
    var neutralTransfersMinor: Int
}
extension AppMoneyService {
    var logCalendar: MadarCalendarDays { .init(zone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, offset: Int(app.number("core.hijriOffset"))) }
    func logMonthStart(_ day: GregorianDay) -> GregorianDay {
        if app.string("core.firstCalendar") != "gregorian" { return logCalendar.hijriMonthStart(containing: day) }
        return (try? GregorianDay(year: day.year, month: day.month, day: 1)) ?? day
    }
    func logMonthDays(_ anchor: GregorianDay) -> [GregorianDay] {
        let start = logMonthStart(anchor), length: Int
        if app.string("core.firstCalendar") == "gregorian" {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
            length = calendar.range(of: .day, in: .month, for: start.date(in: calendar.timeZone))?.count ?? 30
        } else { length = logCalendar.hijriMonthLength(containing: anchor) }
        return (0..<length).map { start.adding(days: $0) }
    }
    func logMonthLabels(_ start: GregorianDay) -> MadarDateLabels {
        let end = logMonthDays(start).last ?? start
        let first = app.dateLabels(start), last = app.dateLabels(end)
        let primary = first.primary.split(separator: " ").dropFirst().joined(separator: " ")
        let a = first.secondary.split(separator: " ").dropFirst().joined(separator: " "), b = last.secondary.split(separator: " ").dropFirst().joined(separator: " ")
        return .init(primary: primary, secondary: a == b ? a : a + " – " + b)
    }
    func loadLog(month: GregorianDay? = nil, at instant: Date? = nil) throws -> MoneyLogReading {
        let ledger = try moneyLedger(at: instant ?? app.prayerNow()), today = ledger.today, movements = ledger.movements
        let start = logMonthStart(month ?? today), days = logMonthDays(start)
        let readings = ledger.days((-6..<(days.count + 6)).map { start.adding(days: $0) })
        var months = Set(movements.map { logMonthStart($0.day) }); months.insert(logMonthStart(today)); months.insert(logMonthStart(logMonthStart(today).adding(days: -1)))
        for key in ledger.pending.keys { if let day = try? GregorianDay(key) { months.insert(logMonthStart(day)) } }
        var filters = [MoneyLogFilter(id: "all", title: "الكل")]
        if movements.contains(where: \.cash) { filters.append(.init(id: "cash", title: "النقد")) }
        for card in ledger.cards where movements.contains(where: { $0.cardID == card.id }) { filters.append(.init(id: card.id.uuidString, title: card.name)) }
        if movements.contains(where: \.bnpl) { filters.append(.init(id: "bnpl", title: "الأقساط")) }
        if movements.contains(where: { ["transfer", "cardPayment"].contains($0.kind) }) { filters.append(.init(id: "transfers", title: "تحويلات")) }
        let monthDays = readings.filter { $0.day >= start && $0.day <= days.last! }
        let neutral = movements.filter { $0.confirmed && $0.day >= start && $0.day <= days.last! && $0.budgetLabel == "محايد لليومية" && ["transfer", "cardPayment", "repayment"].contains($0.kind) }.reduce(0) { $0 + $1.amountMinor }
        return .init(today: today, monthStart: start, days: monthDays, arcadeDays: readings, monthStarts: months.sorted(by: >), movements: movements.sorted { $0.at > $1.at }, filters: filters, neutralTransfersMinor: neutral)
    }
    func moneyLedger(at now: Date) throws -> MoneyLedger {
        _ = try load(at: now) // same store/authentication boundary as the home
        let context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let tx = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let byID = Dictionary(tx.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let parts = Dictionary(grouping: allocations, by: \.transactionID)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        var spent: [String: Int] = [:], other: [String: Int] = [:], cashOut: [String: Int] = [:], unknownCash: Set<String> = [], pending: [String: Int] = [:]
        var movements: [MoneyLogMovement] = [], kept: [MoneyTransaction] = []
        let owned = Set(accounts.filter { $0.ownership == "mine" && $0.tracked }.map(\.id))
        for row in tx {
            if let card = cards.first(where: { $0.id == row.cardID }), let account = card.accountID, !owned.contains(account) { continue }
            let linked = [row.fromAccountID, row.toAccountID].compactMap { $0 }
            if !linked.isEmpty && !linked.contains(where: owned.contains) { continue }
            guard let day = try? GregorianDay(row.dayKey) else { continue }
            kept.append(row)
            let confirmed = row.reviewState == "ok", effect = try? repo.effect(of: row)
            let original = row.kind == "refund" ? row.relatedTransactionID.flatMap { byID[$0] } : nil
            let budgetDay = original?.dayKey ?? row.dayKey
            let ownParts = parts[row.id] ?? []
            if confirmed {
                let budgetParts = ownParts.filter { ["spend", "refund", "adjust", "offset"].contains($0.kind) }
                spent[budgetDay, default: 0] -= budgetParts.filter { $0.target == "daily" }.reduce(0) { $0 + $1.amountMinor }
                other[budgetDay, default: 0] -= budgetParts.filter { $0.target != "daily" }.reduce(0) { $0 + $1.amountMinor }
                if row.ignoredFromBudget {
                    let charge = (try? repo.effect(of: row, includingExcluded: true))?.budgetChargeMinor ?? 0
                    other[budgetDay, default: 0] += charge
                }
                if let effect { cashOut[row.dayKey, default: 0] += max(0, -effect.cashMinor) }
                else { unknownCash.insert(row.dayKey) }
            } else { pending[row.dayKey, default: 0] += 1 }
            let title = row.merchant ?? row.counterparty ?? moneyKindLabel(row.kind)
            let category = categories.first { $0.id == row.categoryID }?.name ?? moneyKindLabel(row.kind)
            let payment = cards.first { $0.id == row.cardID }?.name ?? accounts.first { $0.id == row.fromAccountID || $0.id == row.toAccountID }?.name ?? "طريقة الدفع غير معروفة"
            let budgetLabel = !confirmed ? "ينتظر قرارك" : row.ignoredFromBudget ? "خارج الميزانية" : row.kind == "refund" ? "عاد إلى يوم الأصل" : ["cardPayment", "repayment", "income", "salary", "cashback"].contains(row.kind) || effect?.budgetChargeMinor == 0 ? "محايد لليومية" : ownParts.contains { $0.target == "daily" } ? "من يومك" : ownParts.isEmpty ? "التخصيص غير مكتمل" : "من المظاريف"
            let explanation = !confirmed ? "هذه حركة تنتظر قرارك؛ لم تدخل الأرقام المؤكدة بعد." : "حركة مؤكّدة: " + budgetLabel + ". " + (row.kind == "cardPayment" ? "السداد تحويل ينقص النقد والدين، ولا يخصم اليومية مرة أخرى." : "التخصيصات الفعلية هي مصدر صرف اليومية والمظاريف.")
            var detail = MoneySourceDetail(id: row.id.uuidString, title: title, amountMinor: row.homeAmountMinor, explanation: explanation, message: messages.first { $0.id == row.messageID }?.text, date: day)
            if let original, let originalDay = try? GregorianDay(original.dayKey) { detail.explanation += " الرد يعود إلى يوم الأصل: " + app.dateLabels(originalDay).combined + "." }
            movements.append(.init(id: row.id, day: day, at: row.eventAt, title: title, category: category, payment: payment, kind: row.kind, cardID: row.cardID,
                cash: accounts.contains { $0.kind == "cash" && $0.id == row.fromAccountID }, bnpl: row.method == "bnpl" || row.kind == "repayment", amountMinor: row.homeAmountMinor,
                confirmed: confirmed, budgetLabel: budgetLabel, detail: detail))
        }
        // A message without a draft still leaves its day pending; never infer it was spending.
        let drafted = Set(tx.compactMap(\.messageID))
        for message in messages where ["needsLook", "possibleDuplicate"].contains(message.status) && !drafted.contains(message.id) {
            if let day = try? DiaryLineRenderer.today(context: context, now: message.receivedAt) { pending[day.description, default: 0] += 1 }
        }
        let policies = try context.fetch(FetchDescriptor<CyclePolicy>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.start <= now }
        let starts = cycles.compactMap { cycle -> (Cycle, GregorianDay)? in
            guard let first = policies.filter({ $0.cycleID == cycle.id }).map(\.effectiveFromDayKey).min(), let day = try? GregorianDay(first) else { return nil }; return (cycle, day)
        }.sorted { $0.1 == $1.1 ? $0.0.start < $1.0.start : $0.1 < $1.1 }
        var drips: [String: Int] = [:]
        for allocation in allocations where allocation.target == "daily" && allocation.kind == "fund" && allocation.amountMinor < 0 && allocation.idempotencyKey.hasPrefix("daily:") {
            let bits = allocation.idempotencyKey.split(separator: ":")
            if bits.count == 5, let cycle = allocation.cycleID { drips[cycle.uuidString + ":" + String(bits[3]), default: 0] -= allocation.amountMinor }
        }
        return MoneyLedger(now: now, today: today, repo: repo, movements: movements, transactions: kept, allocations: allocations, categories: categories, cards: cards,
                           pending: pending, starts: starts, spent: spent, other: other, cashOut: cashOut, unknownCash: unknownCash, drips: drips)
    }
    func moneyKindLabel(_ kind: String) -> String {
        ["expense": "مصروف", "fee": "رسوم", "withdrawal": "سحب نقدي", "transfer": "تحويل", "income": "دخل", "salary": "راتب", "refund": "ردّ", "cashback": "استرداد نقدي", "cardPayment": "سداد بطاقة", "billPayment": "سداد فاتورة", "repayment": "سداد قسط", "adjustment": "تسوية"][kind] ?? "حركة مالية"
    }
}
