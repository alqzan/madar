/// F07: read-only estimates. Bank statements remain authoritative; forecasts never book a movement.
public enum CardPlanning {
    /// Minor-unit result, half away from zero, with full-width multiplication.
    /// Used only for nonnegative amounts and rates; unavailable inputs stay unavailable.
    public static func rateAmount(_ amountMinor: Int, numerator: Int, denominator: Int) -> Int? {
        guard amountMinor >= 0, numerator >= 0, denominator > 0 else { return nil }
        let product = UInt(amountMinor).multipliedFullWidth(by: UInt(numerator))
        guard product.high < UInt(denominator) else { return nil }
        let division = UInt(denominator).dividingFullWidth(product)
        let rounded = division.quotient.addingReportingOverflow(division.remainder >= (UInt(denominator) + 1) / 2 ? 1 : 0)
        guard !rounded.overflow, rounded.partialValue <= UInt(Int.max) else { return nil }
        return Int(rounded.partialValue)
    }
    public static func cashbackEstimate(purchaseMinor: Int, rateBp: Int?) -> Int? {
        guard let rateBp, (0...10_000).contains(rateBp) else { return nil }
        return rateAmount(purchaseMinor, numerator: rateBp, denominator: 10_000)
    }
    /// Explicit simple-interest scenario over the supplied number of days, annual rate / 365.
    /// Does not model a bank's compounding, fees or grace-period conditions.
    public static func interestEstimate(unpaidMinor: Int, annualRateBp: Int?, days: Int) -> Int? {
        guard let annualRateBp, (0...100_000).contains(annualRateBp), (0...366).contains(days) else { return nil }
        return rateAmount(unpaidMinor, numerator: annualRateBp * days, denominator: 3_650_000)
    }
    public static func utilisationBp(owedMinor: Int, limitMinor: Int?) -> Int? {
        guard let limitMinor, limitMinor > 0 else { return nil }
        return rateAmount(owedMinor, numerator: 10_000, denominator: limitMinor)
    }
    /// Cash coverage of known due items in date order. No unconfirmed salary is assumed.
    public static func cashAfter(availableMinor: Int, dueMinor: [Int]) -> [Int]? {
        var cash = availableMinor, result: [Int] = []
        for amount in dueMinor {
            guard amount >= 0 else { return nil }
            let next = cash.subtractingReportingOverflow(amount); guard !next.overflow else { return nil }
            cash = next.partialValue; result.append(cash)
        }
        return result
    }
}
