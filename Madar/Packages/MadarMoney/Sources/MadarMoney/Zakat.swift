import Foundation

/// F11 as amended by RM7: Madar computes and does not give rulings. Every result is approximate («لو حال الحول اليوم»),
/// the gold price is per gram of 24K and entered by hand, and the debt choice is the user's, written under the number.
/// RM7 also makes the nisab basis an explicit choice (gold 24K or silver) and defines a debt option that includes the
/// loan. Screen copy and options still pass the owner's specialist review before release (F11).
public enum ZakatDebtsPolicy: String, Sendable { case unset, none, dueNow, allOwed, allOwedAndLoan }
public enum NisabBasis: String, Sendable { case gold, silver }

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
    /// The loan's remaining balance (outside «عليك», RM9), deducted only under allOwedAndLoan.
    public var loanRemainingMinor: Int
    public var nisabBasis: NisabBasis
    public var goldPricePerGramMinor: Int?
    public var goldPriceSetAt: Date?
    public var nisabMg: Int
    public var silverPricePerGramMinor: Int?
    public var silverPriceSetAt: Date?
    public var nisabSilverMg: Int
    public var hawlStartHijri: String?
    public init(accounts: [ZakatAccount], otherAssetsMinor: Int = 0, debtsPolicy: ZakatDebtsPolicy = .unset, owedAllMinor: Int = 0, dueNowMinor: Int = 0,
                loanRemainingMinor: Int = 0, nisabBasis: NisabBasis = .gold, goldPricePerGramMinor: Int? = nil, goldPriceSetAt: Date? = nil, nisabMg: Int = 85_000,
                silverPricePerGramMinor: Int? = nil, silverPriceSetAt: Date? = nil, nisabSilverMg: Int = 595_000, hawlStartHijri: String? = nil) {
        self.accounts = accounts; self.otherAssetsMinor = otherAssetsMinor; self.debtsPolicy = debtsPolicy; self.owedAllMinor = owedAllMinor
        self.dueNowMinor = dueNowMinor; self.loanRemainingMinor = loanRemainingMinor; self.nisabBasis = nisabBasis
        self.goldPricePerGramMinor = goldPricePerGramMinor; self.goldPriceSetAt = goldPriceSetAt; self.nisabMg = nisabMg
        self.silverPricePerGramMinor = silverPricePerGramMinor; self.silverPriceSetAt = silverPriceSetAt; self.nisabSilverMg = nisabSilverMg
        self.hawlStartHijri = hawlStartHijri
    }
}

public struct ZakatAssessment: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// debtsPolicy = unset: the screen asks before showing any number.
        case askDebts
        /// No price for the chosen basis yet: the nisab cannot be known.
        case askPrice
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
        let gold = input.nisabBasis == .gold
        let price = gold ? input.goldPricePerGramMinor : input.silverPricePerGramMinor
        let setAt = gold ? input.goldPriceSetAt : input.silverPriceSetAt
        let stale = setAt.map { now.timeIntervalSince($0) > Double(staleAfterDays) * 86_400 } ?? false
        let hawlUnknown = (input.hawlStartHijri ?? "").isEmpty
        // nisab = milligrams ÷ 1000 × price per gram (gold 24K: 85 g; silver: 595 g).
        let nisab = price.map { MoneyMath.divideRounded((gold ? input.nisabMg : input.nisabSilverMg) * $0, by: 1_000) }
        var assessment = ZakatAssessment(outcome: .askDebts, poolMinor: pool, deductedMinor: 0, nisabMinor: nisab, goldPriceStale: stale, hawlUnknown: hawlUnknown)
        let deducted: Int
        switch input.debtsPolicy {
        case .unset: return assessment
        case .none: deducted = 0
        case .dueNow: deducted = input.dueNowMinor
        case .allOwed: deducted = input.owedAllMinor
        case .allOwedAndLoan: deducted = input.owedAllMinor + input.loanRemainingMinor
        }
        assessment.deductedMinor = deducted
        guard let nisab else { assessment.outcome = .askPrice; return assessment }
        let base = pool - deducted
        assessment.outcome = base < nisab ? .belowNisab : .due(amountMinor: MoneyMath.applying(basisPoints: rateBasisPoints, to: base))
        return assessment
    }
}
