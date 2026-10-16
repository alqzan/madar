import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyRuleRow: Identifiable, Equatable {
    var id: UUID
    var merchant: String
    var categoryID: UUID?
    var ignore: Bool
    var count: Int
    var lastAt: Date?
    var learnedAt: Date
}

struct MoneyRuleCategory: Identifiable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var merchants: Int
    var times: Int
}

struct MoneyRuleConflict: Identifiable, Equatable {
    struct Option: Equatable { var categoryID: UUID; var name: String; var count: Int }
    var id: String { pattern }
    var pattern: String
    var merchant: String
    var options: [Option]
}

struct MoneyRulesReading: Equatable {
    var rules: [MoneyRuleRow]
    var categories: [MoneyRuleCategory]
    var allCategories: [MoneyRuleCategory]
    var conflicts: [MoneyRuleConflict]
    var applied: Int
}

extension AppMoneyService {
    func categories() throws -> [MoneyRuleCategory] {
        try ModelContext(app.container).fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
            .map { .init(id: $0.id, name: $0.name, icon: $0.icon, merchants: 0, times: 0) }
    }

    func loadRules() throws -> MoneyRulesReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container)
        let rules = try context.fetch(FetchDescriptor<MerchantRule>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let all = try categories()
        func pattern(_ row: MoneyTransaction) -> String? { (row.merchant ?? row.counterparty).map(BankDedupe.normalize).flatMap { $0.isEmpty ? nil : $0 } }
        let byPattern = Dictionary(grouping: rows.filter { pattern($0) != nil }, by: { pattern($0)! })
        var ruleRows: [MoneyRuleRow] = rules.map { rule -> MoneyRuleRow in
            let matching = byPattern[rule.pattern] ?? []
            // Shown as the user last saw it in a message, not the normalized key.
            let latest: MoneyTransaction? = matching.max { $0.eventAt < $1.eventAt }
            let display: String = latest?.merchant ?? latest?.counterparty ?? rule.pattern
            let lastAt: Date? = latest?.eventAt
            return MoneyRuleRow(id: rule.id, merchant: display, categoryID: rule.categoryID, ignore: rule.ignore, count: matching.count, lastAt: lastAt, learnedAt: rule.createdAt)
        }
        ruleRows.sort { (a: MoneyRuleRow, b: MoneyRuleRow) -> Bool in a.count == b.count ? a.merchant < b.merchant : a.count > b.count }
        // «طُبّقت»: movements whose merchant has a rule and that carry the rule's decision.
        var applied = 0
        for rule in rules {
            for row in byPattern[rule.pattern] ?? [] {
                // Only movements that arrived after the rule's last change, and that the user confirmed.
                guard row.reviewState == "ok", row.createdAt >= rule.updatedAt else { continue }
                let carries: Bool = rule.ignore ? row.ignoredFromBudget : row.categoryID == rule.categoryID
                if carries { applied += 1 }
            }
        }
        let categories = all.map { category -> MoneyRuleCategory in
            var c = category
            c.merchants = rules.filter { $0.categoryID == category.id && !$0.ignore }.count
            c.times = rows.filter { $0.categoryID == category.id && $0.reviewState == "ok" }.count
            return c
        }
        // A merchant the user filed under two categories, with no rule yet: ask which one holds.
        let ruled = Set(rules.map(\.pattern))
        let conflicts: [MoneyRuleConflict] = byPattern.compactMap { key, list in
            guard !ruled.contains(key) else { return nil }
            let counts = Dictionary(grouping: list.filter { $0.reviewState == "ok" && $0.categoryID != nil }, by: { $0.categoryID! }).mapValues(\.count)
            guard counts.count >= 2 else { return nil }
            let options = counts.sorted { $0.value == $1.value ? $0.key.uuidString < $1.key.uuidString : $0.value > $1.value }.prefix(2).compactMap { id, count in
                all.first { $0.id == id }.map { MoneyRuleConflict.Option(categoryID: id, name: $0.name, count: count) }
            }
            guard options.count == 2 else { return nil }
            return .init(pattern: key, merchant: list.max { $0.eventAt < $1.eventAt }.flatMap { $0.merchant ?? $0.counterparty } ?? key, options: options)
        }.sorted { $0.merchant < $1.merchant }
        return .init(rules: ruleRows, categories: categories.filter { $0.merchants > 0 }, allCategories: categories, conflicts: conflicts, applied: applied)
    }
}
