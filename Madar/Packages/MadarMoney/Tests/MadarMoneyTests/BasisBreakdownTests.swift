import Testing
@testable import MadarMoney

struct BasisBreakdownTests {
    @Test func c0ColumnIsAConservingExplanationOfTheSameNetAmount() {
        // C0: 12,850,000 − 980,000 = 11,870,000; reserved 10,622,000.
        // 24 future dailies × 40,000 = 960,000; current entitlement 136,000.
        let basis = BasisEngine.basis(.init(accounts: [.init(balanceMinor: 12_850_000)],
            creditCards: [.init(statementMinor: 680_000, unbilledMinor: 180_000)], installments: [.init(amountMinor: 120_000)],
            loanDueMinor: 285_000, billsDueMinor: 41_000, envelopeAllocationsMinor: [10_296_000]))
        let parts = BasisBreakdownEngine.explain(basis, futureDailyMinor: 960_000, availableNowMinor: 136_000)
        #expect(parts.unallocatedMinor == 1_248_000); #expect(parts.cycleRemainderMinor == 152_000)
        #expect(parts.reservedMinor + parts.futureDailyMinor! + parts.availableNowMinor! + parts.cycleRemainderMinor! == 11_870_000)
    }
    @Test func unsetDailyIsNotShownAsZeroAndShortfallKeepsItsSign() {
        let basis = BasisEngine.basis(.init(accounts: [.init(balanceMinor: 1000)], envelopeAllocationsMinor: [1200]))
        let noDaily = BasisBreakdownEngine.explain(basis, futureDailyMinor: nil, availableNowMinor: nil)
        #expect(noDaily.futureDailyMinor == nil); #expect(noDaily.cycleRemainderMinor == nil); #expect(noDaily.unallocatedMinor == -200)
        let deficit = BasisBreakdownEngine.explain(basis, futureDailyMinor: 300, availableNowMinor: -100)
        #expect(deficit.cycleRemainderMinor == -400)
    }
}
