import Testing
@testable import MadarMoney

struct GoalPreparationTests {
    @Test func approvedEditableSuggestionsAndExactLastDrop() {
        let plans = GoalPreparation.suggestions(targetMinor: 1_500_000, availableDailyMinor: 40_000, surplusMinor: 130_000)
        #expect(plans.map(\.dailyMinor) == [5_000, 10_000, 13_333])
        #expect(plans.map(\.days) == [274, 137, 103])
        #expect(GoalPreparation.suggestions(targetMinor: 200_000, availableDailyMinor: 40_000, surplusMinor: 200_000).allSatisfy { $0.dailyMinor == 0 && $0.days == 0 })
        #expect(GoalPreparation.yearReserve(targetMinor: 8_000_000, balancedDailyMinor: 10_000, daysInYear: 354, reserveMinor: 5_000_000) == 4_460_000)
        #expect(GoalPreparation.days(remainingMinor: 1, dailyMinor: 0) == nil)
        let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 40_000))], plans: [.init(id: "goal", amountMinor: 13_333, period: .perDay, maximumMinorPerCycle: 30_000)], pausedDays: [2])
        #expect(CycleEngine.days(through: 5, input).map { $0.dripsMinor["goal"] ?? 0 } == [13_333, 0, 13_333, 3_334, 0])
        #expect(CycleEngine.day(4, input).dailyMinor == 36_666)
    }
    @Test func capTracksActualFundingAfterEarlierPlan() {
        let input = CycleInput(expectedLengthDays: 3, policies: [.init(mode: .fixed(allowanceMinor: 100))], plans: [.init(id: "first", amountMinor: 70, period: .perDay), .init(id: "goal", amountMinor: 80, period: .perDay, maximumMinorPerCycle: 50)])
        #expect(CycleEngine.days(through: 3, input).map { $0.dripsMinor["goal"] ?? 0 } == [30, 20, 0])
        #expect(CycleEngine.planFunding("goal", through: 3, input).shortMinor == 0)
    }
}
