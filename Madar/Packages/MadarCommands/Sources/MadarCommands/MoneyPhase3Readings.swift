import Foundation
import SwiftData
import MadarData
import MadarMoney
import MadarPrayer

/// Owner, 11 Nov 2026, phase 3: recurring charges and salary, instalment plans, refund matching, fees and foreign-currency details.
/// All derived on read from stored rows with predicate-limited fetches; nothing here writes.
public extension MoneyRepository {
    // MARK: Recurring charges and salary

    struct RecurringRow: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable { case subscription, salary }
        public var kind: Kind
        public var series: RecurringCharges.Series
        /// A bill or subscription obligation of the same merchant already exists, so the room need not offer to create one.
        public var isTracked: Bool
        public var id: String { kind.rawValue + ":" + series.id }
    }

    /// Subscriptions (bank-confirmed expenses repeating at a regular interval, any interval) and recurring salary credits, soonest expected first.
    /// A series whose pattern ended (`status == .ended`) is left out unless `includeEnded`.
    func recurringCharges(now: Date = .now, includeEnded: Bool = false) throws -> [RecurringRow] {
        let zone = try PrayerRepository(context: context).place(at: now).timeZone
        let from = now.addingTimeInterval(-1_100 * 86_400)
        let expenses = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.kind == "expense" && $0.reviewState == "ok" && $0.source == "bank" && $0.obligationID == nil
                && $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt >= from && $0.eventAt <= now }))
        let salaries = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.kind == "salary" && $0.reviewState == "ok" && $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt >= from && $0.eventAt <= now }))
        let obligations = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        let tracked = Set(obligations.flatMap { [MerchantKey.key($0.name), MerchantKey.key($0.provider)] }.filter { !$0.isEmpty })
        let spend: [RecurringCharges.Occurrence] = expenses.compactMap { row in
            guard let name = row.merchant ?? row.counterparty else { return nil }
            let key = MerchantKey.key(name)
            return key.isEmpty ? nil : .init(id: row.id.uuidString, key: key, name: name, currency: row.currency, amountMinor: row.amountMinor, at: row.eventAt)
        }
        let pay: [RecurringCharges.Occurrence] = salaries.map { row in
            let name = row.counterparty ?? row.merchant
            return .init(id: row.id.uuidString, key: SalarySourceMatcher.key(name) ?? "salary", name: name ?? "الراتب",
                         currency: row.currency, amountMinor: row.amountMinor, at: row.eventAt)
        }
        let subscriptions = RecurringCharges.detect(spend, profile: .subscription, now: now, timeZone: zone)
            .map { RecurringRow(kind: .subscription, series: $0, isTracked: tracked.contains($0.key)) }
        let salary = RecurringCharges.detect(pay, profile: .salary, now: now, timeZone: zone)
            .map { RecurringRow(kind: .salary, series: $0, isTracked: false) }
        return (subscriptions + salary).filter { includeEnded || $0.series.status != .ended }
            .sorted { ($0.series.nextExpectedAt, $0.id) < ($1.series.nextExpectedAt, $1.id) }
    }

    // MARK: Message fields

    /// Messages by id with their parsed fields, read in bounded predicate chunks.
    func parsedMessages(_ ids: [UUID]) throws -> [UUID: (message: BankMessage, fields: MoneyParsedFields?)] {
        var result: [UUID: (message: BankMessage, fields: MoneyParsedFields?)] = [:]
        let unique = Array(Set(ids))
        for start in stride(from: 0, to: unique.count, by: 200) {
            let chunk = Array(unique[start..<min(start + 200, unique.count)])
            for message in try context.fetch(FetchDescriptor<BankMessage>(predicate: #Predicate { chunk.contains($0.id) && $0.deletedAt == nil && $0.mergedInto == nil })) {
                result[message.id] = (message, message.parsedJSON.flatMap { try? JSONDecoder().decode(MoneyParsedFields.self, from: $0) })
            }
        }
        return result
    }

    func liveTransactions(_ ids: [UUID]) throws -> [UUID: MoneyTransaction] {
        var result: [UUID: MoneyTransaction] = [:]
        let unique = Array(Set(ids))
        for start in stride(from: 0, to: unique.count, by: 200) {
            let chunk = Array(unique[start..<min(start + 200, unique.count)])
            for row in try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { chunk.contains($0.id) && $0.deletedAt == nil && $0.mergedInto == nil })) { result[row.id] = row }
        }
        return result
    }

    // MARK: Instalment plans

    /// Tamara/Tabby plans: open dues announced plus instalments paid, grouped by provider and merchant, with the count and remaining
    /// figures only where a message printed them.
    func instalmentPlans(now: Date = .now) throws -> [InstalmentPlans.Plan] {
        let dues = try context.fetch(FetchDescriptor<UpcomingDue>(predicate: #Predicate { $0.kind == "bnpl" && $0.deletedAt == nil && $0.mergedInto == nil }))
        let payments = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.kind == "repayment" && $0.reviewState == "ok" && $0.messageID != nil && $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt <= now }))
        let live = try liveTransactions(dues.compactMap(\.closedByTransactionID))
        let openDues = dues.filter { $0.closedByTransactionID.map { live[$0] == nil } ?? true }
        let messages = try parsedMessages(openDues.compactMap(\.sourceMessageID) + payments.compactMap(\.messageID))
        var events: [InstalmentPlans.Event] = []
        for due in openDues {
            let fields = due.sourceMessageID.flatMap { messages[$0]?.fields }
            events.append(.init(id: due.id.uuidString, provider: due.payee, merchant: fields?.merchant, currency: due.currency, amountMinor: due.amountMinor,
                                at: due.dueAt ?? due.createdAt, isPaid: false, number: fields?.instalmentNumber, count: fields?.instalmentCount, remainingMinor: fields?.remainingMinor))
        }
        for row in payments {
            guard let fields = row.messageID.flatMap({ messages[$0]?.fields }), let provider = fields.provider else { continue }
            events.append(.init(id: row.id.uuidString, provider: provider, merchant: row.merchant ?? fields.merchant, currency: row.currency, amountMinor: row.amountMinor,
                                at: row.eventAt, isPaid: true, number: fields.instalmentNumber, count: fields.instalmentCount, remainingMinor: fields.remainingMinor))
        }
        return InstalmentPlans.derive(events)
    }

    // MARK: Refund matching

    struct RefundOriginals: Equatable, Sendable {
        /// The one purchase to link without asking; nil when ambiguous or none.
        public var suggested: UUID?
        /// Every purchase the refund could undo, best first (for a chooser).
        public var candidates: [UUID]
    }

    /// Purchases a refund draft could undo. Link the choice with `money.edit {id, relatedTransactionID}` before confirming; the confirm path
    /// re-checks it (confirmed expense, same currency, same card, amount within what is left).
    func refundOriginals(forRefund id: UUID) throws -> RefundOriginals {
        guard let row = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.id == id })).first, row.kind == "refund" else {
            return .init(suggested: nil, candidates: [])
        }
        let (refund, originals) = try refundInputs(for: row)
        return .init(suggested: RefundMatching.match(refund, among: originals).flatMap(UUID.init(uuidString:)),
                     candidates: RefundMatching.candidates(for: refund, among: originals).compactMap { UUID(uuidString: $0.id) })
    }

    /// The unique matching purchase of a refund row (used by intake to link the draft).
    func matchedOriginal(forRefund row: MoneyTransaction) throws -> UUID? {
        let (refund, originals) = try refundInputs(for: row)
        return RefundMatching.match(refund, among: originals).flatMap(UUID.init(uuidString:))
    }

    private func refundInputs(for row: MoneyTransaction) throws -> (RefundMatching.Refund, [RefundMatching.Original]) {
        let refund = RefundMatching.Refund(merchant: row.merchant ?? row.counterparty, cardKey: row.cardID?.uuidString, accountKey: row.toAccountID?.uuidString,
                                           currency: row.currency, amountMinor: row.amountMinor, at: row.eventAt)
        let currency = row.currency, at = row.eventAt, amount = row.amountMinor, selfID = row.id
        let from = at.addingTimeInterval(-TimeInterval(RefundMatching.windowDays) * 86_400)
        let purchases = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.kind == "expense" && $0.reviewState == "ok" && $0.deletedAt == nil && $0.mergedInto == nil && $0.currency == currency
                && $0.eventAt <= at && $0.eventAt >= from && $0.amountMinor >= amount && $0.id != selfID }))
        guard !purchases.isEmpty else { return (refund, []) }
        let linked = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.kind == "refund" && $0.relatedTransactionID != nil && $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt >= from && $0.id != selfID }))
        var refunded: [UUID: Int] = [:]
        for other in linked { if let target = other.relatedTransactionID { refunded[target, default: 0] += other.amountMinor } }
        return (refund, purchases.map {
            .init(id: $0.id.uuidString, merchant: $0.merchant ?? $0.counterparty, cardKey: $0.cardID?.uuidString, accountKey: $0.fromAccountID?.uuidString,
                  currency: $0.currency, amountMinor: $0.amountMinor, refundedMinor: refunded[$0.id] ?? 0, at: $0.eventAt)
        })
    }

    // MARK: Fees, VAT, foreign currency

    struct TransactionCharges: Equatable, Sendable {
        public var transactionID: UUID
        /// What the bank printed beside the movement; empty when nothing was printed.
        public var charges: ChargeBreakdown
        /// The currency of `charges`: the home (account) currency for a foreign purchase, since banks bill the markup there; else the movement's currency.
        public var chargeCurrency: String
        /// The original foreign amount and currency are the transaction's own `amountMinor` / `currency`.
        public var isForeign: Bool
        public var originalAmountMinor: Int
        public var originalCurrency: String
        public var homeAmountMinor: Int
        public var homeCurrency: String
        /// The rate Madar used for the home amount (`rateAtTime`) and the rate text the message printed, never mixed.
        public var rateAtTime: String?
        public var printedRate: String?
    }

    struct ChargeTotal: Equatable, Sendable {
        public var currency: String
        public var charges: ChargeBreakdown
        public var transactionCount: Int
    }

    /// Fees, VAT and foreign details for the given transactions. Rows with neither charges nor a foreign currency are omitted.
    func charges(forTransactions ids: [UUID]) throws -> [UUID: TransactionCharges] {
        try chargeDetails(Array(try liveTransactions(ids).values))
    }

    /// Totals of printed fees and VAT over confirmed movements with `from <= eventAt < to`, one per currency (never converted).
    func chargeTotals(from: Date, to: Date) throws -> [ChargeTotal] {
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate {
            $0.reviewState == "ok" && $0.messageID != nil && $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt >= from && $0.eventAt < to }))
        var totals: [String: (ChargeBreakdown, Int)] = [:]
        for detail in try chargeDetails(rows).values where !detail.charges.isEmpty {
            let old = totals[detail.chargeCurrency] ?? (ChargeBreakdown(), 0)
            totals[detail.chargeCurrency] = (old.0 + detail.charges, old.1 + 1)
        }
        return totals.map { ChargeTotal(currency: $0.key, charges: $0.value.0, transactionCount: $0.value.1) }.sorted { $0.currency < $1.currency }
    }

    private func chargeDetails(_ rows: [MoneyTransaction]) throws -> [UUID: TransactionCharges] {
        let messages = try parsedMessages(rows.compactMap(\.messageID))
        var result: [UUID: TransactionCharges] = [:]
        for row in rows {
            let fields = row.messageID.flatMap { messages[$0]?.fields }
            let charges = ChargeBreakdown(feeMinor: fields?.feeMinor ?? 0, vatMinor: fields?.vatMinor ?? 0, foreignFeeMinor: fields?.foreignFeeMinor ?? 0)
            let foreign = row.currency != row.homeCurrency
            guard !charges.isEmpty || foreign else { continue }
            result[row.id] = .init(transactionID: row.id, charges: charges, chargeCurrency: foreign ? row.homeCurrency : row.currency, isForeign: foreign, originalAmountMinor: row.amountMinor, originalCurrency: row.currency,
                                   homeAmountMinor: row.homeAmountMinor, homeCurrency: row.homeCurrency, rateAtTime: row.rateAtTime, printedRate: fields?.exchangeRate)
        }
        return result
    }
}
