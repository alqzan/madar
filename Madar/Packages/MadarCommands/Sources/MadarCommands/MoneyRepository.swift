import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer

/// Read model shared by money screens; never rewrites checkpoints or stored day keys.
/// Foreign account balances require an explicit manual home rate, never an assumed 1:1 rate.
@MainActor public struct MoneyRepository {
    public let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func effect(of row: MoneyTransaction, includingExcluded: Bool = false) throws -> MovementEffect {
        let settings = try SettingsStore(context: context)
        let cashAsSpend = try settings.value(for: "mal.cashWithdrawalAsSpend") == .bool(true)
        let accounts = try liveAccounts(), cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let card = cards.first { $0.id == row.cardID }
        let from = accounts.first { $0.id == row.fromAccountID }, to = accounts.first { $0.id == row.toAccountID }
        func owned(_ account: Account?) -> Bool { account?.ownership == "mine" && account?.tracked == true }
        let movement: Movement
        var amount = row.homeAmountMinor
        switch row.kind {
        case "expense":
            let method: Movement.PayFrom = card?.kind == "credit" ? .creditCard : card?.kind == "debit" ? .debitCard
                : card?.kind == "prepaid" ? .prepaidCard : from?.kind == "cash" ? .cashWallet : .account
            movement = .purchase(method)
        case "fee": movement = .fee(onCard: card?.kind == "credit")
        case "cardPayment": movement = .cardPayment
        case "withdrawal": movement = .withdrawal
        case "transfer": movement = owned(from) && owned(to) ? .ownTransfer : row.fromAccountID == nil ? .income(isSalary: false) : .externalTransfer(notSpend: false)
        case "income", "salary": movement = .income(isSalary: row.kind == "salary")
        case "refund": movement = .refund(card?.kind == "credit" ? .creditCard : .account)
        case "cashback": movement = .cashbackRedeemed(card?.kind == "credit" ? .creditCard : .account)
        case "billPayment": movement = .billPayment(linkedToObligation: row.obligationID != nil)
        case "repayment":
            let obligation = try context.fetch(FetchDescriptor<Obligation>()).first { $0.id == row.obligationID && $0.deletedAt == nil && $0.mergedInto == nil }
            guard let obligation else { throw MoneyCommandError.invalidReference }
            movement = obligation.kind == "loan" ? .loanInstalment : .bnplInstalment
        case "adjustment":
            // M5-V15 / F03: the reconciliation record holds the signed difference and its name; the movement is linked
            // from `Reconciliation.adjustmentTransactionID` (the dictionary's relation). Accounts also carry the sign in from/to.
            let record = try context.fetch(FetchDescriptor<Reconciliation>()).first { $0.adjustmentTransactionID == row.id && $0.deletedAt == nil && $0.mergedInto == nil }
            let spend = record?.resolution == "unrecordedSpend"
            if row.cardID != nil {
                movement = .cardAdjustment(unrecordedSpend: spend); amount = record?.deltaMinor ?? 0
            } else {
                movement = .adjustment(unrecordedSpend: spend); amount = record?.deltaMinor ?? (row.toAccountID != nil ? row.homeAmountMinor : -row.homeAmountMinor)
            }
        default: throw MoneyCommandError.invalidReference
        }
        var effect = MovementEngine.effect(movement, amountMinor: amount, ignoredFromBudget: row.ignoredFromBudget && !includingExcluded,
            settings: .init(cashWithdrawalAsSpend: cashAsSpend))
        // RM4: obligations are reserved once. The BNPL purchase route is introduced with its own envelope flow.
        if row.obligationID != nil { effect.budgetChargeMinor = 0 }
        return effect
    }

