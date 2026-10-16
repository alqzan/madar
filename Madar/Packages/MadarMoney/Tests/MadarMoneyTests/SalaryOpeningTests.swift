import Testing
@testable import MadarMoney

/// M5-V08 «نزل الراتب». Expected values are copied from §7.5 (L02, L03, L07, L13, L14, «الباقي للفوائض حتى ١٠٬٠٠٠ ثم
/// الاحتياطي», early salary) with the hand arithmetic beside each; none is read back from the planner.
@Suite struct SalaryOpeningTests {
    static func input(availableNow: Int? = nil, offsetSoFar: Int = 0, surplus: Int = 0, reserve: Int = 0, autoOffset: Bool = true,
                      remainder: SalaryRemainder = .surplusThenReserve, salary: Int = 0, length: Int = 30,
                      allowance: AllowanceMode = .fixed(allowanceMinor: 0), obligations: Int = 0, plans: [EnvelopePlanSpec] = []) -> SalaryOpeningInput {
        .init(newCycleID: "c2", salaryTransactionID: "sal", salaryMinor: salary, expectedLengthDays: length, allowance: allowance,
              closing: availableNow.map { .init(cycleID: "c1", availableNowMinor: $0, dailyMinor: 40_000, offsetThisCycleMinor: offsetSoFar) },
              surplusMinor: surplus, reserveMinor: reserve, autoOffset: autoOffset, remainder: remainder, obligationsMinor: obligations, plans: plans)
    }
    static func sum(_ rows: [AllocationRow], _ target: AllocationTarget) -> Int { rows.filter { $0.target == target }.reduce(0) { $0 + $1.amountMinor } }

    @Test func l02DeficitIsOffsetFromTheSurplusAndNoHalalaDisappears() {
        let plan = SalaryOpening.plan(Self.input(availableNow: -42_000, surplus: 500_000))
        #expect(plan.close?.offsetMinor == 42_000)
        #expect(plan.close?.surplusAfterMinor == 458_000)
        #expect(plan.carryMinor == 0)
        // The offset is an internal move in the closing cycle: −42000 from the surplus, +42000 to the daily.
        #expect(Self.sum(plan.rows, .surplus) == -42_000)
        #expect(Self.sum(plan.rows, .daily) == 42_000)
        #expect(plan.rows.allSatisfy { $0.cycleID == "c1" })
        // (لك الآن + الفوائض) before = −42000 + 500000 = 458000 = carry + surplus after.
        #expect(plan.carryMinor + 500_000 + Self.sum(plan.rows, .surplus) == 458_000)
    }

    @Test func l02WithOffsetOffTheDeficitIsCarriedVisibly() {
        let plan = SalaryOpening.plan(Self.input(availableNow: -42_000, surplus: 500_000, autoOffset: false))
        #expect(plan.close?.offsetMinor == 0)
        #expect(plan.carryMinor == -42_000)
        #expect(plan.rows.isEmpty)
        #expect(plan.carryMinor + 500_000 == 458_000)
    }

    @Test func l14TheOffsetCapIsPerCycle() {
        // Three deficits of 40000 were already offset this cycle (120000 = 3 × 40000); the close deficit is the fourth.
        let plan = SalaryOpening.plan(Self.input(availableNow: -40_000, offsetSoFar: 120_000, surplus: 500_000))
        #expect(plan.close?.offsetMinor == 0)
        #expect(plan.carryMinor == -40_000)
        #expect(plan.close?.offsetShortfall == .cycleCapReached)
    }

