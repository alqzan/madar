/// L03: a debt repayment preview does not change the independent saving plan.
public struct RepaymentPreview: Equatable, Sendable {
    public var installmentsMinor: [Int]
    public var dailyAfterMinor: [Int]
}
public enum RepaymentEngine {
    /// Exact minor units; the final salary absorbs the remainder. Forecast only: the current
    /// frozen daily policy is never rewritten by adopting a future salary plan.
    public static func preview(debtMinor: Int, salaries: Int, dailyMinor: Int, cycleDays: Int) -> RepaymentPreview? {
        guard debtMinor > 0, (1...6).contains(salaries), cycleDays > 0 else { return nil }
        let split = MoneyMath.split(debtMinor, into: salaries)
        let payments = (0..<salaries).map { split.each + ($0 == salaries - 1 ? split.lastRemainder : 0) }
        return .init(installmentsMinor: payments, dailyAfterMinor: payments.map { dailyMinor - MoneyMath.divideRounded($0, by: cycleDays) })
    }
}

/// An adopted salary repayment (M5-V04, schema V6): the debt it was adopted for and over how many salaries.
public struct RepaymentPlanState: Equatable, Sendable {
    public var totalMinor: Int
    public var paychecks: Int
    /// Σ of this plan's repay allocations so far, and how many salaries paid into it.
    public var paidMinor: Int
    public var paidCount: Int
    public init(totalMinor: Int, paychecks: Int, paidMinor: Int = 0, paidCount: Int = 0) {
        self.totalMinor = totalMinor; self.paychecks = paychecks; self.paidMinor = paidMinor; self.paidCount = paidCount
    }
    public var remainingMinor: Int { max(0, totalMinor - paidMinor) }
}

extension RepaymentEngine {
    /// What the next salary pays. Counted from what was actually paid, never from dates, so an early, late or skipped
    /// salary keeps the plan exact: every salary pays the even share, and the last one (or any after it, if a source
    /// fell short, L13) pays total − paid to the minor unit. Nil once the debt is paid.
    public static func nextPayment(_ plan: RepaymentPlanState) -> Int? {
        guard plan.totalMinor > 0, plan.paychecks > 0, plan.remainingMinor > 0 else { return nil }
        if plan.paidCount >= plan.paychecks - 1 { return plan.remainingMinor }
        return min(MoneyMath.split(plan.totalMinor, into: plan.paychecks).each, plan.remainingMinor)
    }
}

extension EnvelopePlanSpec {
    /// The salary-funding spec of an adopted repayment, or nil when nothing is left to pay.
    public static func repayment(id: String, target: AllocationTarget, source: Source, _ plan: RepaymentPlanState) -> EnvelopePlanSpec? {
        guard let amount = RepaymentEngine.nextPayment(plan) else { return nil }
        return EnvelopePlanSpec(id: id, target: target, kind: .repay, source: source, perPaycheckMinor: amount,
                                remainingPaychecks: max(1, plan.paychecks - plan.paidCount))
    }
}
