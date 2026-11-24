import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

enum MoneySafeArithmetic {
    static func percent(_ part: Int, of whole: Int, rounded: Bool = true) -> Int {
        guard whole > 0 else { return 0 }
        return ratio(part, multiplier: 100, over: whole, rounding: rounded ? .plain : .down)
    }

    static func ratio(_ value: Int, multiplier: Int, over denominator: Int) -> Int {
        ratio(value, multiplier: multiplier, over: denominator, rounding: .down)
    }

    static func sum(_ values: [Int]) -> Int {
        let total = values.reduce(Decimal(0)) { $0 + Decimal(Int64($1)) }
        return boundedInteger(total, rounding: .down)
    }

    private static func ratio(_ value: Int, multiplier: Int, over denominator: Int, rounding: NSDecimalNumber.RoundingMode) -> Int {
        guard denominator > 0 else { return 0 }
        let exact = Decimal(Int64(value)) * Decimal(Int64(multiplier)) / Decimal(Int64(denominator))
        return boundedInteger(exact, rounding: rounding)
    }

    private static func boundedInteger(_ value: Decimal, rounding: NSDecimalNumber.RoundingMode) -> Int {
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 0, rounding)
        if rounded >= Decimal(Int64.max) { return Int.max }
        if rounded <= Decimal(Int64.min) { return Int.min }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

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
    var percentUsed: Int? { limitMinor.flatMap { $0 > 0 ? MoneySafeArithmetic.percent(max(0, spentMinor), of: $0, rounded: false) : nil } }
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

extension CategoryLimit {
    static func latestByCategory(in context: ModelContext) throws -> [UUID: CategoryLimit] {
        let rows = try context.fetch(FetchDescriptor<CategoryLimit>(predicate: #Predicate {
            $0.deletedAt == nil && $0.mergedInto == nil
        }))
        var latest: [UUID: CategoryLimit] = [:]
        for row in rows {
            guard let categoryID = row.categoryID else { continue }
            if let current = latest[categoryID],
               (current.updatedAt, current.id.uuidString) >= (row.updatedAt, row.id.uuidString) { continue }
            latest[categoryID] = row
        }
        return latest
    }

    var effectiveMode: CategoryLimitMode {
        switch mode {
        case "fixed": .fixed(limitMinor: limitMinor)
        case "percent": .percent(basisPoints: percentBp ?? 0, base: base == "allowance" ? .allowance : .income)
        default: .none
        }
    }
}

extension AppMoneyService {
    func loadCategories(at instant: Date? = nil) throws -> MoneyCategoriesReading {
        try requireReadableStore()
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = instant ?? app.prayerNow()
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        let cycle = try repo.cycle(at: now)
        let income = cycle?.incomeMinor ?? 0
        let allowance = cycle.map { CycleEngine.accruedDaily(through: $0.input.expectedLengthDays, $0.input) } ?? 0
        let length = max(1, cycle?.input.expectedLengthDays ?? 30), elapsed = min(length, max(1, cycle?.elapsedDays ?? 1))
        let movements: [MoneyTransaction]
        if let cycle { movements = try repo.confirmedTransactions().filter { $0.cycleID == cycle.id } }
        else { movements = [] }
        let movementsByCategory = Dictionary(grouping: movements, by: \.categoryID)
        let movementIDs = Set(movements.map(\.id))
        var charges: [UUID: Int] = [:]
        if !movementIDs.isEmpty {
            for allocation in try context.fetch(FetchDescriptor<Allocation>()) {
                guard let id = allocation.transactionID, movementIDs.contains(id), live(allocation),
                      allocation.kind == "spend" || allocation.kind == "refund" else { continue }
                charges[id, default: 0] -= allocation.amountMinor
            }
        }
        func charged(_ row: MoneyTransaction) -> Int { charges[row.id] ?? 0 }
        let limits = try CategoryLimit.latestByCategory(in: context)
        let rules = try context.fetch(FetchDescriptor<MerchantRule>()).filter { live($0) && !$0.ignore }
        let legacyRules = Dictionary(grouping: rules, by: \.pattern)
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { live($0) && $0.mergedInto == nil }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let shelves: [MoneyCategoryShelf] = categories.map { category in
            let rows = movementsByCategory[category.id] ?? []
            let spent = rows.reduce(0) { $0 + charged($1) }
            let byMerchant = Dictionary(grouping: rows, by: { $0.merchant ?? $0.counterparty ?? "بلا اسم" }).mapValues { $0.reduce(0) { $0 + charged($1) } }
            var books = byMerchant.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { MoneyShelfBook(id: $0.key, name: $0.key, amountMinor: $0.value) }
            if books.count > 3 {
                let rest = books.dropFirst(2).reduce(0) { $0 + $1.amountMinor }
                books = Array(books.prefix(2)) + [MoneyShelfBook(id: "rest", name: "غيرها", amountMinor: rest)]
            }
            let limit = limits[category.id]
            let effective = LimitEngine.effectiveLimit(limit?.effectiveMode ?? .none, cycleIncomeMinor: income, cycleAllowanceMinor: allowance)
            return .init(id: category.id, name: category.name, spentMinor: spent, limitMinor: effective, mode: limit?.mode ?? "none", percentBp: limit?.percentBp,
                         base: limit?.base ?? "income", books: books, expectedTodayMinor: effective.map {
                             MoneySafeArithmetic.ratio($0, multiplier: elapsed, over: length)
                         })
        }
        let auto = movements.filter { row in
            guard let category = row.categoryID else { return false }
            if row.categorySource == "learned" || row.categorySource == "rule" { return true }
            // Records created before category provenance was stored can still match an old merchant rule.
            guard row.categorySource == nil, let merchant = row.merchant ?? row.counterparty else { return false }
            return legacyRules[BankDedupe.normalize(merchant)]?.contains { $0.categoryID == category } == true
        }.count
        return .init(cycleID: cycle?.id, shelves: shelves, totalLimitsMinor: MoneySafeArithmetic.sum(shelves.compactMap(\.limitMinor)), incomeMinor: income, allowanceMinor: allowance,
                     autoCategorized: auto, daysLeft: max(1, length - elapsed + 1))
    }
}
