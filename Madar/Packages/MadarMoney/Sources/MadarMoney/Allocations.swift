/// F02 allocations: where a movement's budget charge lands (daily, envelope, reserve, surplus, goal), funding, offsets,
/// repayments and refunds, each with a natural idempotency key. Balances are derived as Σ live allocations.
public enum AllocationTarget: Hashable, Sendable {
    case daily
    case envelope(String)
    case reserve, surplus
    case goal(String)
}

public struct AllocationRow: Equatable, Sendable {
    public enum Kind: String, Sendable { case spend, fund, refund, offset, repay, adjust }
    public var transactionID: String?
    public var groupID: String?
    public var target: AllocationTarget
    /// Signed in home minor units: + adds to the target, − takes from it.
    public var amountMinor: Int
    public var kind: Kind
    public var cycleID: String?
    public var idempotencyKey: String
    public var deleted = false
    public init(transactionID: String? = nil, groupID: String? = nil, target: AllocationTarget, amountMinor: Int, kind: Kind,
                cycleID: String? = nil, idempotencyKey: String) {
        self.transactionID = transactionID; self.groupID = groupID; self.target = target; self.amountMinor = amountMinor
        self.kind = kind; self.cycleID = cycleID; self.idempotencyKey = idempotencyKey
    }
}

public enum AllocationKeys {
    public static func fund(cycle: String, plan: String) -> String { "fund:\(cycle):\(plan)" }
    public static func offset(cycle: String, dayKey: String) -> String { "offset:\(cycle):\(dayKey)" }
    public static func split(transaction: String, _ n: Int) -> String { "split:\(transaction):\(n)" }
    public static func refund(transaction: String, _ n: Int) -> String { "refund:\(transaction):\(n)" }
}

/// An in-memory mirror of the Allocation rows: committing the same key twice writes nothing the second time.
public struct AllocationLedger: Equatable, Sendable {
    public private(set) var rows: [AllocationRow] = []
    public init(rows: [AllocationRow] = []) { self.rows = rows }

    /// Returns the rows actually written (empty when every key already exists).
    @discardableResult public mutating func commit(_ new: [AllocationRow]) -> [AllocationRow] {
        let existing = Set(rows.filter { !$0.idempotencyKey.isEmpty }.map(\.idempotencyKey))
        let written = new.filter { $0.idempotencyKey.isEmpty || !existing.contains($0.idempotencyKey) }
        rows += written
        return written
    }

    /// Undo of a movement tombstones all its allocations in one write, so every source comes back.
    public mutating func undo(transactionID: String) {
        for i in rows.indices where rows[i].transactionID == transactionID { rows[i].deleted = true }
    }

    public func balance(_ target: AllocationTarget) -> Int {
        rows.filter { !$0.deleted && $0.target == target }.reduce(0) { $0 + $1.amountMinor }
    }

    public func live(transactionID: String) -> [AllocationRow] { rows.filter { !$0.deleted && $0.transactionID == transactionID } }
}

public enum AllocationEngine {
    /// Splits a total over integer weights to the halala: ⌊total × w ÷ Σw⌋ each, the remainder on the last (L12).
    public static func distribute(_ total: Int, weights: [Int]) -> [Int] {
        precondition(!weights.isEmpty && weights.allSatisfy { $0 >= 0 } && weights.reduce(0, +) > 0)
        let sum = weights.reduce(0, +), sign = total < 0 ? -1 : 1, magnitude = abs(total)
        var parts = weights.dropLast().map { magnitude * $0 / sum }
        parts.append(magnitude - parts.reduce(0, +))
        return parts.map { $0 * sign }
    }

    public enum SplitError: Error, Equatable { case partsDoNotAddUp, negativePart }

    /// A spend over several sources: Σ allocations = −home amount exactly; by default all of it on «يومك».
    /// Parts that do not add up to the amount, or a negative part, are refused rather than silently absorbed.
    public static func spend(transactionID: String, homeAmountMinor: Int, over sources: [(AllocationTarget, Int)] = [], cycleID: String? = nil) throws -> [AllocationRow] {
        let plan = sources.isEmpty ? [(AllocationTarget.daily, homeAmountMinor)] : sources
        guard plan.allSatisfy({ $0.1 >= 0 }) else { throw SplitError.negativePart }
        guard plan.reduce(0, { $0 + $1.1 }) == homeAmountMinor else { throw SplitError.partsDoNotAddUp }
        return plan.enumerated().map { i, source in
            let amount = source.1
            return AllocationRow(transactionID: transactionID, target: source.0, amountMinor: -amount, kind: .spend, cycleID: cycleID,
                                 idempotencyKey: AllocationKeys.split(transaction: transactionID, i))
        }
    }

    /// A spend split by weights (e.g. thirds), each part to the halala.
    public static func spend(transactionID: String, homeAmountMinor: Int, weighted sources: [(AllocationTarget, Int)], cycleID: String? = nil) throws -> [AllocationRow] {
        let parts = distribute(homeAmountMinor, weights: sources.map(\.1))
        return try spend(transactionID: transactionID, homeAmountMinor: homeAmountMinor, over: zip(sources.map(\.0), parts).map { ($0, $1) }, cycleID: cycleID)
    }

    /// A refund returns to the original's allocations in proportion to its amount (F02).
    public static func refund(refundTransactionID: String, homeAmountMinor: Int, original: [AllocationRow]) -> [AllocationRow] {
        let spends = original.filter { $0.kind == .spend && !$0.deleted }
        guard !spends.isEmpty else { return [] }
        let parts = distribute(homeAmountMinor, weights: spends.map { -$0.amountMinor })
        return zip(spends, parts).enumerated().map { i, pair in
            AllocationRow(transactionID: refundTransactionID, target: pair.0.target, amountMinor: pair.1, kind: .refund, cycleID: pair.0.cycleID,
                          idempotencyKey: AllocationKeys.refund(transaction: refundTransactionID, i))
        }
    }
}
