import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One way to pay in «سجّل مصروفًا»: the cash wallet, a card, or an own account. Each names its account or card
/// explicitly, so the command never has to guess between several accounts.
struct MoneyPaymentChoice: Identifiable, Equatable {
    enum Kind: String { case cash, debit, credit, prepaid, account }
    var id: String
    var title: String
    var kind: Kind
    var cardID: UUID?
    var accountID: UUID?
    /// What the money leaves: the wallet or account balance now (nil for a credit card).
    var balanceMinor: Int?
    var accountName: String?
    /// Credit only: owed now, the limit when known, and the day this purchase's cash leaves («متى يخرج النقد»).
    var owedMinor: Int = 0
    var limitMinor: Int?
    var purchaseDue: GregorianDay?
    var currency: String = "SAR"
}
struct MoneyExpenseMerchant: Identifiable, Equatable {
    var id: String { name }
    var name: String
    /// A category suggested from repeated manual choices; every purchase can choose another.
    var categoryID: UUID?
    var categorySource: String?
    var hasMultipleLearnedCategories: Bool
    /// The way this merchant was paid last time.
    var methodID: String?
}
struct MoneyExpenseCategory: Identifiable, Equatable {
    var id: UUID
    var name: String
    var spentMinor: Int?
    var limitMinor: Int?
    var preferredCardID: UUID?
    var preferredCardName: String?
}
/// A movement already on the books near the chosen time, for «تبدو مسجّلة» before saving (RM8 the other way round).
struct MoneyExpenseNearby {
    var methodID: String?
    var amountMinor: Int
    var currency: String
    var at: Date
    var merchant: String?
    var fromMessage: Bool
}
struct MoneyExpenseReading {
    var currency: String
    var cycle: MoneyCycleReading?
    var today: GregorianDay
    /// The earliest day an expense may be dated: the open cycle's first day, else 60 days back.
    var earliest: Date
    var methods: [MoneyPaymentChoice]
    var defaultMethodID: String?
    var merchants: [MoneyExpenseMerchant]
    var categories: [MoneyExpenseCategory]
    var envelopes: [MoneyHomeEnvelope]
    var cashCountedAtWithdrawal: Bool
    var diaryOn: Bool
    var nearby: [MoneyExpenseNearby]
    var tripCurrency: String? = nil
    var tripRate: String? = nil
    var tripEnvelopeID: UUID? = nil
    var merchantLearningIndex: MerchantCategoryLearning.Index = .empty
    var merchantLearningThreshold: Int = 3

    func merchantLearning(for name: String) -> MerchantCategoryLearning.Result {
        merchantLearningIndex.result(for: name, threshold: merchantLearningThreshold)
    }
}

