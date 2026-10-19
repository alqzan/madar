import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One line of «محضر جرد الحسابات»: an owned account, credit card, or BNPL installment plan in the home currency.
struct MoneyReconcileRow: Identifiable {
    struct Suggestion { var observedMinor: Int; var at: Date; var day: GregorianDay; var text: String }
    struct Pending: Identifiable { var id: UUID; var title: String; var amountMinor: Int; var day: GregorianDay }
    var id: UUID
    var side: ReconcileLine.Side
    var name: String
    var detail: String
    /// Madar's book now: account cash, card debt, or the unpaid amount in the installment schedule.
    var expectedMinor: Int
    /// The last live reconciliation of this line, or nil when it was never reconciled.
    var lastAt: Date?
    var lastResolution: String?
    /// Since when the book has run unchecked: the last reconciliation, else its first balance or movement.
    var since: GregorianDay?
    /// Days with a confirmed movement on this line since then: where a missing message could hide.
    var activeDays: Set<GregorianDay>
    var movementCount: Int
    /// L04 composition (accounts): last confirmed balance + in − out since it = expected.
    var baseMinor: Int?
    var baseDay: GregorianDay?
    var baseIsReconciliation: Bool
    var inMinor: Int
    var outMinor: Int
    /// The balance printed in the newest bank message on this account, when nothing moved since it.
    var suggestion: Suggestion?
    /// Drafts on this line still waiting for a decision; a difference that equals one is probably it.
    var pending: [Pending]
}

struct MoneyReconcileReading {
    var today: GregorianDay
    var rows: [MoneyReconcileRow]
    /// «لم يُستحق بعد من يومياتك» (L04): part of the balance, neither surplus nor difference.
    var notYetAccruedMinor: Int?
    var hasOtherCategory: Bool
}

