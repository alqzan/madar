import Testing
@testable import MadarMoney

struct BigExpenseTests {
    @Test func anExistingEnvelopeRepaysOnlyItsNewDebtL03() throws {
        // L03: 2000 saved, 3000 purchase, repay only 1000 over two salaries; the saving plan is independent.
        let p = try #require(BigExpense.plan(amountMinor: 300000, mode: .installments, availableMinor: 0, surplusMinor: 0, reserveMinor: 0, dailyMinor: 40000, cycleDays: 30, cycles: 2, envelopeBalanceMinor: 200000))
        #expect(p.futureMinor == 300000); #expect(p.repaymentMinor == 100000); #expect(p.paymentsMinor == [50000, 50000])
    }
    @Test func canonicalMixedPurchaseHasOneMeaningForEachSource() throws {
        // §7.5 / mal/27: 4800 = 960 current + 1400 surplus + 2440 future.
        // 244000 / 30 = 8133 with 10 on the final day; lowest daily = 40000 - 8143 = 31857.
        let p = try #require(BigExpense.plan(amountMinor: 480_000, mode: .mixed, availableMinor: 96_000, surplusMinor: 140_000, reserveMinor: 1_000_000, dailyMinor: 40_000, cycleDays: 30))
        #expect(p.dailyMinor == 96_000); #expect(p.surplusMinor == 140_000); #expect(p.futureMinor == 244_000)
        #expect(p.reserveMinor == 0); #expect(p.paymentsMinor == [244_000]); #expect(p.lowestDailyMinor == 31_857)
        #expect(p.dailyMinor + p.surplusMinor + p.reserveMinor + p.futureMinor == 480_000)
    }
    @Test func twelveCyclesAndThirdOfDailyAreHardLimits() {
        // 12000 per day, one third 4000. 30 days = 120000 per cycle, 12 cycles = 1440000.
        #expect(BigExpense.minimumCycles(debtMinor: 1_440_000, dailyMinor: 12_000, cycleDays: 30) == 12)
        #expect(BigExpense.minimumCycles(debtMinor: 1_440_001, dailyMinor: 12_000, cycleDays: 30) == nil)
        #expect(BigExpense.minimumCycles(debtMinor: 10_000, dailyMinor: 0, cycleDays: 30) == nil)
        #expect(BigExpense.plan(amountMinor: 480_000, mode: .installments, availableMinor: 0, surplusMinor: 0, reserveMinor: 0, dailyMinor: 40_000, cycleDays: 30, cycles: 1) == nil)
    }
    @Test func manualChoicesAndRemaindersStayExact() throws {
        let daily = try #require(BigExpense.plan(amountMinor: 420_001, mode: .daily, availableMinor: -10, surplusMinor: 0, reserveMinor: 0, dailyMinor: 0, cycleDays: 28))
        #expect(daily.dailyMinor == 420_001); #expect(daily.futureMinor == 0)
        #expect(BigExpense.plan(amountMinor: 420_001, mode: .reserve, availableMinor: 0, surplusMinor: 0, reserveMinor: 420_000, dailyMinor: 0, cycleDays: 28) == nil)
        let p = try #require(BigExpense.plan(amountMinor: 300_001, mode: .installments, availableMinor: 100_000, surplusMinor: 200_000, reserveMinor: 999_999, dailyMinor: 40_000, cycleDays: 30, cycles: 2))
        #expect(p.paymentsMinor == [150_000, 150_001]); #expect(p.dailyMinor == 0); #expect(p.paymentsMinor.reduce(0,+) == 300_001)
    }
}
