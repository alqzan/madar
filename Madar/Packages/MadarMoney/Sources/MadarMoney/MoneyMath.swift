/// Integer money arithmetic (§7.5 «المبالغ في النموذج»): amounts are Int minor units, ratios are Int basis points
/// (10 000 = 100%), never Double.
public enum MoneyMath {
    public static let basisPointsPerWhole = 10_000

    /// a × bp ÷ 10 000, rounded half away from zero (the rounding §7.5 F04 names for money).
    public static func applying(basisPoints bp: Int, to amount: Int) -> Int {
        divideRounded(amount * bp, by: basisPointsPerWhole)
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
