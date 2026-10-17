import Foundation

/// Decimal input to currency minor units, without binary floating point or truncating a fraction.
public enum MoneyAmountInput {
    public static func minor(_ raw: String, exponent: Int) -> Int? {
        guard (0...3).contains(exponent) else { return nil }
        // Arabic decimal keyboards emit Arabic-Indic digits and the Arabic decimal separator.
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).map { c -> String in
            if let n = c.wholeNumberValue, n < 10 { return String(n) }
            if c == "٫" { return "." }
            return String(c)
        }.joined()
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
              let whole = Int(parts[0]) else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= exponent || fraction.dropFirst(exponent).allSatisfy({ $0 == "0" }) else { return nil }
        var scale = 1
        for _ in 0..<exponent { scale *= 10 }
        let digits = String(fraction.prefix(exponent)).padding(toLength: exponent, withPad: "0", startingAt: 0)
        let product = whole.multipliedReportingOverflow(by: scale)
        let result = product.partialValue.addingReportingOverflow(Int(digits) ?? 0)
        guard !product.overflow, !result.overflow else { return nil }
        return result.partialValue
    }
}
