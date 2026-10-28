import Testing
@testable import MadarMoney

struct FundingProjectionTests {
    // L06/L08/RM3: 30 days × 100 allowance cannot deposit the requested 120 a day.
    @Test func dailyFundingUsesTheAllowanceAndDoesNotCountTodayTwice() {
        let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 10_000))],
                               plans: [.init(id: "p", amountMinor: 12_000, period: .perDay)])
        let result = FundingProjectionEngine.project(balances: ["goal": 100_000],
            cycles: [.init(start: -9, firstDay: 11, lastDay: 30, input: input, targets: ["p": "goal"])],
            salaryDays: [], plans: [], surplusMinor: 0, reserveMinor: 0, through: 20)
        #expect(result.balance("goal", on: 0) == 100_000)
        #expect(result.balance("goal", on: 1) == 110_000)
        #expect(result.balance("goal", on: 20) == 300_000)
        #expect(result.balance("goal", on: 21) == nil)
    }

    // L06: 300,000/28 = 10,714 plus the final remainder 8; no rounding is lost.
    @Test func cycleRemainderAndPlanEndArePreserved() {
        let input = CycleInput(expectedLengthDays: 28, policies: [.init(mode: .fixed(allowanceMinor: 40_000))],
                               plans: [.init(id: "p", amountMinor: 300_000, period: .perCycle)])
        let result = FundingProjectionEngine.project(balances: ["goal": 0],
            cycles: [.init(start: 1, firstDay: 1, lastDay: 28, input: input, targets: ["p": "goal"])],
            salaryDays: [], plans: [], surplusMinor: 0, reserveMinor: 0, through: 28)
        #expect(result.balance("goal", on: 27) == 289_278)
        #expect(result.balance("goal", on: 28) == 300_000)
        var ended = input; ended.plans[0].endDay = 2
        let short = FundingProjectionEngine.project(balances: ["goal": 0],
            cycles: [.init(start: 1, firstDay: 1, lastDay: 28, input: ended, targets: ["p": "goal"])],
            salaryDays: [], plans: [], surplusMinor: 0, reserveMinor: 0, through: 28)
        #expect(short.balance("goal", on: 28) == 21_428)
    }

    // L13: two goals compete for 20,000 surplus; later salaries cannot invent replenishment.
    @Test func conditionalSourcesCompeteAndNeverRegrow() {
        let result = FundingProjectionEngine.project(balances: ["a": 0, "b": 0], cycles: [], salaryDays: [4, 11], plans: [
            .init(spec: .init(id: "first", target: .envelope("a"), source: .surplus, perPaycheckMinor: 15_000)),
            .init(spec: .init(id: "second", target: .envelope("b"), source: .surplus, perPaycheckMinor: 15_000))
        ], surplusMinor: 20_000, reserveMinor: 0, through: 11)
        #expect(result.balance("a", on: 3) == 0)
        #expect(result.balance("a", on: 4) == 15_000)
        #expect(result.balance("b", on: 4) == 5_000)
        #expect(result.balance("a", on: 11) == 15_000)
        #expect(result.balance("b", on: 11) == 5_000)
    }

    // L03/L12: 100 on three salaries is 33 + 33 + 34; the separate saving expires after salary two.
    @Test func repaymentFinishesAndExpiredSavingStops() {
        let result = FundingProjectionEngine.project(balances: ["goal": -100], cycles: [], salaryDays: [7, 14, 21, 28], plans: [
            .init(spec: .init(id: "saving", target: .envelope("goal"), source: .salary, perPaycheckMinor: 50), until: 14),
            .init(spec: .init(id: "repay", target: .envelope("goal"), kind: .repay, source: .salary, perPaycheckMinor: 33),
                  repayment: .init(totalMinor: 100, paychecks: 3))
        ], surplusMinor: 0, reserveMinor: 0, through: 28)
        #expect(result.balance("goal", on: 7) == -17)
        #expect(result.balance("goal", on: 14) == 66)
        #expect(result.balance("goal", on: 21) == 100)
        #expect(result.balance("goal", on: 28) == 100)
    }

    @Test func dailyGoalCapCarriesAcrossCyclesAndTripsPauseFunding() {
        let input = CycleInput(expectedLengthDays: 3, policies: [.init(mode: .fixed(allowanceMinor: 100))],
                               plans: [.init(id: "p", amountMinor: 80, period: .perDay)], pausedDays: [2])
        let result = FundingProjectionEngine.project(balances: ["goal": 0], cycles: [
            .init(start: 1, firstDay: 1, lastDay: 3, input: input, targets: ["p": "goal"]),
            .init(start: 4, firstDay: 1, lastDay: 3, input: input, targets: ["p": "goal"])
        ], salaryDays: [], plans: [], surplusMinor: 0, reserveMinor: 0, dailyCaps: ["p": 200], through: 6)
        #expect(result.balance("goal", on: 2) == 80)
        #expect(result.balance("goal", on: 3) == 160)
        #expect(result.balance("goal", on: 4) == 200)
        #expect(result.balance("goal", on: 6) == 200)
    }

    @Test func salaryCompletingTheGoalReleasesItsDailyShareToTheOtherGoal() {
        let input = CycleInput(expectedLengthDays: 2, policies: [.init(mode: .fixed(allowanceMinor: 100))], plans: [
            .init(id: "first", amountMinor: 100, period: .perDay), .init(id: "second", amountMinor: 100, period: .perDay)
        ])
        let result = FundingProjectionEngine.project(balances: ["a": 0, "b": 0],
            cycles: [.init(start: 1, firstDay: 1, lastDay: 2, input: input, targets: ["first": "a", "second": "b"])],
            salaryDays: [1], plans: [.init(spec: .init(id: "salary", target: .envelope("a"), source: .salary, perPaycheckMinor: 100))],
            surplusMinor: 0, reserveMinor: 0, dailyCaps: ["first": 100], through: 2)
        #expect(result.balance("a", on: 1) == 100)
        #expect(result.balance("a", on: 2) == 100)
        #expect(result.balance("b", on: 1) == 100)
        #expect(result.balance("b", on: 2) == 200)
    }
}
