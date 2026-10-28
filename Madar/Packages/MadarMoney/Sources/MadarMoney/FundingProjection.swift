/// A read-only scenario: the current plans continue, with no new spending, salary change or replenishment of
/// reserve/surplus. Dates are offsets from today; the caller supplies actual salary-calendar occurrences.
public struct FundingProjectionCycle: Sendable {
    public var start: Int
    public var firstDay: Int
    public var lastDay: Int
    public var input: CycleInput
    public var targets: [String: String]
    public init(start: Int, firstDay: Int, lastDay: Int, input: CycleInput, targets: [String: String]) {
        self.start = start; self.firstDay = firstDay; self.lastDay = lastDay; self.input = input; self.targets = targets
    }
}

public struct FundingProjectionPlan: Sendable {
    public var spec: EnvelopePlanSpec
    public var until: Int?
    public var repayment: RepaymentPlanState?
    public init(spec: EnvelopePlanSpec, until: Int? = nil, repayment: RepaymentPlanState? = nil) {
        self.spec = spec; self.until = until; self.repayment = repayment
    }
}

public struct FundingProjectionPoint: Equatable, Sendable {
    public var day: Int
    public var balanceMinor: Int
    public var salary: Bool
}

public struct FundingProjectionResult: Sendable {
    public var points: [String: [FundingProjectionPoint]]
    public var through: Int
    public func balance(_ target: String, on day: Int) -> Int? {
        guard (0...through).contains(day) else { return nil }
        return points[target]?.last(where: { $0.day <= day })?.balanceMinor
    }
}

public enum FundingProjectionEngine {
    /// Reuses L06/L08/RM3 daily funding and L13 salary funding. Never creates an allocation or replenishes a source
    /// from hypothetical cycle leftovers. All plans compete for the same daily/source budgets in their real order.
    public static func project(balances initial: [String: Int], cycles: [FundingProjectionCycle],
                               salaryDays: [Int], plans: [FundingProjectionPlan], surplusMinor: Int, reserveMinor: Int,
                               dailyCaps: [String: Int] = [:], through horizon: Int) -> FundingProjectionResult {
        let horizon = max(0, min(3660, horizon))
        var balances = initial, points = initial.mapValues { [FundingProjectionPoint(day: 0, balanceMinor: $0, salary: false)] }
        var surplus = max(0, surplusMinor), reserve = max(0, reserveMinor), plans = plans
        var caps = dailyCaps, drops: [Int: [String: Int]] = [:]
        let salaries = Set(salaryDays.filter { $0 > 0 && $0 <= horizon })
        let windows = cycles.sorted { $0.start < $1.start }
        guard horizon > 0 else { return .init(points: points, through: horizon) }
        for day in 1...horizon {
            var changed = Set<String>()
            if salaries.contains(day) {
                let active = plans.compactMap { plan -> EnvelopePlanSpec? in
                    guard plan.until == nil || day <= plan.until! else { return nil }
                    if let state = plan.repayment {
                        return .repayment(id: plan.spec.id, target: plan.spec.target, source: plan.spec.source, state)
                    }
                    return plan.spec
                }
                let funded = PlanEngine.salaryFunding(cycleID: String(day), salaryTransactionID: "forecast", plans: active,
                                                       surplusMinor: surplus, reserveMinor: reserve).rows
                for row in funded {
                    switch row.target {
                    case .surplus: surplus += row.amountMinor
                    case .reserve: reserve += row.amountMinor
                    case .envelope(let target):
                        balances[target, default: 0] += row.amountMinor; changed.insert(target)
                        if row.kind == .fund && row.amountMinor > 0 {
                            // The goal's lifetime cap includes salary/surplus/reserve funding too, just as the
                            // persisted cycle reader does. Release that daily allowance to competing plans.
                            let ids = Set(windows.flatMap { $0.targets.filter { $0.value == target }.map(\.key) })
                            for id in ids where caps[id] != nil { caps[id] = max(0, caps[id]! - row.amountMinor) }
                        }
                        if let index = plans.firstIndex(where: { row.idempotencyKey == AllocationKeys.fund(cycle: String(day), plan: $0.spec.id) }),
                           var state = plans[index].repayment, row.amountMinor > 0 {
                            state.paidMinor += row.amountMinor; state.paidCount += 1; plans[index].repayment = state
                        }
                    default: break
                    }
                }
            }
            // Build each cycle once. Current-cycle firstDay excludes drops already present in today's balance.
            for window in windows where max(1, window.start + window.firstDay - 1) == day {
                var input = window.input
                for index in input.plans.indices {
                    if window.firstDay == 1, let cap = caps[input.plans[index].id] {
                        input.plans[index].maximumMinorPerCycle = min(input.plans[index].maximumMinorPerCycle ?? cap, cap)
                    }
                }
                let last = min(window.lastDay, horizon - window.start + 1)
                for value in CycleEngine.days(through: max(0, last), input) where value.day >= window.firstDay {
                    let offset = window.start + value.day - 1
                    guard offset > 0 else { continue }
                    for (id, amount) in value.dripsMinor where amount > 0 {
                        guard let target = window.targets[id] else { continue }
                        drops[offset, default: [:]][target, default: 0] += amount
                        if caps[id] != nil { caps[id] = max(0, caps[id]! - amount) }
                    }
                }
            }
            for (target, amount) in drops.removeValue(forKey: day) ?? [:] {
                balances[target, default: 0] += amount; changed.insert(target)
            }
            for target in changed {
                points[target, default: []].append(.init(day: day, balanceMinor: balances[target, default: 0], salary: salaries.contains(day)))
            }
        }
        return .init(points: points, through: horizon)
    }
}
