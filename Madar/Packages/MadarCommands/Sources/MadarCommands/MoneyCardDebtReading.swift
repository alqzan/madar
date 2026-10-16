import Foundation
import SwiftData
import MadarData
import MadarMoney

public struct MoneyCardDebtReading {
    public var cardID: UUID
    public var cardName: String
    public var statementID: UUID?
    public var statementLeftMinor: Int
    public var unbilledLeftMinor: Int
    public var dueDate: Date?
    public var estimatedClose: Bool
    public var messageID: UUID?
    public var totalMinor: Int { statementLeftMinor + unbilledLeftMinor }
}

extension MoneyRepository {
    /// F07: payments reduce the statement first; a refund reduces the original purchase's
    /// statement or unbilled portion. These same rows feed the headline basis and source view.
    public func cardDebts(at now: Date) throws -> [MoneyCardDebtReading] {
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let owned = Set(accounts.filter { $0.ownership == "mine" && $0.tracked }.map(\.id))
        let tx = try confirmedTransactions().filter { $0.eventAt <= now }
        let statements = try context.fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.closeDate <= now }
        return try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.kind == "credit" && ($0.accountID == nil || owned.contains($0.accountID!)) }.map { card in
            let statement = statements.filter { $0.cardID == card.id }.max { $0.closeDate < $1.closeDate }
            let close = statement?.closeDate ?? .distantPast
            var billed = statement?.statementMinor ?? 0, unbilled = 0, payments = 0
            for row in tx where row.cardID == card.id && row.eventAt > close {
                let delta = try effect(of: row).debtMinor
                if row.kind == "refund", let original = tx.first(where: { $0.id == row.relatedTransactionID }) {
                    if original.eventAt > close { unbilled += delta } else { billed += delta }
                } else if delta < 0 { payments -= delta }
                else { unbilled += delta }
            }
            let state = CreditCardState(statementMinor: max(0, billed), paidSinceCloseMinor: payments, unbilledMinor: max(0, unbilled))
            return .init(cardID: card.id, cardName: card.name, statementID: statement?.id, statementLeftMinor: state.statementLeftMinor,
                unbilledLeftMinor: state.unbilledLeftMinor, dueDate: statement?.dueDate, estimatedClose: statement?.closeDateSource == "estimated", messageID: statement?.messageID)
        }
    }
}
