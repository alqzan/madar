public enum ExpenseThreshold {
    public enum Rule: Equatable, Sendable { case dailies(Int), salaryPercent(basisPoints: Int), amount(Int) }
    public static func amount(_ rule: Rule, dailyMinor: Int?, salaryMinor: Int?) -> Int? {
        switch rule {
        case .amount(let n): return n > 0 ? n : nil
        case .salaryPercent(let bp): guard let salaryMinor, salaryMinor > 0, bp > 0 else { return nil }; return max(1, MoneyMath.applying(basisPoints: bp, to: salaryMinor))
        case .dailies(let n): guard let dailyMinor, dailyMinor > 0, n > 0 else { return nil }; let p = dailyMinor.multipliedReportingOverflow(by: n); return p.overflow ? nil : p.partialValue
        }
    }
}
