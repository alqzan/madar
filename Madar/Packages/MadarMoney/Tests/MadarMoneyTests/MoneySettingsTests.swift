import Testing
@testable import MadarMoney
struct MoneySettingsTests {
    @Test func ownerOffsetCapIsPerCycleAndNeverErasesTheRest() {
        // 2 dailies of 400 = 800 for the whole cycle; two deficits of 500 leave 200 carried.
        let p = OffsetEngine.offset(deficitsMinor: [50000,50000], dailyMinor: 40000, surplusMinor: 200000, enabled: true, capDailies: 2)
        #expect(p.map(\.offsetMinor) == [50000,30000]); #expect(p.map(\.remainingDeficitMinor) == [0,20000])
        let close = CycleClose.close(.init(availableNowMinor: -90000, dailyMinor: 40000, surplusMinor: 200000, offsetCapDailies: 2))
        #expect(close.offsetMinor == 0); #expect(close.carryMinor == -90000); #expect(close.surplusAfterMinor == 200000)
        #expect(ExpenseThreshold.amount(.dailies(3), dailyMinor: 40000, salaryMinor: 1500000) == 120000)
    }
    @Test func ownersAlternativeBigExpenseThresholds() {
        #expect(ExpenseThreshold.amount(.salaryPercent(basisPoints: 1000), dailyMinor: 40000, salaryMinor: 1500000) == 150000)
        #expect(ExpenseThreshold.amount(.amount(90000), dailyMinor: nil, salaryMinor: nil) == 90000)
        #expect(ExpenseThreshold.amount(.salaryPercent(basisPoints: 1000), dailyMinor: 40000, salaryMinor: 0) == nil)
    }
}