    public func allocationRows(transactionID: UUID? = nil) throws -> [AllocationRow] {
        try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && (transactionID == nil || $0.transactionID == transactionID) }.map { row in
            let target: AllocationTarget
            switch row.target {
            case "daily": target = .daily
            case "reserve": target = .reserve
            case "surplus": target = .surplus
            case "envelope": guard let id = row.targetID else { throw MoneyCommandError.invalidReference }; target = .envelope(id.uuidString)
            case "goal": guard let id = row.targetID else { throw MoneyCommandError.invalidReference }; target = .goal(id.uuidString)
            default: throw MoneyCommandError.invalidReference
            }
            guard let kind = AllocationRow.Kind(rawValue: row.kind) else { throw MoneyCommandError.invalidReference }
            return .init(transactionID: row.transactionID?.uuidString, groupID: row.groupID?.uuidString, target: target,
                amountMinor: row.amountMinor, kind: kind, cycleID: row.cycleID?.uuidString, idempotencyKey: row.idempotencyKey)
        }
    }

    /// The merchant's live rule, by the same normalized pattern the intake uses (M5-V07).
    public func merchantRule(for merchant: String?) throws -> MerchantRule? { try MoneyMutationHandler.rule(for: merchant, in: context) }

    public func confirmedTransactions() throws -> [MoneyTransaction] {
        try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.reviewState == "ok" }
    }
    public func pendingTransactions() throws -> [MoneyTransaction] {
        try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.reviewState != "ok" }
    }
    public func accountBalance(_ account: Account, at now: Date = .now) throws -> Int {
        var deltas: [Int] = []
        let cards = try context.fetch(FetchDescriptor<Card>())
        for row in try confirmedTransactions() where row.eventAt > (account.balanceAt ?? .distantPast) && row.eventAt <= now {
            guard row.fromAccountID == account.id || row.toAccountID == account.id else { continue }
            let amount: Int
            if account.currency == row.currency { amount = row.amountMinor }
            else if account.currency == row.homeCurrency { amount = row.homeAmountMinor }
            else { throw MoneyCommandError.missingRate }
            let card = cards.first { $0.id == row.cardID && $0.deletedAt == nil && $0.mergedInto == nil }
            let credit = card?.kind == "credit"
            // A credit-card purchase/refund never posts to its settlement account until payment.
            if credit && ["expense", "fee", "refund", "cashback"].contains(row.kind) { continue }
            if row.fromAccountID == account.id { deltas.append(-amount) }
            if row.toAccountID == account.id { deltas.append(amount) }
        }
        return try MoneyMutationHandler.sum([account.balanceMinor] + deltas)
    }
    public func homeAccountBalances(at now: Date = .now, rates: [String: String] = [:]) throws -> [(account: Account, homeMinor: Int)] {
        let home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        let rates = try manualRates(at: now).merging(rates) { _, explicit in explicit }
        return try liveAccounts().filter { $0.ownership == "mine" && $0.tracked && $0.balanceAt != nil }.map { account in
            let amount = try accountBalance(account, at: now)
            if account.currency == home { return (account, amount) }
            guard let rate = rates[account.currency] else { throw MoneyCommandError.missingRate }
            return (account, try FX.homeAmount(amountMinor: amount, currency: account.currency, rate: rate, home: home))
        }
    }
    public func basis(at now: Date = .now, rates: [String: String] = [:]) throws -> Basis {
        BasisEngine.basis(try basisInput(at: now, rates: rates))
    }
    public func basisInput(at now: Date = .now, rates: [String: String] = [:]) throws -> BasisInput {
        let rates = try manualRates(at: now).merging(rates) { _, explicit in explicit }
        let accounts = try homeAccountBalances(at: now, rates: rates).map { AccountState(balanceMinor: $0.homeMinor) }
        let transactions = try confirmedTransactions().filter { $0.eventAt <= now }
        let cardStates = try cardDebts(at: now).map { CreditCardState(statementMinor: $0.statementLeftMinor, paidSinceCloseMinor: $0.creditMinor, unbilledMinor: $0.unbilledLeftMinor) }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        func converted(_ amount: Int, currency: String) throws -> Int {
            if currency == home { return amount }; guard let rate = rates[currency] else { throw MoneyCommandError.missingRate }
            return try FX.homeAmount(amountMinor: amount, currency: currency, rate: rate, home: home)
        }
        let bnpl = try items.compactMap { item -> InstallmentState? in
            guard let obligation = obligations.first(where: { $0.id == item.obligationID && $0.kind == "installment" }) else { return nil }
            return .init(amountMinor: try converted(item.amountMinor, currency: obligation.currency), paidMinor: try converted(item.paidMinor, currency: obligation.currency))
        }
        let place = try PrayerRepository(context: context).place(at: now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
        let active = try context.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.start <= now && ($0.end == nil || now < $0.end!) }.max { $0.start < $1.start }
        let month = calendar.dateInterval(of: .month, for: now)!
        let periodStart = active?.start ?? month.start
        let tomorrow = GregorianDay.containing(now, in: place.timeZone).adding(days: 1).date(in: place.timeZone)
        let periodEnd = active.map { max($0.expectedEnd ?? month.end, tomorrow) } ?? month.end
        let loans = try items.compactMap { item -> Int? in
            guard item.dueDate < periodEnd,
                  let obligation = obligations.first(where: { $0.id == item.obligationID && $0.kind == "loan" }) else { return nil }
            return try converted(max(0, item.amountMinor - item.paidMinor), currency: obligation.currency)
        }
        // All bills in this cycle are reserved, including a bill whose due day is still ahead.
        // M5-X00: a bill or subscription on a free schedule is reserved once per unpaid due day inside the period, so a
        // six-month rent is not reserved every cycle.
        let firstDay = GregorianDay.containing(periodStart, in: place.timeZone), endDay = GregorianDay.containing(periodEnd, in: place.timeZone)
        var bills: [Int] = []
        for obligation in obligations where obligation.isRecurring {
            if let schedule = obligation.recurrence {
                let payments = transactions.filter { $0.obligationID == obligation.id }.map(\.eventAt)
                let count = try unpaidRecurring(schedule, from: firstDay, before: endDay, payments: payments, zone: place.timeZone).count
                if count > 0 { bills.append(try converted(obligation.amountMinor, currency: obligation.currency) * count) }
            } else if obligation.kind == "bill", !transactions.contains(where: { $0.obligationID == obligation.id && $0.eventAt >= periodStart && $0.eventAt < periodEnd }) {
                bills.append(try converted(obligation.amountMinor, currency: obligation.currency))
            }
        }
        let allocations = try allocationRows().filter { $0.target != .daily }.map(\.amountMinor)
        return BasisInput(accounts: accounts, creditCards: cardStates, installments: bnpl,
            loanDueMinor: try MoneyMutationHandler.sum(loans), billsDueMinor: try MoneyMutationHandler.sum(bills), envelopeAllocationsMinor: allocations)
    }
    /// Free due dates in a late cycle's gap belong to that cycle, and stay reserved until paid after it closes.
    public func unpaidRecurring(_ schedule: Recurrence, from: GregorianDay, before: GregorianDay, payments: [Date], zone: TimeZone) throws -> [GregorianDay] {
        var days = Set(ObligationSchedule.unpaid(schedule, from: from, before: before, payments: payments, zone: zone))
        for cycle in try context.fetch(FetchDescriptor<Cycle>()) where cycle.deletedAt == nil && cycle.mergedInto == nil {
            guard let expected = cycle.expectedEnd else { continue }
            let end = cycle.end ?? (cycle.start < from.date(in: zone) ? from.date(in: zone) : expected)
            guard end > expected else { continue }
            days.formUnion(ObligationSchedule.unpaid(schedule, from: .containing(expected, in: zone), before: .containing(end, in: zone), payments: payments, zone: zone))
        }
        return days.sorted()
    }

    public func zakatAccounts(at now: Date = .now, rates: [String: String] = [:]) throws -> [ZakatAccount] {
        try homeAccountBalances(at: now, rates: rates).map { .init(balanceMinor: $0.homeMinor, include: $0.account.zakatInclude) }
    }
    private func liveAccounts() throws -> [Account] { try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil } }
}
