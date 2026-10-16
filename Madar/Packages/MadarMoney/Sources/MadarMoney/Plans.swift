import Foundation

/// RM3: one funding model. A plan has one source; salary-, surplus- and reserve-funded plans become allocations at the
/// salary, a daily-funded plan is the drop CycleEngine takes from «يومك». A repayment plan is separate from a saving
/// plan on the same envelope (L03).
public struct EnvelopePlanSpec: Equatable, Sendable {
    public enum Kind: String, Sendable { case fund, repay }
    public enum Source: String, Sendable { case salary, daily, surplus, reserve }
    public var id: String
    public var target: AllocationTarget
    public var kind: Kind
    public var source: Source
    public var perPaycheckMinor: Int
    /// For a repayment: salaries left; nil = open-ended.
    public var remainingPaychecks: Int?
    public init(id: String, target: AllocationTarget, kind: Kind = .fund, source: Source, perPaycheckMinor: Int, remainingPaychecks: Int? = nil) {
        self.id = id; self.target = target; self.kind = kind; self.source = source
        self.perPaycheckMinor = perPaycheckMinor; self.remainingPaychecks = remainingPaychecks
    }
}

public struct FundingShortfall: Equatable, Sendable {
    public var planID: String
    /// «ينقص X» — what the source could not give (L13); the goal's due date then shows in the `due` pattern.
    public var shortMinor: Int
}

public enum PlanEngine {
    /// The allocations one salary makes. A surplus or reserve source never goes below zero (L13): it gives what it has,
    /// and the rest is a visible shortfall. Keys are fund:<cycle>:<plan>, so a repeated salary message funds nothing twice.
    public static func salaryFunding(cycleID: String, salaryTransactionID: String, plans: [EnvelopePlanSpec],
                                     surplusMinor: Int, reserveMinor: Int) -> (rows: [AllocationRow], shortfalls: [FundingShortfall]) {
        var rows: [AllocationRow] = [], shortfalls: [FundingShortfall] = []
        var available: [EnvelopePlanSpec.Source: Int] = [.surplus: surplusMinor, .reserve: reserveMinor]
        for plan in plans where plan.source != .daily && (plan.remainingPaychecks ?? 1) > 0 {
            let key = AllocationKeys.fund(cycle: cycleID, plan: plan.id), kind: AllocationRow.Kind = plan.kind == .repay ? .repay : .fund
            switch plan.source {
            case .salary:
                rows.append(AllocationRow(transactionID: salaryTransactionID, target: plan.target, amountMinor: plan.perPaycheckMinor,
                                          kind: kind, cycleID: cycleID, idempotencyKey: key))
            case .surplus, .reserve:
                let from: AllocationTarget = plan.source == .surplus ? .surplus : .reserve
                let take = min(plan.perPaycheckMinor, max(0, available[plan.source] ?? 0))
                available[plan.source, default: 0] -= take
                if take > 0 {
                    // An internal move: two rows in one group summing to zero.
                    rows.append(AllocationRow(groupID: key, target: from, amountMinor: -take, kind: kind, cycleID: cycleID, idempotencyKey: key + ":from"))
                    rows.append(AllocationRow(groupID: key, target: plan.target, amountMinor: take, kind: kind, cycleID: cycleID, idempotencyKey: key))
                }
                if take < plan.perPaycheckMinor { shortfalls.append(.init(planID: plan.id, shortMinor: plan.perPaycheckMinor - take)) }
            case .daily: break
            }
        }
        return (rows, shortfalls)
    }
}

/// F03 / L04: the reconciliation record. expected = last confirmed balance + in − out since; its composition is shown,
/// including what of the dailies is not yet accrued (part of the balance, neither surplus nor a difference).
public struct ReconciliationResult: Equatable, Sendable {
    public var expectedMinor: Int
    public var observedMinor: Int
    /// observed − expected.
    public var deltaMinor: Int
    /// «لم يُستحق بعد من يومياتك».
    public var notYetAccruedMinor: Int
}

public enum ReconciliationEngine {
    public static func reconcile(lastConfirmedMinor: Int, inflowsMinor: Int, outflowsMinor: Int, observedMinor: Int, notYetAccruedMinor: Int) -> ReconciliationResult {
        let expected = lastConfirmedMinor + inflowsMinor - outflowsMinor
        return ReconciliationResult(expectedMinor: expected, observedMinor: observedMinor, deltaMinor: observedMinor - expected, notYetAccruedMinor: notYetAccruedMinor)
    }

    /// The dailies of the rest of the cycle: Σ «يومك» for days after today through the expected end.
    public static func notYetAccrued(elapsedDays: Int, _ input: CycleInput) -> Int {
        CycleEngine.accruedDaily(through: input.expectedLengthDays, input) - CycleEngine.accruedDaily(through: elapsedDays, input)
    }
}

/// RM5: pairing the two SMS legs of a transfer between own accounts.
public struct BankLeg: Equatable, Sendable {
    public enum Direction: Sendable { case out, `in` }
    public var id: String
    public var accountID: String
    public var accountOwned: Bool
    public var direction: Direction
    public var amountMinor: Int
    public var at: Date
    public init(id: String, accountID: String, accountOwned: Bool = true, direction: Direction, amountMinor: Int, at: Date) {
        self.id = id; self.accountID = accountID; self.accountOwned = accountOwned; self.direction = direction; self.amountMinor = amountMinor; self.at = at
    }
}

public enum TransferPairing {
    /// RM5 names no window; 10 minutes matches RM8's near-duplicate window (logged for the owner).
    public static let windowSeconds: TimeInterval = 10 * 60

    /// Same amount, opposite sides, two different owned accounts, within the window; each leg pairs once, nearest first.
    public static func pairs(_ legs: [BankLeg], window: TimeInterval = windowSeconds) -> [(out: String, in: String)] {
        var used = Set<String>(), result: [(out: String, in: String)] = []
        for out in legs.filter({ $0.direction == .out && $0.accountOwned }).sorted(by: { $0.at < $1.at }) {
            let match = legs.filter { leg in
                leg.direction == .in && leg.accountOwned && !used.contains(leg.id) && leg.accountID != out.accountID
                    && leg.amountMinor == out.amountMinor && abs(leg.at.timeIntervalSince(out.at)) <= window
            }.min { abs($0.at.timeIntervalSince(out.at)) < abs($1.at.timeIntervalSince(out.at)) }
            if let match { used.insert(match.id); result.append((out.id, match.id)) }
        }
        return result
    }
}

public enum InstallmentEngine {
    /// A payment raises paidMinor of its instalment; a partial payment leaves it open. Rest and «عليك» are derived.
    public static func pay(_ items: [InstallmentState], index: Int, amountMinor: Int) -> [InstallmentState] {
        var items = items
        items[index].paidMinor += amountMinor
        return items
    }
    public static func isClosed(_ item: InstallmentState) -> Bool { item.paidMinor >= item.amountMinor }
}
