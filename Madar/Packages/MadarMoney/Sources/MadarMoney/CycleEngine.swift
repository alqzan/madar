/// The cycle's daily numbers (§7.5 numbers table, F05, L01–L09, RM2, RM3). Days are 1-based cycle days
/// (day 1 = the money day of the salary's eventAt, RM9); the app maps dayKeys to them.
public enum AllowanceMode: Equatable, Sendable {
    /// A fixed daily allowance. 0 stays 0 (L05).
    case fixed(allowanceMinor: Int)
    /// Percent of the cycle's income, divided over the expected cycle length, never 30 (L07).
    case percent(basisPoints: Int, incomeMinor: Int)
}

/// One CyclePolicy row: the allowance in force from `effectiveFromDay`. Editing the allowance adds a row from the
/// next money day; earlier days keep their rate (L01).
public struct CyclePolicySpec: Equatable, Sendable {
    public var effectiveFromDay: Int
    public var mode: AllowanceMode
    public init(effectiveFromDay: Int = 1, mode: AllowanceMode) { self.effectiveFromDay = effectiveFromDay; self.mode = mode }
}

/// The rate frozen when a policy starts: dailyRateMinor, plus the remainder that lands on the last expected day.
public struct FrozenRate: Equatable, Sendable {
    public var dailyRateMinor: Int
    public var lastDayRemainderMinor: Int
    public init(dailyRateMinor: Int, lastDayRemainderMinor: Int) { self.dailyRateMinor = dailyRateMinor; self.lastDayRemainderMinor = lastDayRemainderMinor }
}

/// A plan's daily share («قسمة يومك»). RM3: one funding model; a plan funded from the daily amount has a period and a start.
public struct DailyPlan: Equatable, Sendable {
    public enum Period: Equatable, Sendable { case perCycle, perDay }
    public var id: String
    public var amountMinor: Int
    public var period: Period
    public var startDay: Int
    public init(id: String, amountMinor: Int, period: Period, startDay: Int = 1) {
        self.id = id; self.amountMinor = amountMinor; self.period = period; self.startDay = startDay
    }
}

/// One money day of the cycle.
public struct CycleDay: Equatable, Sendable {
    public var day: Int
    /// The allowance accrued on this day before plans take their share (0 while the trip pauses the daily, L10).
    public var allowanceMinor: Int
    /// What the plans actually took, plan id → amount; never more than the allowance (L08).
    public var dripsMinor: [String: Int]
    /// «يومك» for this day = allowance − plans' share.
    public var dailyMinor: Int { allowanceMinor - dripsMinor.values.reduce(0, +) }
}

public struct CycleInput: Equatable, Sendable {
    /// Expected length in days, from salary to the next expected salary (RM9: scheduled days, so an early arrival
    /// does not change a percent-mode rate).
    public var expectedLengthDays: Int
    public var policies: [CyclePolicySpec]
    public var plans: [DailyPlan]
    /// Signed carry from the previous cycle (negative = a deficit carried, L02).
    public var carryMinor: Int
    /// Days the trip pauses the daily accrual (`mal.travelPausesDaily`, L10).
    public var pausedDays: Set<Int>
    public init(expectedLengthDays: Int, policies: [CyclePolicySpec], plans: [DailyPlan] = [], carryMinor: Int = 0, pausedDays: Set<Int> = []) {
        self.expectedLengthDays = expectedLengthDays; self.policies = policies; self.plans = plans
        self.carryMinor = carryMinor; self.pausedDays = pausedDays
    }
}

public enum CycleEngine {
    /// F05: fixed = the allowance; percent = income × bp ÷ expected length, remainder on the last expected day.
    public static func freeze(_ mode: AllowanceMode, expectedLengthDays: Int) -> FrozenRate {
        switch mode {
        case .fixed(let allowance):
            return FrozenRate(dailyRateMinor: allowance, lastDayRemainderMinor: 0)
        case .percent(let bp, let income):
            let (each, remainder) = MoneyMath.split(MoneyMath.applying(basisPoints: bp, to: income), into: expectedLengthDays)
            return FrozenRate(dailyRateMinor: each, lastDayRemainderMinor: remainder)
        }
    }

    /// The policy in force on a day: the latest row whose effectiveFromDay ≤ day.
    static func policy(on day: Int, _ policies: [CyclePolicySpec]) -> CyclePolicySpec? {
        policies.filter { $0.effectiveFromDay <= day }.max { $0.effectiveFromDay < $1.effectiveFromDay }
    }