extension AppMoneyService {
    func loadReconcile(at instant: Date? = nil) throws -> MoneyReconcileReading {
        let now = instant ?? app.prayerNow(), home = try load(at: now), zone = app.activePlace.timeZone
        let context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let currency = app.string("core.currency")
        let confirmed = try repo.confirmedTransactions().filter { $0.eventAt <= now }
        let pendingRows = try repo.pendingTransactions()
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let records = try context.fetch(FetchDescriptor<Reconciliation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.sorted { $0.at < $1.at }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let installments = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.kind == "installment" && $0.currency == currency
        }
        func day(_ row: MoneyTransaction) -> GregorianDay { (try? GregorianDay(row.dayKey)) ?? .containing(row.eventAt, in: zone) }
        var rows: [MoneyReconcileRow] = []
        let kinds = ["current": "حساب جارٍ", "savings": "حساب ادّخار", "cash": "نقد في اليد", "wallet": "محفظة"]
        for item in try repo.homeAccountBalances(at: now) where item.account.currency == currency {
            let account = item.account
            let debitCards = Set(cards.filter { $0.accountID == account.id && $0.kind != "credit" }.map(\.id))
            func touches(_ row: MoneyTransaction) -> Bool {
                if row.fromAccountID == account.id || row.toAccountID == account.id { return true }
                return row.cardID.map(debitCards.contains) == true
            }
            let mine = records.filter { $0.accountID == account.id }
            let last = mine.last, confirmedBase = mine.last { $0.resolution != "leave" }
            let baseAt = confirmedBase?.at ?? account.balanceAt
            let baseMinor = try baseAt.map { try repo.accountBalance(account, at: $0) } ?? account.balanceMinor
            // The same rows and rule as `accountBalance` (credit purchases post on payment), split into in and out.
            var inflow = 0, outflow = 0
            for row in confirmed where row.eventAt > (baseAt ?? .distantPast) && (row.fromAccountID == account.id || row.toAccountID == account.id) {
                if let card = cards.first(where: { $0.id == row.cardID }), card.kind == "credit", ["expense", "fee", "refund", "cashback"].contains(row.kind) { continue }
                if row.fromAccountID == account.id { outflow += row.amountMinor }
                if row.toAccountID == account.id { inflow += row.amountMinor }
            }
            let sinceAt = last?.at ?? account.balanceAt
            let moved = confirmed.filter { touches($0) && $0.eventAt > (sinceAt ?? .distantPast) }
            // Prefill from the newest bank message that printed this account's balance, if the book has not moved since.
            var suggestion: MoneyReconcileRow.Suggestion?
            if let newest = confirmed.filter({ touches($0) && $0.messageID != nil }).max(by: { $0.eventAt < $1.eventAt }),
               newest.eventAt > (last?.at ?? .distantPast),
               let message = messages.first(where: { $0.id == newest.messageID }), let data = message.parsedJSON,
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let balance = (parsed["balanceMinor"] as? NSNumber)?.intValue, balance >= 0,
               try repo.accountBalance(account, at: newest.eventAt) == item.homeMinor {
                suggestion = .init(observedMinor: balance, at: newest.eventAt, day: day(newest), text: message.text)
            }
            rows.append(.init(id: account.id, side: .account, name: account.name, detail: [kinds[account.kind] ?? "حساب", account.last4.map { "•••• " + $0 }].compactMap { $0 }.joined(separator: " "),
                expectedMinor: item.homeMinor, lastAt: last?.at, lastResolution: last?.resolution, since: sinceAt.map { .containing($0, in: zone) },
                activeDays: Set(moved.map(day)), movementCount: moved.count, baseMinor: baseMinor, baseDay: baseAt.map { .containing($0, in: zone) },
                baseIsReconciliation: confirmedBase != nil, inMinor: inflow, outMinor: outflow, suggestion: suggestion,
                pending: pendingRows.filter(touches).map { .init(id: $0.id, title: $0.merchant ?? $0.counterparty ?? "حركة تنتظر", amountMinor: $0.homeAmountMinor, day: day($0)) }))
        }
        for debt in try repo.cardDebts(at: now) {
            guard let card = cards.first(where: { $0.id == debt.cardID }) else { continue }
            let mine = records.filter { $0.cardID == card.id }, last = mine.last
            let sinceAt = last?.at ?? confirmed.filter { $0.cardID == card.id }.map(\.eventAt).min()
            let moved = confirmed.filter { $0.cardID == card.id && $0.eventAt > (last?.at ?? .distantPast) }
            rows.append(.init(id: card.id, side: .creditCard, name: card.name, detail: "بطاقة ائتمانية •••• " + card.last4,
                expectedMinor: debt.totalMinor, lastAt: last?.at, lastResolution: last?.resolution, since: sinceAt.map { .containing($0, in: zone) },
                activeDays: Set(moved.map(day)), movementCount: moved.count, baseMinor: nil, baseDay: nil, baseIsReconciliation: last != nil,
                inMinor: debt.statementLeftMinor, outMinor: debt.unbilledLeftMinor, suggestion: nil,
                pending: pendingRows.filter { $0.cardID == card.id }.map { .init(id: $0.id, title: $0.merchant ?? "حركة تنتظر", amountMinor: $0.homeAmountMinor, day: day($0)) }))
        }
        for obligation in obligations {
            let schedule = installments.filter { $0.obligationID == obligation.id }
            guard !schedule.isEmpty else { continue }
            let paidMinor = schedule.reduce(0) { $0 + max(0, min($1.amountMinor, $1.paidMinor)) }
            let remainingMinor = max(0, obligation.totalMinor - paidMinor)
            guard remainingMinor > 0 else { continue }

            let mine = records.filter { $0.obligationID == obligation.id }, last = mine.last
            let purchase = confirmed.first { $0.id == obligation.purchaseTransactionID }
            let firstDate = purchase?.eventAt ?? schedule.map(\.dueDate).min() ?? obligation.createdAt
            let sinceAt = last?.at ?? firstDate
            let moved = confirmed.filter { $0.obligationID == obligation.id && $0.eventAt > (last?.at ?? .distantPast) }
            let provider = obligation.provider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let folded = provider.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let name = folded.contains("tamara") ? "تمارا" : folded.contains("tabby") ? "تابي" : (provider.isEmpty ? obligation.name : provider)
            rows.append(.init(id: obligation.id, side: .installment, name: name, detail: obligation.name,
                expectedMinor: remainingMinor, lastAt: last?.at, lastResolution: last?.resolution,
                since: .containing(sinceAt, in: zone), activeDays: Set(moved.map(day)), movementCount: moved.count,
                baseMinor: obligation.totalMinor, baseDay: .containing(firstDate, in: zone), baseIsReconciliation: last != nil,
                inMinor: paidMinor, outMinor: remainingMinor, suggestion: nil, pending: []))
        }
        let other = try context.fetch(FetchDescriptor<MadarData.Category>()).contains { $0.deletedAt == nil && $0.mergedInto == nil && $0.name == "أخرى" }
        return .init(today: today, rows: rows, notYetAccruedMinor: home.cycle.map { ReconciliationEngine.notYetAccrued(elapsedDays: $0.elapsedDays, $0.input) }, hasOtherCategory: other)
    }
}
