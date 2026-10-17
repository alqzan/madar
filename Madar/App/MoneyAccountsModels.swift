import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyAccountRow: Identifiable {
    var id: String
    var accountID: UUID?
    var name: String
    var subtitle: String
    var amountMinor: Int?
    var currency: String
    var side: AccountRoot.Side
    var counted: Bool
    var messageCount: Int
    var source: AccountBalanceSource?
    var edit: MoneyAccountEdit?
}
struct MoneyAccountEdit: Identifiable {
    var id: UUID
    var isNew: Bool
    var name: String
    var bank: String
    var last4: String
    var kind: String
    var ownership: String
    var currency: String
    var openingMinor: Int
    var openingAt: Date
    var senderIDs: [String]
    var tracked: Bool
    var zakatInclude: Bool
    var fixedCheckpoint: Bool
    var openingKnown = true
}
struct MoneyAccountsReading {
    var rows: [MoneyAccountRow]
    var basis: Basis?
    var shortcutAt: Date?
    var shortcutCount: Int
}
extension AppMoneyService {
    func loadAccounts() throws -> MoneyAccountsReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = app.prayerNow()
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.sorted { ($0.ownership == "mine" ? 0 : 1, $0.name) < ($1.ownership == "mine" ? 0 : 1, $1.name) }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let reconciliations = try context.fetch(FetchDescriptor<Reconciliation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.resolution != "leave" }
        var rows: [MoneyAccountRow] = []
        for a in accounts {
            let matching = messages.filter { m in
                guard let data = m.parsedJSON, let parsed = try? JSONDecoder().decode(MoneyParsedFields.self, from: data) else { return false }
                return MoneyAccountRules.matches(a, sender: m.sender, last4: parsed.last4)
            }
            let latest = matching.compactMap { m -> (Date, Int)? in
                guard let data = m.parsedJSON, let p = try? JSONDecoder().decode(MoneyParsedFields.self, from: data), let balance = p.balanceMinor, p.currency == a.currency else { return nil }
                return (p.eventAt ?? m.receivedAt, balance)
            }.max { $0.0 < $1.0 }
            let evidence = latest.flatMap { pair -> (at: Date, printedMinor: Int, bookMinor: Int)? in
                guard let book = try? repo.accountBalance(a, at: pair.0) else { return nil }; return (pair.0, pair.1, book)
            }
            let source = AccountsTree.source(openingAt: a.balanceAt, reconciledAt: reconciliations.filter { $0.accountID == a.id }.map(\.at).max(), message: evidence)
            let edit = MoneyAccountEdit(id: a.id, isNew: false, name: a.name, bank: a.bank, last4: a.last4 ?? "", kind: a.kind, ownership: a.ownership,
                currency: a.currency, openingMinor: a.balanceMinor, openingAt: a.balanceAt ?? now, senderIDs: a.senderIDs, tracked: a.tracked, zakatInclude: a.zakatInclude,
                fixedCheckpoint: try MoneyAccountRules.hasMovements(a.id, in: context), openingKnown: a.balanceAt != nil)
            rows.append(.init(id: "account:" + a.id.uuidString, accountID: a.id, name: a.name, subtitle: Self.accountKind(a.kind), amountMinor: try? repo.accountBalance(a, at: now), currency: a.currency, side: .cash,
                counted: a.ownership == "mine" && a.tracked, messageCount: matching.count, source: source, edit: edit))
        }
        let debts = try repo.cardDebts(at: now)
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        for debt in debts {
            let card = cards.first { $0.id == debt.cardID }
            rows.append(.init(id: "card:" + debt.cardID.uuidString, name: debt.cardName, subtitle: "ائتماني", amountMinor: debt.totalMinor, currency: app.string("core.currency"), side: .creditCard, counted: true,
                messageCount: messages.filter { m in guard let bytes = m.parsedJSON, let p = try? JSONDecoder().decode(MoneyParsedFields.self, from: bytes) else { return false }; return p.last4 == card?.last4 && (BankDedupe.normalize(m.sender) == BankDedupe.normalize(card?.bank ?? "") || card?.aliases.map(BankDedupe.normalize).contains(BankDedupe.normalize(m.sender)) == true) }.count))
        }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.kind == "installment" }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        for o in obligations {
            let remaining = items.filter { $0.obligationID == o.id }.reduce(0) { $0 + max(0, $1.amountMinor - $1.paidMinor) }
            rows.append(.init(id: "installment:" + o.id.uuidString, name: o.name, subtitle: "تقسيط", amountMinor: remaining, currency: o.currency, side: .instalment, counted: true, messageCount: o.sourceMessageID == nil ? 0 : 1))
        }
        let shortcut = messages.filter { $0.channel == "shortcut" }
        let ordered = rows.filter(\.counted) + rows.filter { !$0.counted }
        return .init(rows: ordered, basis: try? repo.basis(at: now), shortcutAt: shortcut.map(\.receivedAt).max(), shortcutCount: shortcut.count)
    }
    static func accountKind(_ raw: String) -> String { switch raw { case "savings": "ادخار"; case "cash": "نقد"; case "wallet": "محفظة"; default: "جاري" } }
}