    /// A plan's wanted share on a day before the allowance cap. A per-cycle plan is spread over the expected days from
    /// its start with its remainder on the last expected day, so the drops sum to the plan exactly (L06, RM3 start).
    static func wanted(_ plan: DailyPlan, day: Int, length: Int) -> Int {
        guard day >= plan.startDay else { return 0 }
        switch plan.period {
        case .perDay: return plan.amountMinor
        case .perCycle:
            // Spread over the days from its start to the expected end, so the drops still sum to the plan (L06).
            let start = max(1, plan.startDay)
            guard day <= length, start <= length else { return 0 }
            let (each, remainder) = MoneyMath.split(plan.amountMinor, into: length - start + 1)
            return each + (day == length ? remainder : 0)
        }
    }

    /// Day `day` of the cycle. Days past the expected end (a late salary) accrue at the same rate (F05).
    public static func day(_ day: Int, _ input: CycleInput) -> CycleDay {
        var allowance = 0
        if !input.pausedDays.contains(day), let policy = policy(on: day, input.policies) {
            let rate = freeze(policy.mode, expectedLengthDays: input.expectedLengthDays)
            allowance = rate.dailyRateMinor + (day == input.expectedLengthDays ? rate.lastDayRemainderMinor : 0)
        }
        // L08: plans take at most what the day has, in plan order; no money that the day did not have.
        var left = allowance, drips: [String: Int] = [:]
        for plan in input.plans {
            let take = min(left, wanted(plan, day: day, length: input.expectedLengthDays))
            drips[plan.id, default: 0] += take; left -= take
        }
        return CycleDay(day: day, allowanceMinor: allowance, dripsMinor: drips)
    }

    public static func days(through last: Int, _ input: CycleInput) -> [CycleDay] {
        last < 1 ? [] : (1...last).map { day($0, input) }
    }

    /// Σ «يومك» from day 1 through `elapsedDays` inclusive.
    public static func accruedDaily(through elapsedDays: Int, _ input: CycleInput) -> Int {
        days(through: elapsedDays, input).reduce(0) { $0 + $1.dailyMinor }
    }

    /// What a plan received through a day, and what it is short of wanting (L08: «ينقص ٦٠٠٠٠»).
    public static func planFunding(_ planID: String, through last: Int, _ input: CycleInput) -> (depositedMinor: Int, shortMinor: Int) {
        guard let plan = input.plans.first(where: { $0.id == planID }) else { return (0, 0) }
        let deposited = days(through: last, input).reduce(0) { $0 + ($1.dripsMinor[planID] ?? 0) }
        let wanted = last < 1 ? 0 : (1...last).reduce(0) { $0 + wanted(plan, day: $1, length: input.expectedLengthDays) }
        return (deposited, wanted - deposited)
    }

    /// «لك الآن» = Σ يومك through today + carry − Σ the day's spending through today.
    /// `dailySpentMinor` holds each day's net allocations on the daily target (spend positive, refunds negative);
    /// money charged to an envelope is not in it.
    public static func availableNow(elapsedDays: Int, _ input: CycleInput, dailySpentMinor: [Int: Int]) -> Int {
        accruedDaily(through: elapsedDays, input) + input.carryMinor
            - dailySpentMinor.filter { $0.key >= 1 && $0.key <= elapsedDays }.values.reduce(0, +)
    }

    /// RM2: the headline answers "how much can I spend today?" — today's «صرفت X من Y» beside the cumulative «لك الآن»,
    /// with over-today and over-the-cycle kept apart.
    public static func headline(elapsedDays: Int, _ input: CycleInput, dailySpentMinor: [Int: Int], pendingDecisions: Int = 0) -> Headline {
        let today = day(elapsedDays, input), spent = dailySpentMinor[elapsedDays] ?? 0
        let now = availableNow(elapsedDays: elapsedDays, input, dailySpentMinor: dailySpentMinor)
        return Headline(todayAllowanceMinor: today.dailyMinor, todaySpentMinor: spent, availableNowMinor: now,
                        overTodayMinor: spent > today.dailyMinor ? spent - today.dailyMinor : nil,
                        overCycleMinor: now < 0 ? -now : nil, pendingDecisions: pendingDecisions)
    }

    /// L09: the curve is drawn on the actual «يومك» (after plans), the same number as «لك الآن».
    public static func curve(through last: Int, _ input: CycleInput, dailySpentMinor: [Int: Int]) -> [CurvePoint] {
        var accrued = 0, spent = 0
        return days(through: last, input).map { day in
            accrued += day.dailyMinor; spent += dailySpentMinor[day.day] ?? 0
            return CurvePoint(day: day.day, accruedMinor: accrued, spentMinor: spent)
        }
    }
}

public struct Headline: Equatable, Sendable {
    public var todayAllowanceMinor: Int
    public var todaySpentMinor: Int
    public var availableNowMinor: Int
    /// Spent today beyond today's «يومك».
    public var overTodayMinor: Int?
    /// «لك الآن» below zero: the cycle so far is overspent.
    public var overCycleMinor: Int?
    public var pendingDecisions: Int
}

public struct CurvePoint: Equatable, Sendable {
    public var day: Int
    public var accruedMinor: Int
    public var spentMinor: Int
}
