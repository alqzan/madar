import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyLogMovement: Identifiable, Sendable {
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
    var searchIndex: String
    var searchIndexWithAmount: String
}
struct MoneyLogDay: Identifiable, Sendable {
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
final class MoneyLedger {
    let now: Date
    let today: GregorianDay
    let repo: MoneyRepository
    let movements: [MoneyLogMovement]
    /// The rows the ledger kept (owned accounts and cards only), confirmed or not.
    let transactions: [MoneyTransaction]
    /// The full live snapshot is retained only for the analysis projection, whose definition includes all confirmed rows.
    let allLiveTransactionsForAnalysis: [MoneyTransaction]?
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
         allLiveTransactionsForAnalysis: [MoneyTransaction]? = nil, categories: [MadarData.Category], cards: [Card], pending: [String: Int], starts: [(Cycle, GregorianDay)],
         spent: [String: Int], other: [String: Int], cashOut: [String: Int], unknownCash: Set<String>, drips: [String: Int]) {
        self.now = now; self.today = today; self.repo = repo; self.movements = movements; self.transactions = transactions
        self.allLiveTransactionsForAnalysis = allLiveTransactionsForAnalysis; self.allocations = allocations
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
struct MoneyLogFilter: Identifiable, Sendable {
    var id: String
    var title: String
}
struct MoneyLogReading: Sendable {
    var today: GregorianDay
    var monthStart: GregorianDay
    var days: [MoneyLogDay]
    var arcadeDays: [MoneyLogDay]
    var monthStarts: [GregorianDay]
    var movements: [MoneyLogMovement]
    var filters: [MoneyLogFilter]
    var neutralTransfersMinor: Int
}
struct MoneyLogRouteRequestTracker: Sendable {
    private(set) var pendingRequestID: UUID?
    private(set) var appliedRequestID: UUID?

    var hasPendingRequest: Bool { pendingRequestID != nil && pendingRequestID != appliedRequestID }

    mutating func stage(_ requestID: UUID?) {
        guard let requestID, requestID != appliedRequestID else { return }
        pendingRequestID = requestID
    }

    mutating func markApplied(_ requestID: UUID?) {
        guard let requestID else { return }
        appliedRequestID = requestID
        if pendingRequestID == requestID { pendingRequestID = nil }
    }
}
struct MoneyLogReadRequest: Sendable {
    let now: Date
    let month: GregorianDay?
    let timeZoneIdentifier: String
    let firstCalendar: FirstCalendar
    let hijriSource: HijriSource
    let hijriOffset: Int
    let numerals: NumeralStyle
    let currency: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

@ModelActor private actor MoneyLogReadActor {
    func read(_ request: MoneyLogReadRequest) throws -> MoneyLogReading {
        try Task.checkCancellation()
        return try MoneyLogReadingBuilder.load(context: modelContext, request: request)
    }
}

enum MoneyLogReadingBuilder {
    static func load(context: ModelContext, request: MoneyLogReadRequest) throws -> MoneyLogReading {
        try Task.checkCancellation()
        let ledger = try makeLedger(context: context, request: request), today = ledger.today, movements = ledger.movements
        let start = monthStart(request.month ?? today), days = monthDays(start, timeZone: request.timeZone)
        let readings = ledger.days((-6..<(days.count + 6)).map { start.adding(days: $0) })
        var months = Set(movements.map { monthStart($0.day) })
        months.insert(monthStart(today)); months.insert(monthStart(monthStart(today).adding(days: -1)))
        for key in ledger.pending.keys { if let day = try? GregorianDay(key) { months.insert(monthStart(day)) } }
        var filters = [MoneyLogFilter(id: "all", title: "الكل")]
        if movements.contains(where: \.cash) { filters.append(.init(id: "cash", title: "النقد")) }
        let cardIDsWithMovements = Set(movements.compactMap(\.cardID))
        for card in ledger.cards where cardIDsWithMovements.contains(card.id) { filters.append(.init(id: card.id.uuidString, title: card.name)) }
        if movements.contains(where: \.bnpl) { filters.append(.init(id: "bnpl", title: "الأقساط")) }
        if movements.contains(where: { ["transfer", "cardPayment"].contains($0.kind) }) { filters.append(.init(id: "transfers", title: "تحويلات")) }
        let lastDay = days.last ?? start
        let monthDays = readings.filter { $0.day >= start && $0.day <= lastDay }
        let neutral = movements.reduce(into: 0) { total, movement in
            if movement.confirmed && movement.day >= start && movement.day <= lastDay && movement.budgetLabel == "محايد لليومية"
                && ["transfer", "cardPayment", "repayment"].contains(movement.kind) { total += movement.amountMinor }
        }
        return .init(today: today, monthStart: start, days: monthDays, arcadeDays: readings, monthStarts: months.sorted(by: >),
            movements: movements.sorted { $0.at > $1.at }, filters: filters, neutralTransfersMinor: neutral)
    }

    static func makeLedger(context: ModelContext, request: MoneyLogReadRequest, retainAllLiveTransactionsForAnalysis: Bool = false) throws -> MoneyLedger {
        let now = request.now, repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let tx = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let byID = Dictionary(tx.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let parts = Dictionary(grouping: allocations, by: \.transactionID)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cardByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let messageByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let accountByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var accountOrder: [UUID: Int] = [:]
        for (index, account) in accounts.enumerated() where accountOrder[account.id] == nil { accountOrder[account.id] = index }
        let cashAccountIDs = Set(accounts.lazy.filter { $0.kind == "cash" }.map(\.id))
        var spent: [String: Int] = [:], other: [String: Int] = [:], cashOut: [String: Int] = [:], unknownCash: Set<String> = [], pending: [String: Int] = [:]
        var movements: [MoneyLogMovement] = [], kept: [MoneyTransaction] = []
        let owned = Set(accounts.filter { $0.ownership == "mine" && $0.tracked }.map(\.id))
        let effects = try repo.effectContext()
        for (index, row) in tx.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            if let card = row.cardID.flatMap({ cardByID[$0] }), let account = card.accountID, !owned.contains(account) { continue }
            let linked = [row.fromAccountID, row.toAccountID].compactMap { $0 }
            if !linked.isEmpty && !linked.contains(where: owned.contains) { continue }
            guard let day = try? GregorianDay(row.dayKey) else { continue }
            kept.append(row)
            let confirmed = row.reviewState == "ok", effect = try? repo.effect(of: row, in: effects)
            let original = row.kind == "refund" ? row.relatedTransactionID.flatMap { byID[$0] } : nil
            let budgetDay = original?.dayKey ?? row.dayKey
            let ownParts = parts[row.id] ?? []
            if confirmed {
                let budgetParts = ownParts.filter { ["spend", "refund", "adjust", "offset"].contains($0.kind) }
                spent[budgetDay, default: 0] -= budgetParts.filter { $0.target == "daily" }.reduce(0) { $0 + $1.amountMinor }
                other[budgetDay, default: 0] -= budgetParts.filter { $0.target != "daily" }.reduce(0) { $0 + $1.amountMinor }
                if row.ignoredFromBudget {
                    let charge = (try? repo.effect(of: row, includingExcluded: true, in: effects))?.budgetChargeMinor ?? 0
                    other[budgetDay, default: 0] += charge
                }
                if let effect { cashOut[row.dayKey, default: 0] += max(0, -effect.cashMinor) }
                else { unknownCash.insert(row.dayKey) }
            } else { pending[row.dayKey, default: 0] += 1 }
            let title = row.merchant ?? row.counterparty ?? moneyKindLabel(row.kind)
            let category = row.categoryID.flatMap { categoryByID[$0] }?.name ?? moneyKindLabel(row.kind)
            let paymentAccount = [row.fromAccountID, row.toAccountID].compactMap { $0 }.compactMap { id in accountOrder[id].map { (id, $0) } }
                .min { $0.1 < $1.1 }.flatMap { accountByID[$0.0] }
            let payment = row.cardID.flatMap { cardByID[$0] }?.name ?? paymentAccount?.name ?? "طريقة الدفع غير معروفة"
            let searchText = title + category + payment
            let searchIndex = normalizedSearch(searchText)
            let searchIndexWithAmount = normalizedSearch(searchText + formattedAmount(row.homeAmountMinor, request: request))
            let budgetLabel = !confirmed ? "ينتظر قرارك" : row.ignoredFromBudget ? "خارج الميزانية" : row.kind == "refund" ? "عاد إلى يوم الأصل" : ["cardPayment", "repayment", "income", "salary", "cashback"].contains(row.kind) || effect?.budgetChargeMinor == 0 ? "محايد لليومية" : ownParts.contains { $0.target == "daily" } ? "من يومك" : ownParts.isEmpty ? "التخصيص غير مكتمل" : "من المظاريف"
            let explanation = !confirmed ? "هذه حركة تنتظر قرارك؛ لم تدخل الأرقام المؤكدة بعد." : "حركة مؤكّدة: " + budgetLabel + ". " + (row.kind == "cardPayment" ? "السداد تحويل ينقص النقد والدين، ولا يخصم اليومية مرة أخرى." : "التخصيصات الفعلية هي مصدر صرف اليومية والمظاريف.")
            var detail = MoneySourceDetail(id: row.id.uuidString, title: title, amountMinor: row.homeAmountMinor, explanation: explanation, message: row.messageID.flatMap { messageByID[$0] }?.text, date: day)
            if let original, let originalDay = try? GregorianDay(original.dayKey) {
                detail.explanation += " الرد يعود إلى يوم الأصل: " + dateLabels(originalDay, request: request).combined + "."
            }
            movements.append(.init(id: row.id, day: day, at: row.eventAt, title: title, category: category, payment: payment, kind: row.kind, cardID: row.cardID,
                cash: row.fromAccountID.map(cashAccountIDs.contains) ?? false, bnpl: row.method == "bnpl" || row.kind == "repayment", amountMinor: row.homeAmountMinor,
                confirmed: confirmed, budgetLabel: budgetLabel, detail: detail, searchIndex: searchIndex, searchIndexWithAmount: searchIndexWithAmount))
        }
        let drafted = Set(tx.compactMap(\.messageID))
        for message in messages where ["needsLook", "possibleDuplicate"].contains(message.status) && !drafted.contains(message.id) {
            if let day = try? DiaryLineRenderer.today(context: context, now: message.receivedAt) { pending[day.description, default: 0] += 1 }
        }
        let policies = try context.fetch(FetchDescriptor<CyclePolicy>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.start <= now }
        let firstPolicyDayByCycle = policies.reduce(into: [UUID: String]()) { firstDays, policy in
            guard let cycleID = policy.cycleID else { return }
            if let current = firstDays[cycleID], current <= policy.effectiveFromDayKey { return }
            firstDays[cycleID] = policy.effectiveFromDayKey
        }
        var starts: [(Cycle, GregorianDay)] = []
        for cycle in cycles {
            guard let first = firstPolicyDayByCycle[cycle.id], let day = try? GregorianDay(first) else { continue }
            starts.append((cycle, day))
        }
        starts.sort { $0.1 == $1.1 ? $0.0.start < $1.0.start : $0.1 < $1.1 }
        var drips: [String: Int] = [:]
        for allocation in allocations where allocation.target == "daily" && allocation.kind == "fund" && allocation.amountMinor < 0 && allocation.idempotencyKey.hasPrefix("daily:") {
            let bits = allocation.idempotencyKey.split(separator: ":")
            if bits.count == 5, let cycle = allocation.cycleID { drips[cycle.uuidString + ":" + String(bits[3]), default: 0] -= allocation.amountMinor }
        }
        return MoneyLedger(now: now, today: today, repo: repo, movements: movements, transactions: kept, allocations: allocations,
            allLiveTransactionsForAnalysis: retainAllLiveTransactionsForAnalysis ? tx : nil, categories: categories, cards: cards,
            pending: pending, starts: starts, spent: spent, other: other, cashOut: cashOut, unknownCash: unknownCash, drips: drips)
    }

    private static func monthStart(_ day: GregorianDay) -> GregorianDay {
        (try? GregorianDay(year: day.year, month: day.month, day: 1)) ?? day
    }

    private static func monthDays(_ anchor: GregorianDay, timeZone: TimeZone) -> [GregorianDay] {
        let start = monthStart(anchor)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let length = calendar.range(of: .day, in: .month, for: start.date(in: timeZone))?.count ?? 30
        return (0..<length).map { start.adding(days: $0) }
    }

    private static func dateLabels(_ day: GregorianDay, request: MoneyLogReadRequest) -> MadarDateLabels {
        DualDate(instant: day.date(in: request.timeZone).addingTimeInterval(12 * 3600), timeZone: request.timeZone,
            source: request.hijriSource, sightingOffset: request.hijriOffset)
            .labels(firstCalendar: request.firstCalendar, numerals: request.numerals)
    }

    private static func normalizedSearch(_ value: String) -> String {
        BankDedupe.normalize(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func formattedAmount(_ minor: Int, request: MoneyLogReadRequest) -> String {
        let exponent = CurrencyExponents.specified.exponent(request.currency) ?? 2
        var scale = 1
        for _ in 0..<exponent { scale *= 10 }
        let showFractions = minor % scale != 0
        return MadarNumberFormatter(style: request.numerals).amount(
            minorUnits: Int64(showFractions ? minor : minor / scale), fractionDigits: showFractions ? exponent : 0, signed: false)
    }

    private static func moneyKindLabel(_ kind: String) -> String {
        ["expense": "مصروف", "fee": "رسوم", "withdrawal": "سحب نقدي", "transfer": "تحويل", "income": "دخل", "salary": "راتب", "refund": "ردّ", "cashback": "استرداد نقدي", "cardPayment": "سداد بطاقة", "billPayment": "سداد فاتورة", "repayment": "سداد قسط", "adjustment": "تسوية"][kind] ?? "حركة مالية"
    }
}
extension AppMoneyService {
    var logCalendar: MadarCalendarDays { .init(zone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, offset: Int(app.number("core.hijriOffset"))) }
    // Owner, 26 Oct 2026: the log is grouped by Gregorian month whatever the first calendar; the title still shows both.
    func logMonthStart(_ day: GregorianDay) -> GregorianDay {
        (try? GregorianDay(year: day.year, month: day.month, day: 1)) ?? day
    }
    func logMonthDays(_ anchor: GregorianDay) -> [GregorianDay] {
        let start = logMonthStart(anchor)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        let length = calendar.range(of: .day, in: .month, for: start.date(in: calendar.timeZone))?.count ?? 30
        return (0..<length).map { start.adding(days: $0) }
    }
    func logMonthLabels(_ start: GregorianDay, end: GregorianDay? = nil, primary calendar: FirstCalendar = .gregorian) -> MadarDateLabels {
        let end = end ?? logMonthDays(start).last ?? start
        let first = app.dateLabels(start, first: calendar), last = app.dateLabels(end, first: calendar)
        let primary = first.primary.split(separator: " ").dropFirst().joined(separator: " ")
        let a = first.secondary.split(separator: " ").dropFirst().joined(separator: " "), b = last.secondary.split(separator: " ").dropFirst().joined(separator: " ")
        return .init(primary: primary, secondary: a == b ? a : a + " – " + b)
    }
    func loadLog(month: GregorianDay? = nil, at instant: Date? = nil) throws -> MoneyLogReading {
        try requireReadableStore()
        let request = logReadRequest(month: month, at: instant ?? app.prayerNow())
        return try MoneyLogReadingBuilder.load(context: ModelContext(app.container), request: request)
    }
    func loadLogOffMain(month: GregorianDay? = nil, at instant: Date? = nil) async throws -> MoneyLogReading {
        let session = app
        let now = instant ?? session.prayerNow()
        for attempt in 0..<4 {
            do {
                try requireReadableStore()
                guard !session.settingsWriteInProgress else { throw BackupOperationError.busy }
                let revision = session.prayerRevision, generation = session.storeGeneration, container = session.container
                let request = logReadRequest(month: month, at: now)
                let readTask = Task.detached(priority: .userInitiated) {
                    let worker = MoneyLogReadActor(modelContainer: container)
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
    func moneyLedger(at now: Date) throws -> MoneyLedger {
        try requireReadableStore() // same store/authentication boundary as the home, without rebuilding the home
        return try MoneyLogReadingBuilder.makeLedger(context: ModelContext(app.container), request: logReadRequest(at: now))
    }
    func logReadRequest(month: GregorianDay? = nil, at now: Date) -> MoneyLogReadRequest {
        .init(now: now, month: month, timeZoneIdentifier: app.activePlace.timeZone.identifier,
            firstCalendar: FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri,
            hijriSource: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura,
            hijriOffset: Int(app.number("core.hijriOffset")),
            numerals: app.string("core.numerals") == "western" ? .western : .hindi,
            currency: app.string("core.currency"))
    }
}
