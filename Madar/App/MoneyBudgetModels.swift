import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarMoney

struct MoneyBudgetRow: Identifiable {
    var id: UUID
    var merchant: String
    var category: String
    var payment: String
    var day: GregorianDay
    var at: Date
    var amountMinor: Int
    var netMinor: Int
    var dailyMinor: Int
    var categoryMinor: Int
    var excluded: Bool
}
struct MoneyBudgetReading {
    var rows: [MoneyBudgetRow]
    var excludedMinor: Int
    var dailyMinor: Int
}
extension AppMoneyService {
    func loadBudgetExclusions() throws -> MoneyBudgetReading {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = app.prayerNow()
        let cycle = try repo.cycle(at: now)
        let movements = try repo.confirmedTransactions().filter { $0.eventAt <= now }
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.mergedInto == nil }
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let rows = try movements.filter { $0.cycleID == cycle?.id && $0.homeCurrency == app.string("core.currency") && $0.obligationID == nil && ["expense", "fee", "withdrawal", "transfer"].contains($0.kind) }.compactMap { row -> MoneyBudgetRow? in
            let excluded = row.ignoredFromBudget
            guard try repo.effect(of: row, includingExcluded: true).budgetChargeMinor > 0 else { return nil }
            let refunds = movements.filter { $0.kind == "refund" && $0.relatedTransactionID == row.id }
            let net = max(0, row.homeAmountMinor - refunds.reduce(0) { $0 + $1.homeAmountMinor })
            let parts = allocations.filter { $0.transactionID == row.id && $0.kind == "spend" && ($0.deletedAt == nil || excluded) }.sorted { $0.idempotencyKey < $1.idempotencyKey }
            let shares = parts.isEmpty ? [] : AllocationEngine.distribute(row.homeAmountMinor - net, weights: parts.map { -$0.amountMinor })
            let daily = parts.isEmpty ? net : max(0, zip(parts, shares).filter { $0.0.target == "daily" }.reduce(0) { $0 - $1.0.amountMinor - $1.1 })
            return .init(id: row.id, merchant: row.merchant ?? row.counterparty ?? "حركة بلا اسم", category: categories.first { $0.id == row.categoryID }?.name ?? "بلا تصنيف",
                payment: cards.first { $0.id == row.cardID }?.name ?? accounts.first { $0.id == row.fromAccountID }?.name ?? "",
                day: try GregorianDay(row.dayKey), at: row.eventAt, amountMinor: row.homeAmountMinor, netMinor: net, dailyMinor: daily,
                categoryMinor: row.categoryID == nil ? 0 : net, excluded: excluded)
        }.sorted { $0.at == $1.at ? $0.id.uuidString < $1.id.uuidString : $0.at > $1.at }
        return .init(rows: rows, excludedMinor: rows.filter(\.excluded).reduce(0) { $0 + $1.netMinor }, dailyMinor: rows.filter { !$0.excluded }.reduce(0) { $0 + $1.dailyMinor })
    }
}
