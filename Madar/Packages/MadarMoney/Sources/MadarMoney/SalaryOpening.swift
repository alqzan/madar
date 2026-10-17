import Foundation

/// «نزل الراتب» (§7.5, F05, L02, L13, L14): one pure plan read by both the report preview and the command,
/// so the screen can never promise a figure the command would not write.
public struct SalaryOpeningInput: Equatable, Sendable {
    public var newCycleID: String
    public var salaryTransactionID: String
    public var salaryMinor: Int
    public var expectedLengthDays: Int
    public var allowance: AllowanceMode
    /// The cycle being closed, nil for the first salary.
    public var closing: Closing?
    public var surplusMinor: Int
    public var reserveMinor: Int
    public var surplusCapMinor: Int
    public var autoOffset: Bool
    public var offsetCapDailies: Int
    public var remainder: SalaryRemainder
    /// Obligations due inside the new cycle (bills and instalments), in home minor units.
    public var obligationsMinor: Int
    public var plans: [EnvelopePlanSpec]
    public struct Closing: Equatable, Sendable {
        public var cycleID: String
        public var availableNowMinor: Int
        public var dailyMinor: Int
        public var offsetThisCycleMinor: Int
        public init(cycleID: String, availableNowMinor: Int, dailyMinor: Int, offsetThisCycleMinor: Int = 0) {
            self.cycleID = cycleID; self.availableNowMinor = availableNowMinor; self.dailyMinor = dailyMinor; self.offsetThisCycleMinor = offsetThisCycleMinor
        }
    }
    public init(newCycleID: String, salaryTransactionID: String, salaryMinor: Int, expectedLengthDays: Int, allowance: AllowanceMode,
                closing: Closing?, surplusMinor: Int, reserveMinor: Int, surplusCapMinor: Int = 1_000_000, autoOffset: Bool = true,
                remainder: SalaryRemainder = .surplusThenReserve, obligationsMinor: Int = 0, plans: [EnvelopePlanSpec] = [], offsetCapDailies: Int = 3) {
        self.newCycleID = newCycleID; self.salaryTransactionID = salaryTransactionID; self.salaryMinor = salaryMinor
        self.expectedLengthDays = expectedLengthDays; self.allowance = allowance; self.closing = closing
        self.surplusMinor = surplusMinor; self.reserveMinor = reserveMinor; self.surplusCapMinor = surplusCapMinor
        self.offsetCapDailies = offsetCapDailies; self.autoOffset = autoOffset; self.remainder = remainder; self.obligationsMinor = obligationsMinor; self.plans = plans
    }
}

public struct SalaryOpeningPlan: Equatable, Sendable {
    public var close: CycleCloseResult?
    public var rate: FrozenRate
    /// Σ of the new cycle's dailies at the frozen rate (the last day carries the remainder, L06/L07).
    public var dailiesMinor: Int
    /// What the salary sends to envelopes this paycheck (salary-sourced fund and repay plans).
    public var envelopesMinor: Int
    public var obligationsMinor: Int
    /// «الباقي»: salary − obligations − envelopes − dailies; negative is shown, never hidden (L02).
    public var leftoverMinor: Int
    public var toSurplusMinor: Int
    public var toReserveMinor: Int
    public var awaitingChoiceMinor: Int
    public var rows: [AllocationRow]
    public var shortfalls: [FundingShortfall]
    /// The carry the new cycle starts with (an un-offset deficit stays visible).
    public var carryMinor: Int { close?.carryMinor ?? 0 }
}

public enum SalaryOpening {
    public static func plan(_ input: SalaryOpeningInput) -> SalaryOpeningPlan {
        var rows: [AllocationRow] = []
        var surplus = input.surplusMinor, reserve = input.reserveMinor
        var close: CycleCloseResult?
        if let closing = input.closing {
            let result = CycleClose.close(.init(availableNowMinor: closing.availableNowMinor, dailyMinor: closing.dailyMinor, surplusMinor: surplus,
                surplusCapMinor: input.surplusCapMinor, alreadyOffsetThisCycleMinor: closing.offsetThisCycleMinor, autoOffset: input.autoOffset, remainder: input.remainder, offsetCapDailies: input.offsetCapDailies))
            // Keyed by both cycles: an undone salary can be confirmed again (old.closedAt guards a second close).
            let key = "close:" + closing.cycleID + ":" + input.newCycleID
            if result.offsetMinor > 0 {
                // The deficit is covered from the surplus inside the closing cycle: two rows summing to zero.
                rows.append(.init(groupID: key + ":offset", target: .surplus, amountMinor: -result.offsetMinor, kind: .offset, cycleID: closing.cycleID, idempotencyKey: key + ":offset:from"))
                rows.append(.init(groupID: key + ":offset", target: .daily, amountMinor: result.offsetMinor, kind: .offset, cycleID: closing.cycleID, idempotencyKey: key + ":offset"))
            }
            if result.toSurplusMinor > 0 { rows.append(.init(target: .surplus, amountMinor: result.toSurplusMinor, kind: .fund, cycleID: closing.cycleID, idempotencyKey: key + ":surplus")) }
            if result.toReserveMinor > 0 { rows.append(.init(target: .reserve, amountMinor: result.toReserveMinor, kind: .fund, cycleID: closing.cycleID, idempotencyKey: key + ":reserve")) }
            surplus = result.surplusAfterMinor; reserve += result.toReserveMinor
            close = result
        }
        let length = max(1, input.expectedLengthDays)
        let rate = CycleEngine.freeze(input.allowance, expectedLengthDays: length)
        let dailies = rate.dailyRateMinor * length + rate.lastDayRemainderMinor
        let funding = PlanEngine.salaryFunding(cycleID: input.newCycleID, salaryTransactionID: input.salaryTransactionID, plans: input.plans,
                                               surplusMinor: surplus, reserveMinor: reserve)
        rows += funding.rows
        for row in funding.rows where row.groupID != nil && row.amountMinor < 0 {
            if row.target == .surplus { surplus += row.amountMinor } else if row.target == .reserve { reserve += row.amountMinor }
        }
        let envelopes = funding.rows.filter { $0.transactionID == input.salaryTransactionID }.reduce(0) { $0 + $1.amountMinor }
        let leftover = input.salaryMinor - input.obligationsMinor - envelopes - dailies
        var toSurplus = 0, toReserve = 0, awaiting = 0
        if leftover > 0 {
            switch input.remainder {
            case .surplusThenReserve: toSurplus = min(leftover, max(0, input.surplusCapMinor - surplus)); toReserve = leftover - toSurplus
            case .reserve: toReserve = leftover
            case .ask: awaiting = leftover
            }
        }
        let key = "salary:" + input.newCycleID
        if toSurplus > 0 { rows.append(.init(transactionID: input.salaryTransactionID, target: .surplus, amountMinor: toSurplus, kind: .fund, cycleID: input.newCycleID, idempotencyKey: key + ":surplus")) }
        if toReserve > 0 { rows.append(.init(transactionID: input.salaryTransactionID, target: .reserve, amountMinor: toReserve, kind: .fund, cycleID: input.newCycleID, idempotencyKey: key + ":reserve")) }
        return .init(close: close, rate: rate, dailiesMinor: dailies, envelopesMinor: envelopes, obligationsMinor: input.obligationsMinor,
                     leftoverMinor: leftover, toSurplusMinor: toSurplus, toReserveMinor: toReserve, awaitingChoiceMinor: awaiting,
                     rows: rows, shortfalls: funding.shortfalls)
    }
}
