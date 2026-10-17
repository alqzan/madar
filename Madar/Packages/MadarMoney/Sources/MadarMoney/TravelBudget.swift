import Foundation

/// The trip's envelope is the budget. Its planned return is an Envelope.due, never Trip.end (actual return).
public enum TravelBudget {
    public static func dailyMinor(targetMinor: Int, durationDays: Int, day: Int) -> Int? {
        guard targetMinor >= 0, durationDays > 0, day > 0, day <= durationDays else { return nil }
        return targetMinor / durationDays + (day == durationDays ? targetMinor % durationDays : 0)
    }
    public static func stampsRemaining(dailyMinor: Int, spentMinor: Int) -> Int {
        guard dailyMinor > 0 else { return 0 }
        let left = spentMinor <= 0 ? dailyMinor : max(0, dailyMinor - spentMinor)
        return Int(UInt(dailyMinor).dividingFullWidth(UInt(left).multipliedFullWidth(by: 10)).quotient)
    }
    /// Display only: the saved home amount remains authoritative; no round-trip conversion is written.
    public static func foreignAmount(homeMinor: Int, currency: String, rate: String, home: String = "SAR", exponents: CurrencyExponents = .specified) throws -> Int {
        guard let foreignExp = exponents.exponent(currency) else { throw FXError.unknownCurrency(currency) }
        guard let homeExp = exponents.exponent(home) else { throw FXError.unknownCurrency(home) }
        if currency == home { return homeMinor }
        var value = Decimal(homeMinor) / (try FX.parseRate(rate))
        let shift = foreignExp - homeExp
        if shift >= 0 { for _ in 0..<shift { value *= 10 } } else { for _ in 0..<(-shift) { value /= 10 } }
        var rounded = Decimal(); NSDecimalRound(&rounded, &value, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int.max), rounded >= Decimal(Int.min) else { throw FXError.amountOverflow }
        return NSDecimalNumber(decimal: rounded).intValue
    }
    public static func canonicalRate(_ raw: String) -> String? {
        let ascii = raw.trimmingCharacters(in: .whitespacesAndNewlines).map { c -> String in
            if let n = c.wholeNumberValue, n < 10 { return String(n) }
            return c == "٫" ? "." : String(c)
        }.joined()
        guard ascii.count <= 40, (try? FX.parseRate(ascii)) != nil else { return nil }
        return ascii
    }
}
