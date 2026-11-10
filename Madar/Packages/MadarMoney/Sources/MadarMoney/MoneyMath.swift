/// Integer money arithmetic (§7.5 «المبالغ في النموذج»): amounts are Int minor units, ratios are Int basis points
/// (10 000 = 100%), never Double.
public enum MoneyMath {
    public static let basisPointsPerWhole = 10_000

    /// a × bp ÷ 10 000, rounded half away from zero (the rounding §7.5 F04 names for money).
    public static func applying(basisPoints bp: Int, to amount: Int) -> Int {
        // Split before multiplying so a valid percentage of a representable amount does not overflow.
        // The remainder is smaller than 10,000, and the whole part cannot exceed the amount for 0...100%.
        guard (0...basisPointsPerWhole).contains(bp) else {
            // Outside 0…100% the product can exceed Int: saturate instead of trapping on an imported or mistyped value.
            let product = amount.multipliedReportingOverflow(by: bp)
            if product.overflow { return (amount < 0) == (bp < 0) ? Int.max : Int.min }
            return divideRounded(product.partialValue, by: basisPointsPerWhole)
        }
        let whole = amount / basisPointsPerWhole
        let remainder = amount % basisPointsPerWhole
        return whole * bp + divideRounded(remainder * bp, by: basisPointsPerWhole)
    }

    /// n ÷ d rounded half away from zero; d > 0.
    public static func divideRounded(_ n: Int, by d: Int) -> Int {
        precondition(d > 0)
        let q = n / d, r = n % d
        guard 2 * abs(r) >= d else { return q }
        return n >= 0 ? q + 1 : q - 1
    }

    /// An exact split to the minor unit: every part gets ⌊total ÷ parts⌋, the remainder goes on the last part (L06, L07, L12).
    public static func split(_ total: Int, into parts: Int) -> (each: Int, lastRemainder: Int) {
        precondition(parts > 0 && total >= 0)
        return (total / parts, total % parts)
    }
}
