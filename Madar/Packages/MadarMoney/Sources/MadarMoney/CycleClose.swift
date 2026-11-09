/// Offsets and the salary close (§7.5 rules, L02, L13, L14, `mal.autoOffset`, `mal.surplusCap`, `mal.salaryRemainder`).
public enum OffsetEngine {

    public enum Shortfall: Equatable, Sendable {
        case disabled
        /// The deficit is larger than the configured cap × «يومك»: it is not offset, it stays visible.
        case tooLarge
        /// «بلغت المقاصة سقف الدورة» (L14).
        case cycleCapReached
        /// The surplus never goes negative (L13).
        case surplusEmpty
    }

    public struct Outcome: Equatable, Sendable {
        public var offsetMinor: Int
        public var remainingDeficitMinor: Int
        public var shortfall: Shortfall?
    }

    /// Offsets each deficit in order from the surplus. The cap is checked against Σ offsets in the cycle (L14), not per event.
    public static func offset(deficitsMinor: [Int], dailyMinor: Int, surplusMinor: Int, alreadyOffsetThisCycleMinor: Int = 0, enabled: Bool, capDailies: Int = 3) -> [Outcome] {
        let product = max(0, capDailies).multipliedReportingOverflow(by: max(0, dailyMinor))
        let cap = product.overflow ? Int.max : product.partialValue
        var used = alreadyOffsetThisCycleMinor, surplus = surplusMinor
        return deficitsMinor.map { deficit in
            guard enabled else { return Outcome(offsetMinor: 0, remainingDeficitMinor: deficit, shortfall: .disabled) }
            guard deficit <= cap else { return Outcome(offsetMinor: 0, remainingDeficitMinor: deficit, shortfall: .tooLarge) }
            let amount = max(0, min(deficit, cap - used, surplus))
            used += amount; surplus -= amount
            let shortfall: Shortfall? = amount == deficit ? nil : (cap - used <= 0 ? .cycleCapReached : .surplusEmpty)
            return Outcome(offsetMinor: amount, remainingDeficitMinor: deficit - amount, shortfall: shortfall)
        }
    }
}

public enum SalaryRemainder: String, Sendable { case surplusThenReserve, reserve, ask }

public struct CycleCloseInput: Equatable, Sendable {
    /// «لك الآن» at the close (signed).
    public var availableNowMinor: Int
    public var dailyMinor: Int
    public var surplusMinor: Int
    public var surplusCapMinor: Int
    public var alreadyOffsetThisCycleMinor: Int
    public var autoOffset: Bool
    public var offsetCapDailies: Int
    public var remainder: SalaryRemainder
    public init(availableNowMinor: Int, dailyMinor: Int, surplusMinor: Int, surplusCapMinor: Int = 1_000_000,
                alreadyOffsetThisCycleMinor: Int = 0, autoOffset: Bool = true, remainder: SalaryRemainder = .surplusThenReserve, offsetCapDailies: Int = 3) {
        self.availableNowMinor = availableNowMinor; self.dailyMinor = dailyMinor; self.surplusMinor = surplusMinor
        self.surplusCapMinor = surplusCapMinor; self.alreadyOffsetThisCycleMinor = alreadyOffsetThisCycleMinor
        self.autoOffset = autoOffset; self.remainder = remainder; self.offsetCapDailies = offsetCapDailies
    }
}

public struct CycleCloseResult: Equatable, Sendable {
    public var offsetMinor: Int
    /// The signed carry into the next cycle; a deficit that was not offset stays visible (L02: no max(0)).
    public var carryMinor: Int
    public var toSurplusMinor: Int
    public var toReserveMinor: Int
    /// With `mal.salaryRemainder = ask`, the leftover waits for the user in «نزل الراتب».
    public var awaitingChoiceMinor: Int
    public var surplusAfterMinor: Int
    public var offsetShortfall: OffsetEngine.Shortfall?
}

public enum CycleClose {
    /// L02: no halala disappears — «لك الآن» + surplus + reserve before equals carry + surplus + reserve + awaiting after.
    public static func close(_ input: CycleCloseInput) -> CycleCloseResult {
        if input.availableNowMinor < 0 {
            let outcome = OffsetEngine.offset(deficitsMinor: [-input.availableNowMinor], dailyMinor: input.dailyMinor, surplusMinor: input.surplusMinor,
                                              alreadyOffsetThisCycleMinor: input.alreadyOffsetThisCycleMinor, enabled: input.autoOffset, capDailies: input.offsetCapDailies)[0]
            return CycleCloseResult(offsetMinor: outcome.offsetMinor, carryMinor: -outcome.remainingDeficitMinor, toSurplusMinor: 0, toReserveMinor: 0,
                                    awaitingChoiceMinor: 0, surplusAfterMinor: input.surplusMinor - outcome.offsetMinor, offsetShortfall: outcome.shortfall)
        }
        let left = input.availableNowMinor
        var toSurplus = 0, toReserve = 0, awaiting = 0
        switch input.remainder {
        case .surplusThenReserve:
            // «الباقي للفوائض حتى ١٠٬٠٠٠ ثم الاحتياطي»: the cap is on the surplus balance.
            toSurplus = min(left, max(0, input.surplusCapMinor - input.surplusMinor)); toReserve = left - toSurplus
        case .reserve: toReserve = left
        case .ask: awaiting = left
        }
        return CycleCloseResult(offsetMinor: 0, carryMinor: 0, toSurplusMinor: toSurplus, toReserveMinor: toReserve,
                                awaitingChoiceMinor: awaiting, surplusAfterMinor: input.surplusMinor + toSurplus, offsetShortfall: nil)
    }
}
