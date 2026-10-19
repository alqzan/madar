/// M5-V15 «المطابقة مع البنك» (F03, `mal/24-Z-R19-rec`): one line per account or credit card — Madar's book against
/// what the bank says — and what naming the difference writes. Pure; the command and the screen share these rules.
public struct ReconcileLine: Equatable, Sendable {
    public enum Side: String, Sendable { case account, creditCard, installment }
    public var side: Side
    /// Madar's book: account cash, card debt, or the installment plan's unpaid schedule.
    public var expectedMinor: Int
    /// What the provider says: the balance, or what is still owed.
    public var observedMinor: Int
    public init(side: Side, expectedMinor: Int, observedMinor: Int) {
        self.side = side; self.expectedMinor = expectedMinor; self.observedMinor = observedMinor
    }
    /// observed − expected, as stored in `Reconciliation.deltaMinor`.
    public var deltaMinor: Int { observedMinor - expectedMinor }
    /// A cash/card shortfall can be spending. An installment difference cannot be classified as spending.
    public var isShortfall: Bool {
        switch side {
        case .account: deltaMinor < 0
        case .creditCard: deltaMinor > 0
        case .installment: false
        }
    }
    /// The effect of settling it on «لك فعلًا» (cash − debt).
    public var netEffectMinor: Int { side == .account ? deltaMinor : -deltaMinor }
}

/// The names «سمّ الفرق» offers. No name leaves the difference open (`leave`).
public enum ReconcileName: String, CaseIterable, Sendable {
    /// «مصاريف فاتتني»: `unrecordedSpend`, charged to today's «يومك».
    case missedSpend
    /// «رسوم بنكية»: `unrecordedSpend` with the note «رسوم بنكية» (a fee is charged like spending, F01).
    case bankFee
    /// «تسوية بلا تفسير»: `adjust`, budget-neutral.
    case unexplained
}

public enum ReconcileEngine {
    /// The names a line can take: spending names only for a shortfall; a surplus can only be settled without a reason.
    public static func names(for line: ReconcileLine) -> [ReconcileName] {
        guard line.deltaMinor != 0 else { return [] }
        guard line.side != .installment else { return [] }
        return line.isShortfall ? [.missedSpend, .bankFee, .unexplained] : [.unexplained]
    }

    /// `Reconciliation.resolution`; nil when the name does not fit the line. A matching line is recorded as `adjust`
    /// with no movement; no name leaves the difference open.
    public static func resolution(_ name: ReconcileName?, for line: ReconcileLine) -> String? {
        if line.deltaMinor == 0 { return name == nil ? "adjust" : nil }
        if line.side == .installment { return name == nil ? "leave" : nil }
        guard let name else { return "leave" }
        guard names(for: line).contains(name) else { return nil }
        return name == .unexplained ? "adjust" : "unrecordedSpend"
    }

    /// The one adjustment movement a settled line writes; nil for a match or a difference left open.
    public static func effect(_ line: ReconcileLine, resolution: String) -> MovementEffect? {
        guard line.side != .installment, line.deltaMinor != 0, resolution != "leave" else { return nil }
        let spend = resolution == "unrecordedSpend"
        return MovementEngine.effect(line.side == .account ? .adjustment(unrecordedSpend: spend) : .cardAdjustment(unrecordedSpend: spend), amountMinor: line.deltaMinor)
    }

    public struct Summary: Equatable, Sendable {
        /// Lines with a difference and no name: «فروق مفتوحة».
        public var open: Int
        /// Σ negative and Σ positive differences of the lines checked so far.
        public var negativeMinor: Int
        public var positiveMinor: Int
        /// Adjustment movements the press writes («تُكتب تسويتان»).
        public var settlements: Int
    }

    public static func summary(_ lines: [(line: ReconcileLine, name: ReconcileName?)]) -> Summary {
        var result = Summary(open: 0, negativeMinor: 0, positiveMinor: 0, settlements: 0)
        for (line, name) in lines where line.deltaMinor != 0 {
            if line.deltaMinor < 0 { result.negativeMinor += line.deltaMinor } else { result.positiveMinor += line.deltaMinor }
            if let resolution = resolution(name, for: line), resolution != "leave" { result.settlements += 1 } else { result.open += 1 }
        }
        return result
    }

    /// «عدّل الواقع»: ± whole currency units; a balance or a debt never goes below zero.
    public static func nudge(_ observedMinor: Int, units: Int, exponent: Int) -> Int {
        var scale = 1; for _ in 0..<max(0, exponent) { scale *= 10 }
        return max(0, observedMinor + units * scale)
    }
}
