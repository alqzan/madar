import Foundation

/// F04: minor-unit exponents and conversion to the home currency. The full ISO 4217 table is a data asset whose licence
/// waits for the owner (provenance `currency-minor-units`); until then the table is injected, and only the values §7.5
/// itself states are built in.
public struct CurrencyExponents: Sendable {
    public var exponents: [String: Int]
    public init(_ exponents: [String: Int]) { self.exponents = exponents }
    /// The values §7.5 states: SAR and USD 2, JPY 0, KWD, BHD and OMR 3.
    public static let specified = CurrencyExponents(["SAR": 2, "USD": 2, "JPY": 0, "KWD": 3, "BHD": 3, "OMR": 3])
    public func exponent(_ code: String) -> Int? { exponents[code] }
}

public enum FXError: Error, Equatable { case unknownCurrency(String), invalidRate(String) }

public enum FX {
    /// A rate is a canonical decimal string (ASCII digits, "." separator), > 0, ≤ 12 fraction digits (§11 FX rate).
    public static func parseRate(_ text: String) throws -> Decimal {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }),
              parts.count == 1 || parts[1].count <= 12,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { throw FXError.invalidRate(text) }
        return value
    }

    /// homeAmountMinor = round_half_away_from_zero(amountMinor × rate × 10^(homeExp − exp)); computed once at write and stored.
    public static func homeAmount(amountMinor: Int, currency: String, rate: String, home: String = "SAR", exponents: CurrencyExponents = .specified) throws -> Int {
        guard let exp = exponents.exponent(currency) else { throw FXError.unknownCurrency(currency) }
        guard let homeExp = exponents.exponent(home) else { throw FXError.unknownCurrency(home) }
        if currency == home { return amountMinor }
        var value = Decimal(amountMinor) * (try parseRate(rate))
        let shift = homeExp - exp
        if shift >= 0 { for _ in 0..<shift { value *= 10 } } else { for _ in 0..<(-shift) { value /= 10 } }
        var rounded = Decimal(), source = value
        // .plain rounds a tie away from zero.
        NSDecimalRound(&rounded, &source, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// A refund linked to its original uses the original rateAtTime, unless its own message states the home amount;
    /// a full refund returns the original home amount exactly.
    /// Partial refunds that together complete the original return its home amount exactly: the completing one gets
    /// home − Σ earlier refunds' home amounts, so no halala drifts.
    public static func refundHomeAmount(refundMinor: Int, original: (amountMinor: Int, homeAmountMinor: Int, currency: String, rate: String?),
                                        priorRefundsMinor: Int = 0, priorRefundsHomeMinor: Int = 0,
                                        statedHomeMinor: Int? = nil, home: String = "SAR", exponents: CurrencyExponents = .specified) throws -> Int {
        if let statedHomeMinor { return statedHomeMinor }
        if refundMinor + priorRefundsMinor == original.amountMinor { return original.homeAmountMinor - priorRefundsHomeMinor }
        guard let rate = original.rate else { return refundMinor }
        return try homeAmount(amountMinor: refundMinor, currency: original.currency, rate: rate, home: home, exponents: exponents)
    }
}
