import Testing
@testable import MadarMoney

/// M5-E01 golden cases. Every expected value is copied from §7.5 (numbers table, constants, L01–L09, L14) or the
/// fixes file (RM2, RM9), with the hand arithmetic beside it; none is taken from the engine's own output.
@Suite struct CycleEngineTests {
    /// C0 daily: allowance 41300 − the Tamara drop 1300 = «يومك» 40000.
    static let c0 = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 41_300))],
                               plans: [.init(id: "tamara", amountMinor: 1_300, period: .perDay)])

    /// B1-19: values an import can carry must not crash the engine.
    @Test func zeroLengthNegativeIncomeAndHugeAmountsNeverTrap() {
        // Zero expected days behave as one day; a negative income earns nothing: 30% of 10 000 over one day.
        let oneDay = CycleEngine.freeze(.percent(basisPoints: 3_000, incomeMinor: 10_000), expectedLengthDays: 0)
        #expect(oneDay.dailyRateMinor == 3_000 && oneDay.lastDayRemainderMinor == 0)
        let none = CycleEngine.freeze(.percent(basisPoints: 3_000, incomeMinor: -5_000), expectedLengthDays: 30)
        #expect(none.dailyRateMinor == 0 && none.lastDayRemainderMinor == 0)
        // 20 000% of a huge amount overflows Int: it saturates; the sign follows the arithmetic.
        #expect(MoneyMath.applying(basisPoints: 2_000_000, to: Int.max / 2) == Int.max)
        #expect(MoneyMath.applying(basisPoints: 2_000_000, to: -(Int.max / 2)) == Int.min)
    }

    @Test func c0DailyIsTheAllowanceLessThePlansShare() {
        #expect(CycleEngine.day(1, Self.c0).dailyMinor == 40_000)
        #expect(CycleEngine.day(1, Self.c0).dripsMinor == ["tamara": 1_300])
    }

    @Test func l01AllowanceEditIsANewPolicyRowAndEarlierDaysKeepTheirRate() {
        // C0 + carry −120000; on day 10 the allowance becomes 46300, in force from day 11.
        var input = Self.c0
        input.carryMinor = -120_000
        input.policies.append(.init(effectiveFromDay: 11, mode: .fixed(allowanceMinor: 46_300)))
        // Day 12: 10 × 40000 + 2 × (46300 − 1300) = 490000; − 120000 = 370000 before spending.
        #expect(CycleEngine.accruedDaily(through: 12, input) == 490_000)
        #expect(CycleEngine.day(12, input).dripsMinor["tamara"] == 1_300)
        #expect(CycleEngine.availableNow(elapsedDays: 12, input, dailySpentMinor: [:]) == 370_000)
    }

    @Test func l05ZeroAllowanceStaysZero() {
        let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 0))])
        let headline = CycleEngine.headline(elapsedDays: 1, input, dailySpentMinor: [1: 10_000])
        // «يومك» 0, «تجاوزت يومك بـ١٠٠».
        #expect(headline.todayAllowanceMinor == 0)
        #expect(headline.overTodayMinor == 10_000)
        #expect(headline.availableNowMinor == -10_000)
    }

    @Test func l06PerCycleDropFollowsTheCyclesOwnLengthAndSumsExactly() {
        for (length, each, remainder) in [(28, 10_714, 8), (31, 9_677, 13)] {
            // 300000 ÷ 28 = 10714 r 8; 300000 ÷ 31 = 9677 r 13 — the remainder on the last day.
            let input = CycleInput(expectedLengthDays: length, policies: [.init(mode: .fixed(allowanceMinor: 50_000))],
                                   plans: [.init(id: "plan", amountMinor: 300_000, period: .perCycle)])
            #expect(CycleEngine.day(1, input).dripsMinor["plan"] == each)
            #expect(CycleEngine.day(length, input).dripsMinor["plan"] == each + remainder)
            #expect(CycleEngine.planFunding("plan", through: length, input).depositedMinor == 300_000)
            // On day 3 three drops show.
            #expect(CycleEngine.planFunding("plan", through: 3, input).depositedMinor == 3 * each)
        }
    }

    @Test func l07PercentModeDividesByTheCycleLengthNotThirty() {
        // Income 1500000 × 40% = 600000; 31 days: 19354 + 26 on the last; 28 days: 21428 + 16 (not 20000).
        for (length, each, remainder) in [(31, 19_354, 26), (28, 21_428, 16)] {
            let mode = AllowanceMode.percent(basisPoints: 4_000, incomeMinor: 1_500_000)
            #expect(CycleEngine.freeze(mode, expectedLengthDays: length) == FrozenRate(dailyRateMinor: each, lastDayRemainderMinor: remainder))
            let input = CycleInput(expectedLengthDays: length, policies: [.init(mode: mode)])
            #expect(CycleEngine.accruedDaily(through: length, input) == 600_000)
        }
    }

    @Test func percentAllowanceHandlesLargeRepresentableSalary() {
        let mode = AllowanceMode.percent(basisPoints: 10_000, incomeMinor: 1_000_000_000_000_000)
        #expect(CycleEngine.freeze(mode, expectedLengthDays: 30) == FrozenRate(dailyRateMinor: 33_333_333_333_333, lastDayRemainderMinor: 10))
    }

    @Test func l08APlanLargerThanTheAllowanceDepositsOnlyWhatItTook() {
        // Allowance 10000/day; the plan wants 12000/day for 30 days.
        let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 10_000))],
                               plans: [.init(id: "plan", amountMinor: 12_000, period: .perDay)])
        #expect(CycleEngine.day(5, input).dripsMinor["plan"] == 10_000)
        #expect(CycleEngine.day(5, input).dailyMinor == 0)
        let funding = CycleEngine.planFunding("plan", through: 30, input)
        // Deposited 300000, not 360000; «ينقص 60000».
        #expect(funding.depositedMinor == 300_000)
        #expect(funding.shortMinor == 60_000)
    }

    @Test func l09CurveAndAvailableNowUseTheActualDaily() {
        let curve = CycleEngine.curve(through: 3, Self.c0, dailySpentMinor: [2: 5_000])
        // On 40000, not 41300.
        #expect(curve.map(\.accruedMinor) == [40_000, 80_000, 120_000])
        #expect(curve.map(\.spentMinor) == [0, 5_000, 5_000])
        #expect(CycleEngine.availableNow(elapsedDays: 3, Self.c0, dailySpentMinor: [2: 5_000]) == 115_000)
    }

    @Test func availableNowIsCumulativeFromTheCycleStart() {
        // §7.5 example: day 6 at 40000/day = 240000; spent 104000 by then → «لك الآن» 136000 (١٬٣٦٠).
        let spent = [1: 30_000, 3: 50_000, 6: 24_000]
        #expect(CycleEngine.availableNow(elapsedDays: 6, Self.c0, dailySpentMinor: spent) == 136_000)
        // Spending on a day after today is not counted yet.
        #expect(CycleEngine.availableNow(elapsedDays: 2, Self.c0, dailySpentMinor: spent) == 50_000)
    }

    @Test func rm2HeadlineKeepsTodayAndTheCycleApart() {
        // Day 2: 80000 accrued. Today 55000 of 40000 → over today by 15000, while the cycle is still 25000 up.
        let today = CycleEngine.headline(elapsedDays: 2, Self.c0, dailySpentMinor: [2: 55_000], pendingDecisions: 1)
        #expect(today == Headline(todayAllowanceMinor: 40_000, todaySpentMinor: 55_000, availableNowMinor: 25_000,
                                  overTodayMinor: 15_000, overCycleMinor: nil, pendingDecisions: 1))
        // Day 27 at «تجاوزت … بـ٤٢٠» cumulative: 27 × 40000 = 1080000; spent 1122000 → 42000 over the cycle, nothing today.
        let cycle = CycleEngine.headline(elapsedDays: 27, Self.c0, dailySpentMinor: [5: 1_122_000])
        #expect(cycle.overCycleMinor == 42_000)
        #expect(cycle.overTodayMinor == nil)
    }

    @Test func lateSalaryDaysAccrueAtTheSameRateAndEarlyDaysDoNot() {
        // F05: a 28-day percent cycle whose salary comes on day 30 → days 29 and 30 accrue 21428 each.
        let input = CycleInput(expectedLengthDays: 28, policies: [.init(mode: .percent(basisPoints: 4_000, incomeMinor: 1_500_000))])
        #expect(CycleEngine.day(29, input).allowanceMinor == 21_428)
        #expect(CycleEngine.accruedDaily(through: 30, input) == 600_000 + 2 * 21_428)
        // An early salary on day 26 closes at day 25: 25 × 21428 = 535700; the unaccrued days stay in the bank.
        #expect(CycleEngine.accruedDaily(through: 25, input) == 535_700)
    }

    @Test func travelPausedDaysAccrueNothing() {
        // L10: with `mal.travelPausesDaily`, the trip days accrue 0 (the trip envelope carries the spending).
        var input = Self.c0
        input.pausedDays = [3, 4, 5, 6, 7]
        #expect(CycleEngine.day(4, input).dailyMinor == 0)
        #expect(CycleEngine.accruedDaily(through: 7, input) == 2 * 40_000)
    }

    @Test func perCyclePlanStartingLaterStillSumsExactly() {
        // RM3 start: 300000 from day 3 of a 30-day cycle → spread over 28 days: 10714 each, 8 on the last; none on days 1–2.
        let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 50_000))],
                               plans: [.init(id: "plan", amountMinor: 300_000, period: .perCycle, startDay: 3)])
        #expect(CycleEngine.day(2, input).dripsMinor["plan"] == 0)
        #expect(CycleEngine.day(3, input).dripsMinor["plan"] == 10_714)
        #expect(CycleEngine.day(30, input).dripsMinor["plan"] == 10_722)
        #expect(CycleEngine.planFunding("plan", through: 30, input).depositedMinor == 300_000)
    }
}
