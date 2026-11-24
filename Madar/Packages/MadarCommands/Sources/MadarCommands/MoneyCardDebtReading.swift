import Foundation
import SwiftData
import MadarData
import MadarMoney

public struct MoneyCardDebtReading {
    public var cardID: UUID
    public var cardName: String
    public var statementID: UUID?
    public var statementLeftMinor: Int
    public var minimumLeftMinor: Int?
    public var unbilledLeftMinor: Int
    /// Paid beyond the whole debt; the card holds it (F01).
    public var creditMinor: Int = 0
    public var dueDate: Date?
    public var estimatedClose: Bool
    public var messageID: UUID?
    public var totalMinor: Int { statementLeftMinor + unbilledLeftMinor }
}

extension MoneyRepository {
    /// F07: payments reduce the statement first; a refund reduces the original purchase's
    /// statement or unbilled portion. These same rows feed the headline basis and source view.
    public func cardDebts(at now: Date) throws -> [MoneyCardDebtReading] {
        let lookup = try effectContext()
        let owned = Set(lookup.accounts.filter { $0.ownership == "mine" && $0.tracked }.map(\.id))
        let creditCards = lookup.cards.filter { $0.kind == "credit" && ($0.accountID.map(owned.contains) ?? true) }
        guard !creditCards.isEmpty else { return [] }
        let tx = try confirmedTransactions().filter { $0.eventAt <= now }
        let statements = try context.fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.closeDate <= now }
        let statementsByCard = Dictionary(grouping: statements) { $0.cardID }
        let txByCard = Dictionary(grouping: tx) { $0.cardID }
        let txByID = Dictionary(tx.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try creditCards.map { card in
            let statement = (statementsByCard[card.id] ?? []).max { ($0.closeDate, $0.id.uuidString) < ($1.closeDate, $1.id.uuidString) }
            let close = statement?.closeDate ?? .distantPast
            var billed = statement?.statementMinor ?? 0, unbilled = 0, payments = 0
            for row in txByCard[card.id] ?? [] where row.eventAt > close {
                let delta = try effect(of: row, in: lookup).debtMinor
                if row.kind == "refund", let rid = row.relatedTransactionID, let original = txByID[rid] {
                    if original.eventAt > close { unbilled += delta } else { billed += delta }
                } else if delta < 0 { payments -= delta }
                else { unbilled += delta }
            }
            // A refund can arrive after the purchase's statement was already settled. Its
            // excess reduces unbilled debt and then stays on the card as credit (F01).
            let excessRefund = max(0, -billed)
            let state = CreditCardState(statementMinor: max(0, billed), paidSinceCloseMinor: payments + excessRefund, unbilledMinor: max(0, unbilled))
            let minimumLeft = statement.map {
                let credited = max(0, $0.statementMinor - state.statementLeftMinor)
                return max(0, $0.minimumDueMinor - credited)
            }
            return .init(cardID: card.id, cardName: card.name, statementID: statement?.id, statementLeftMinor: state.statementLeftMinor,
                minimumLeftMinor: minimumLeft,
                unbilledLeftMinor: state.unbilledLeftMinor, creditMinor: state.creditMinor, dueDate: statement?.dueDate, estimatedClose: statement?.closeDateSource == "estimated", messageID: statement?.messageID)
        }
    }
}