extension AppMoneyService {
    func expenseDay(at instant: Date) throws -> GregorianDay { try DiaryLineRenderer.today(context: ModelContext(app.container), now: instant) }
    func loadExpense(at instant: Date? = nil) throws -> MoneyExpenseReading {
        let now = instant ?? app.prayerNow(), zone = app.activePlace.timeZone
        let home = try load(at: now), context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let trip = try repo.trip(at: now)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.ownership == "mine" && $0.tracked && ($0.currency == home.currency || $0.currency == trip?.currency) }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { card in card.deletedAt == nil && card.mergedInto == nil && (card.accountID == nil || accounts.contains { $0.id == card.accountID }) }
        let cardReadings = try loadCards(at: now).cards
        let confirmed = try repo.confirmedTransactions()
        let used = confirmed.filter { $0.kind == "expense" }.sorted { $0.eventAt > $1.eventAt }
        let settingStore = try SettingsStore(context: context)
        let learningThreshold = Int(try settingStore.value(for: "mal.merchantLearnAfter").number ?? 3)
        let liveCategories = try context.fetch(FetchDescriptor<MadarData.Category>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let liveCategoryIDs = Set(liveCategories.map(\.id))
        let learningSamples = confirmed.map { row in
            MerchantCategoryLearning.Sample(transactionID: row.id, merchant: row.merchant ?? row.counterparty,
                categoryID: row.categoryID, categorySource: row.categorySource, kind: row.kind,
                reviewState: row.reviewState, isDeleted: row.deletedAt != nil, isMerged: row.mergedInto != nil)
        }
        let learningIndex = MerchantCategoryLearning.makeIndex(samples: learningSamples, liveCategoryIDs: liveCategoryIDs)
        func methodID(_ row: MoneyTransaction) -> String? {
            if let card = row.cardID { return "card:" + card.uuidString }
            if let accountID = row.fromAccountID, let account = accounts.first(where: { $0.id == accountID }) {
                if account.kind == "cash" {
                    return account.currency == home.currency ? "cash" : "cash:" + account.id.uuidString
                }
                return "account:" + account.id.uuidString
            }
            return nil
        }
        var methods: [MoneyPaymentChoice] = []
        // An explicit wallet per currency; never guess between two cash wallets in the same currency.
        let wallets = accounts.filter { $0.kind == "cash" }
        for wallet in wallets where wallets.filter({ $0.currency == wallet.currency }).count == 1 {
            let key = wallet.currency == home.currency ? "cash" : "cash:" + wallet.id.uuidString
            methods.append(.init(id: key, title: wallet.currency == home.currency ? "كاش" : "نقد، " + currencyName(wallet.currency), kind: .cash, accountID: wallet.id, balanceMinor: try? repo.accountBalance(wallet, at: now), accountName: wallet.name, currency: wallet.currency))
        }
        for card in cards {
            let reading = cardReadings.first { $0.id == card.id }, owner = accounts.first { $0.id == card.accountID }
            let kind: MoneyPaymentChoice.Kind = card.kind == "credit" ? .credit : card.kind == "prepaid" ? .prepaid : .debit
            methods.append(.init(id: "card:" + card.id.uuidString, title: card.name, kind: kind, cardID: card.id, accountID: card.accountID,
                balanceMinor: kind == .credit ? nil : owner.flatMap { try? repo.accountBalance($0, at: now) }, accountName: owner?.name,
                owedMinor: reading?.owedMinor ?? 0, limitMinor: card.limitMinor, purchaseDue: kind == .credit ? reading?.purchaseDue : nil, currency: owner?.currency ?? home.currency))
        }
        for account in accounts where ["current", "savings", "wallet"].contains(account.kind) {
            methods.append(.init(id: "account:" + account.id.uuidString, title: account.name, kind: .account, accountID: account.id,
                balanceMinor: try? repo.accountBalance(account, at: now), accountName: account.name, currency: account.currency))
        }
        // The way of paying used most recently comes first among equals; otherwise the order above.
        let recentMethod = used.lazy.compactMap(methodID).first { id in methods.contains { $0.id == id } }
        let since = now.addingTimeInterval(-90 * 86_400)
        var tally: [String: (count: Int, last: Date, method: String?)] = [:]
        for row in used where row.eventAt >= since {
            guard let name = (row.merchant ?? row.counterparty)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            var entry = tally[name] ?? (0, row.eventAt, methodID(row))
            entry.count += 1
            tally[name] = entry
        }
        let merchants = try tally.sorted { $0.value.count == $1.value.count ? $0.value.last > $1.value.last : $0.value.count > $1.value.count }.prefix(10).compactMap { name, entry -> MoneyExpenseMerchant? in
            let rule = try repo.merchantRule(for: name)
            if rule?.ignore == true { return nil }
            let learning = learningIndex.result(for: name, threshold: learningThreshold)
            return .init(name: name, categoryID: learning.suggestedCategoryID,
                categorySource: learning.suggestedCategoryID == nil ? nil : "learned",
                hasMultipleLearnedCategories: learning.hasMultipleQualifiedCategories,
                methodID: entry.method.flatMap { id in methods.contains { $0.id == id } ? id : nil })
        }
        let categories = liveCategories.map { category in
                let limit = home.limits.first { $0.id == category.id }
                let preferred = category.preferredCardID.flatMap { id in cards.first { $0.id == id && $0.kind == "credit" } }
                return MoneyExpenseCategory(id: category.id, name: category.name, spentMinor: limit?.spentMinor, limitMinor: limit?.limitMinor,
                    preferredCardID: preferred?.id, preferredCardName: preferred?.name)
            }
        let start = home.cycle?.startDay.date(in: zone) ?? now.addingTimeInterval(-60 * 86_400)
        let nearby = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && ["expense", "fee"].contains($0.kind) && abs($0.eventAt.timeIntervalSince(now)) < 2 * 86_400 }
            .map { MoneyExpenseNearby(methodID: methodID($0), amountMinor: $0.amountMinor, currency: $0.currency, at: $0.eventAt, merchant: $0.merchant ?? $0.counterparty, fromMessage: $0.messageID != nil) }
        return .init(currency: home.currency, cycle: home.cycle, today: today, earliest: start, methods: methods,
            defaultMethodID: recentMethod ?? methods.first(where: { $0.kind != .cash })?.id ?? methods.first?.id,
            merchants: merchants, categories: categories, envelopes: home.envelopes,
            cashCountedAtWithdrawal: try settingStore.value(for: "mal.cashWithdrawalAsSpend") == .bool(true),
            diaryOn: app.values["notes.autoLines"]?.object?["mal"] != .bool(false), nearby: nearby, tripCurrency: trip?.currency, tripRate: trip?.fxRateToHome, tripEnvelopeID: trip?.journeyKey,
            merchantLearningIndex: learningIndex, merchantLearningThreshold: learningThreshold)
    }
}
