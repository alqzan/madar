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
        var parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        // «١٬٥٠٠» and «1,500» are thousands groups. They are accepted only as proper groups of three, so «1,5» is
        // refused instead of silently becoming 15.
        if let head = parts.first, head.contains(where: { ",٬،".contains($0) }) {
            let groups = head.split(omittingEmptySubsequences: false, whereSeparator: { ",٬،".contains($0) })
            guard let first = groups.first, (1...3).contains(first.count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            parts[0] = Substring(groups.joined())
        }
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
