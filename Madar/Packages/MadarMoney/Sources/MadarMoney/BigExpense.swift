/// The four distributions in §7.5. All sources add up to the purchase to the minor unit (F02/L12).
public enum BigExpense {
    public enum Mode: String, CaseIterable, Sendable { case mixed, installments, daily, reserve }
    public struct Plan: Equatable, Sendable {
        public var dailyMinor: Int
        public var surplusMinor: Int
        public var reserveMinor: Int
        public var futureMinor: Int
        public var paymentsMinor: [Int]
        /// Lowest daily in the forecast: the final day carries all division remainders (L06).
        public var lowestDailyMinor: Int
        public var cycles: Int { paymentsMinor.count }
        public var repaymentMinor: Int { paymentsMinor.reduce(0, +) }
    }
    /// Smallest allowed number of cycles. The largest daily drop, including the remainder, must be at most a third
    /// of the actual daily amount. At most twelve cycles (§7.5); no plan is invented when there is no daily amount.
    public static func minimumCycles(debtMinor: Int, dailyMinor: Int, cycleDays: Int) -> Int? {
        guard debtMinor > 0, dailyMinor > 0, cycleDays > 0 else { return nil }
        return (1...12).first { count in
            let split = MoneyMath.split(debtMinor, into: count)
            let last = split.each + split.lastRemainder
            let drop = MoneyMath.split(last, into: cycleDays)
            return drop.each + drop.lastRemainder <= dailyMinor / 3
        }
    }
    public static func plan(amountMinor: Int, mode: Mode, availableMinor: Int, surplusMinor: Int, reserveMinor: Int,
                            dailyMinor: Int, cycleDays: Int, cycles: Int? = nil, envelopeBalanceMinor: Int = 0) -> Plan? {
        guard amountMinor > 0, cycleDays > 0 else { return nil }
        var daily = 0, surplus = 0, reserve = 0, debt = 0
        switch mode {
        case .mixed:
            daily = min(amountMinor, max(0, availableMinor)); surplus = min(amountMinor - daily, max(0, surplusMinor)); debt = amountMinor - daily - surplus
        case .installments: debt = amountMinor
        case .daily: daily = amountMinor
        case .reserve: guard reserveMinor >= amountMinor else { return nil }; reserve = amountMinor
        }
        var payments: [Int] = [], lowest = dailyMinor
        let repayment = max(0, debt - max(0, envelopeBalanceMinor))
        if repayment > 0 {
            guard let minimum = minimumCycles(debtMinor: repayment, dailyMinor: dailyMinor, cycleDays: cycleDays) else { return nil }
            let n = cycles ?? minimum
            guard (minimum...12).contains(n) else { return nil }
            let split = MoneyMath.split(repayment, into: n)
            payments = (0..<n).map { split.each + ($0 == n - 1 ? split.lastRemainder : 0) }
            let drop = MoneyMath.split(payments.last!, into: cycleDays)
            lowest -= drop.each + drop.lastRemainder
        }
        return .init(dailyMinor: daily, surplusMinor: surplus, reserveMinor: reserve, futureMinor: debt, paymentsMinor: payments, lowestDailyMinor: lowest)
    }
}
