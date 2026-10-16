import Foundation

/// F11 as amended by RM7: Madar computes and does not give rulings. Every result is approximate («لو حال الحول اليوم»),
/// the gold price is per gram of 24K and entered by hand, and the debt choice is the user's, written under the number.
/// A silver basis or a loan-inclusive debt option is not added without the owner's specialist review (F11 pre-release).
public enum ZakatDebtsPolicy: String, Sendable { case unset, none, dueNow, allOwed }

public struct ZakatAccount: Equatable, Sendable {
    public var balanceMinor: Int
    public var owned: Bool
    /// Account.zakatInclude (default on for current, savings and cash).
    public var include: Bool
    public init(balanceMinor: Int, owned: Bool = true, include: Bool = true) { self.balanceMinor = balanceMinor; self.owned = owned; self.include = include }
}

public struct ZakatInput: Equatable, Sendable {
    public var accounts: [ZakatAccount]
    /// «أموال أخرى تُزكّى» — one number the user enters (gold, shares, debts owed to them).
    public var otherAssetsMinor: Int
    public var debtsPolicy: ZakatDebtsPolicy
    /// «عليك» in full, and what is due now (statements due, instalments that fell due unpaid).
    public var owedAllMinor: Int
    public var dueNowMinor: Int
    public var goldPricePerGramMinor: Int?
    public var goldPriceSetAt: Date?
    public var nisabMg: Int
    public var hawlStartHijri: String?
    public init(accounts: [ZakatAccount], otherAssetsMinor: Int = 0, debtsPolicy: ZakatDebtsPolicy = .unset, owedAllMinor: Int = 0, dueNowMinor: Int = 0,
                goldPricePerGramMinor: Int? = nil, goldPriceSetAt: Date? = nil, nisabMg: Int = 85_000, hawlStartHijri: String? = nil) {
        self.accounts = accounts; self.otherAssetsMinor = otherAssetsMinor; self.debtsPolicy = debtsPolicy; self.owedAllMinor = owedAllMinor
        self.dueNowMinor = dueNowMinor; self.goldPricePerGramMinor = goldPricePerGramMinor; self.goldPriceSetAt = goldPriceSetAt
        self.nisabMg = nisabMg; self.hawlStartHijri = hawlStartHijri
    }
}

public struct ZakatAssessment: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// debtsPolicy = unset: the screen asks before showing any number.
        case askDebts
        /// No gold price yet: the nisab cannot be known.
        case askGoldPrice
        /// «دون النصاب تقريبًا», with no amount.
        case belowNisab
        /// Pool × 2.5%, to the halala, approximate.
        case due(amountMinor: Int)
    }
    public var outcome: Outcome
    /// The pool before debts: included owned balances + other assets. Envelopes are parts of these balances, never added.
    public var poolMinor: Int
    public var deductedMinor: Int
    public var nisabMinor: Int?
    /// «السعر من … — حدّثه» when the price is older than 30 days.
    public var goldPriceStale: Bool
    /// No hawl date: the user picks a date to account for themselves each year.
    public var hawlUnknown: Bool
    /// Always true: «تقريبي».
    public let approximate = true
}

public enum ZakatEngine {
    public static let rateBasisPoints = 250
    public static let staleAfterDays = 30

    public static func assess(_ input: ZakatInput, now: Date) -> ZakatAssessment {
        let pool = input.accounts.filter { $0.owned && $0.include }.reduce(0) { $0 + $1.balanceMinor } + input.otherAssetsMinor
        let stale = input.goldPriceSetAt.map { now.timeIntervalSince($0) > Double(staleAfterDays) * 86_400 } ?? false
        let hawlUnknown = (input.hawlStartHijri ?? "").isEmpty
        // nisab = nisabMg ÷ 1000 × price per gram (24K).
        let nisab = input.goldPricePerGramMinor.map { MoneyMath.divideRounded(input.nisabMg * $0, by: 1_000) }
        var assessment = ZakatAssessment(outcome: .askDebts, poolMinor: pool, deductedMinor: 0, nisabMinor: nisab, goldPriceStale: stale, hawlUnknown: hawlUnknown)
        let deducted: Int
        switch input.debtsPolicy {
        case .unset: return assessment
        case .none: deducted = 0
        case .dueNow: deducted = input.dueNowMinor
        case .allOwed: deducted = input.owedAllMinor
        }
        assessment.deductedMinor = deducted
        guard let nisab else { assessment.outcome = .askGoldPrice; return assessment }
        let base = pool - deducted
        assessment.outcome = base < nisab ? .belowNisab : .due(amountMinor: MoneyMath.applying(basisPoints: rateBasisPoints, to: base))
        return assessment
    }
}
