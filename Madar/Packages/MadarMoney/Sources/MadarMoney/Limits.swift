/// Category limits and the linked «ضمن يومك» habit (F06, L05).
public enum CategoryLimitMode: Equatable, Sendable {
    public enum Base: String, Sendable { case income, allowance }
    /// No limit. Distinct from a fixed 0, which is a real limit (L05: 0 ≠ nil).
    case none
    case fixed(limitMinor: Int)
    /// Recomputed every cycle from its base, never turned into a fixed number.
    case percent(basisPoints: Int, base: Base)
}

public enum LimitEngine {
    /// The limit in force for one cycle; nil = no limit.
    public static func effectiveLimit(_ mode: CategoryLimitMode, cycleIncomeMinor: Int, cycleAllowanceMinor: Int) -> Int? {
        switch mode {
        case .none: return nil
        case .fixed(let limit): return limit
        case .percent(let bp, let base):
            return MoneyMath.applying(basisPoints: bp, to: base == .income ? cycleIncomeMinor : cycleAllowanceMinor)
        }
    }

    /// The 80% alert fires once per (category, cycle), when spending reaches 80% of the limit; a fixed 0 alerts on any spend.
    public static func shouldAlert80(spentMinor: Int, limitMinor: Int?, alreadyFiredThisCycle: Bool) -> Bool {
        guard let limit = limitMinor, !alreadyFiredThisCycle, spentMinor > 0 else { return false }
        return spentMinor * 10 >= limit * 8
    }
}

public enum WithinDay: Equatable, Sendable {
    case met, missed
    /// A bank message for that day still waits in «تحتاج نظرة».
    case pending
}

public enum WithinDayEngine {
    /// The day succeeds when Σ allocations on «يومك» that day ≤ «يومك». Ignored purchases are not allocations; a refund
    /// lowers its original day; a late correction re-evaluates (derived, never stored).
    public static func evaluate(dailySpentMinor: Int, dailyMinor: Int, hasUnresolvedMessage: Bool) -> WithinDay {
        if hasUnresolvedMessage { return .pending }
        return dailySpentMinor <= dailyMinor ? .met : .missed
    }
}
