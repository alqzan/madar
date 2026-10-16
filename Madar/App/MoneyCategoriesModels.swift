import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One book on a category's shelf: a merchant's spending this cycle.
struct MoneyShelfBook: Identifiable, Equatable {
    var id: String
    var name: String
    var amountMinor: Int
}

struct MoneyCategoryShelf: Identifiable, Equatable {
    var id: UUID
    var name: String
    var spentMinor: Int
    /// The limit for this cycle (percent limits follow this cycle's income or dailies); nil = no limit.
    var limitMinor: Int?
    var mode: String
    var percentBp: Int?
    var base: String
    var books: [MoneyShelfBook]
    /// «المفروض اليوم»: the limit spread evenly over the cycle, through today.
    var expectedTodayMinor: Int?
    var percentUsed: Int? { limitMinor.flatMap { $0 > 0 ? (spentMinor * 100) / $0 : nil } }
}

struct MoneyCategoriesReading: Equatable {
    var cycleID: UUID? = nil
    var shelves: [MoneyCategoryShelf]
    var totalLimitsMinor: Int
    var incomeMinor: Int
    var allowanceMinor: Int
    var autoCategorized: Int
    var daysLeft: Int
}

extension AppMoneyService {
    func loadCategories() throws -> MoneyCategoriesReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = app.prayerNow()
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        let cycle = try repo.cycle(at: now)
        let cycleRow = try context.fetch(FetchDescriptor<Cycle>()).first { $0.id == cycle?.id }
        let income = cycleRow?.incomeMinor ?? 0
        let allowance = cycle.map { CycleEngine.accruedDaily(through: $0.input.expectedLengthDays, $0.input) } ?? 0
        let length = max(1, cycle?.input.expectedLengthDays ?? 30), elapsed = min(length, max(1, cycle?.elapsedDays ?? 1))
        let movements = try repo.confirmedTransactions().filter { $0.cycleID != nil && $0.cycleID == cycle?.id }
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) && ["spend", "refund"].contains($0.kind) }
        func charged(_ row: MoneyTransaction) -> Int { -allocations.filter { $0.transactionID == row.id }.reduce(0) { $0 + $1.amountMinor } }
        let limits = try context.fetch(FetchDescriptor<CategoryLimit>()).filter(live)
        let rules = try context.fetch(FetchDescriptor<MerchantRule>()).filter(live)
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { live($0) && $0.mergedInto == nil }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let shelves: [MoneyCategoryShelf] = categories.map { category in
            let rows = movements.filter { $0.categoryID == category.id }
            let spent = rows.reduce(0) { $0 + charged($1) }
            let byMerchant = Dictionary(grouping: rows, by: { $0.merchant ?? $0.counterparty ?? "بلا اسم" }).mapValues { $0.reduce(0) { $0 + charged($1) } }
            var books = byMerchant.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { MoneyShelfBook(id: $0.key, name: $0.key, amountMinor: $0.value) }
            if books.count > 3 {
                let rest = books.dropFirst(2).reduce(0) { $0 + $1.amountMinor }
                books = Array(books.prefix(2)) + [MoneyShelfBook(id: "rest", name: "غيرها", amountMinor: rest)]
            }
            let limit = limits.filter { $0.categoryID == category.id }.max { $0.updatedAt < $1.updatedAt }
            let mode: CategoryLimitMode? = switch limit?.mode {
                case "fixed": .fixed(limitMinor: limit?.limitMinor ?? 0)
                case "percent": .percent(basisPoints: limit?.percentBp ?? 0, base: limit?.base == "allowance" ? .allowance : .income)
                default: nil
            }
            let effective = mode.flatMap { LimitEngine.effectiveLimit($0, cycleIncomeMinor: income, cycleAllowanceMinor: allowance) }
            return .init(id: category.id, name: category.name, spentMinor: spent, limitMinor: effective, mode: limit?.mode ?? "none", percentBp: limit?.percentBp,
                         base: limit?.base ?? "income", books: books, expectedTodayMinor: effective.map { $0 * elapsed / length })
        }
        // «تصنّفت وحدها»: confirmed movements this cycle that carry their merchant rule's category.
        let auto = movements.filter { row in
            guard let merchant = row.merchant ?? row.counterparty, let category = row.categoryID else { return false }
            let key = BankDedupe.normalize(merchant)
            return rules.contains { $0.pattern == key && $0.categoryID == category && !$0.ignore }
        }.count
        return .init(cycleID: cycle?.id, shelves: shelves, totalLimitsMinor: shelves.compactMap(\.limitMinor).reduce(0, +), incomeMinor: income, allowanceMinor: allowance,
                     autoCategorized: auto, daysLeft: max(1, length - elapsed + 1))
    }
}