    @Test func theLeftoverFillsTheSurplusToTheCapThenTheReserve() {
        // Close: «لك الآن» +30000 → surplus 950000 + 30000 = 980000 (under the 1000000 cap).
        // New cycle: salary 2000000 − obligations 300000 − envelope 100000 − 30 × 40000 = 400000.
        // 20000 tops the surplus up to 1000000; 380000 goes to the reserve.
        let plan = SalaryOpening.plan(Self.input(availableNow: 30_000, surplus: 950_000, reserve: 5_000_000, salary: 2_000_000,
            allowance: .fixed(allowanceMinor: 40_000), obligations: 300_000,
            plans: [.init(id: "goal", target: .envelope("trip"), source: .salary, perPaycheckMinor: 100_000)]))
        #expect(plan.close?.toSurplusMinor == 30_000)
        #expect(plan.dailiesMinor == 1_200_000)
        #expect(plan.envelopesMinor == 100_000)
        #expect(plan.leftoverMinor == 400_000)
        #expect(plan.toSurplusMinor == 20_000)
        #expect(plan.toReserveMinor == 380_000)
        #expect(950_000 + Self.sum(plan.rows, .surplus) == 1_000_000)
        #expect(Self.sum(plan.rows, .reserve) == 380_000)
        // The salary's own rows add up to what it gives away: envelope + surplus + reserve.
        #expect(plan.rows.filter { $0.transactionID == "sal" }.reduce(0) { $0 + $1.amountMinor } == 500_000)
    }

    @Test func l03SavingsAndRepaymentAreTwoRowsWithTwoKeys() {
        let plans: [EnvelopePlanSpec] = [
            .init(id: "save", target: .envelope("travel"), source: .salary, perPaycheckMinor: 50_000),
            .init(id: "repay", target: .envelope("travel"), kind: .repay, source: .salary, perPaycheckMinor: 50_000, remainingPaychecks: 2),
        ]
        let plan = SalaryOpening.plan(Self.input(salary: 1_000_000, plans: plans))
        let travel = plan.rows.filter { $0.target == .envelope("travel") }
        #expect(travel.map(\.amountMinor) == [50_000, 50_000])
        #expect(Set(travel.map(\.idempotencyKey)).count == 2)
        #expect(travel.map(\.kind) == [.fund, .repay])
        #expect(plan.envelopesMinor == 100_000)
    }

    @Test func l13AGoalFromTheSurplusTakesWhatThereIsAndShowsTheShortfall() {
        let plan = SalaryOpening.plan(Self.input(surplus: 20_000, salary: 0,
            plans: [.init(id: "goal", target: .goal("car"), source: .surplus, perPaycheckMinor: 50_000)]))
        #expect(Self.sum(plan.rows, .goal("car")) == 20_000)
        #expect(plan.shortfalls == [.init(planID: "goal", shortMinor: 30_000)])
        #expect(20_000 + Self.sum(plan.rows, .surplus) == 0)
        // Funding from the surplus is not the salary's money: «الباقي» does not count it.
        #expect(plan.envelopesMinor == 0)
    }

    @Test func l07PercentDailiesSumToTheShareOverTheRealLength() {
        // 40% of 1500000 = 600000 over 31 days: 19354/day + 26 on the last = 600000.
        let plan = SalaryOpening.plan(Self.input(salary: 1_500_000, length: 31, allowance: .percent(basisPoints: 4_000, incomeMinor: 1_500_000)))
        #expect(plan.rate == FrozenRate(dailyRateMinor: 19_354, lastDayRemainderMinor: 26))
        #expect(plan.dailiesMinor == 600_000)
        #expect(plan.leftoverMinor == 900_000)
    }

    @Test func theFirstSalaryHasNothingToClose() {
        let plan = SalaryOpening.plan(Self.input(salary: 1_000_000, allowance: .fixed(allowanceMinor: 20_000)))
        #expect(plan.close == nil)
        #expect(plan.carryMinor == 0)
        #expect(plan.leftoverMinor == 400_000)
    }

    @Test func withAskTheLeftoverWaitsAndNothingIsWritten() {
        let plan = SalaryOpening.plan(Self.input(remainder: .ask, salary: 1_000_000, allowance: .fixed(allowanceMinor: 20_000)))
        #expect(plan.awaitingChoiceMinor == 400_000)
        #expect(plan.rows.isEmpty)
    }

    @Test func aNegativeLeftoverIsShownAndTakesNothing() {
        // 30 × 40000 = 1200000 > salary 1000000: «الباقي» −200000, no surplus or reserve row.
        let plan = SalaryOpening.plan(Self.input(salary: 1_000_000, allowance: .fixed(allowanceMinor: 40_000)))
        #expect(plan.leftoverMinor == -200_000)
        #expect(plan.rows.isEmpty)
    }
}
