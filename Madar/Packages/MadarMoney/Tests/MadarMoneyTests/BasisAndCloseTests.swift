import Testing
@testable import MadarMoney

/// M5-E01 golden cases for «على أي أساس», the close, offsets, runway and limits. Expected values from §7.5 (C0, L02, L05,
/// L14, the reserve example, F06) and RM1/RM2/RM9; source rows are written out, never the totals.
@Suite struct BasisAndCloseTests {
    /// C0 from source rows: two owned accounts and the mother's account, one credit card, Tamara 3 × 40000 unpaid,
    /// the loan instalment due, bills, and the envelope allocations (one debt envelope negative).
    static let c0 = BasisInput(
        accounts: [.init(balanceMinor: 9_000_000), .init(balanceMinor: 3_850_000), .init(balanceMinor: 500_000, ownership: .notMine)],
        creditCards: [.init(statementMinor: 680_000, unbilledMinor: 180_000)],
        installments: [.init(amountMinor: 40_000), .init(amountMinor: 40_000), .init(amountMinor: 40_000)],
        loanDueMinor: 285_000, billsDueMinor: 41_000,
        // reserve 10000000, surplus 300000, goal 16000, trip envelope +100000 − 120000 = −20000 → 10296000.
        envelopeAllocationsMinor: [10_000_000, 300_000, 16_000, 100_000, -120_000])

    @Test func c0BasisMatchesTheSpecFromSourceRows() {
        // في حسابك 12850000; عليك 680000 + 180000 + 120000 = 980000; لك فعلًا 11870000;
        // المحجوز 285000 + 41000 + 10296000 = 10622000; غير مخصّص 1248000.
        #expect(BasisEngine.basis(Self.c0) == Basis(inAccountMinor: 12_850_000, owedMinor: 980_000, netMinor: 11_870_000,
                                                     reservedMinor: 10_622_000, unallocatedMinor: 1_248_000))
    }

    @Test func rm9TheLoanIsReservedNotOwed() {
        // Paying the due loan instalment (F01 repayment): cash −285000, the due leaves «المحجوز»; «عليك» never held it.
        var paid = Self.c0
        paid.accounts[0].balanceMinor -= 285_000; paid.loanDueMinor = 0
        let before = BasisEngine.basis(Self.c0), after = BasisEngine.basis(paid)
        #expect(after.owedMinor == before.owedMinor)
        #expect(after.netMinor == before.netMinor - 285_000)
        #expect(after.reservedMinor == before.reservedMinor - 285_000)
        #expect(after.unallocatedMinor == before.unallocatedMinor)
    }

    @Test func cardPaymentMovesCashAndDebtTogether() {
        // F01: a card payment is a transfer — cash −, debt −, «لك فعلًا» unchanged. An overpayment lowers the unbilled.
        var paid = Self.c0
        paid.accounts[0].balanceMinor -= 700_000; paid.creditCards[0].paidSinceCloseMinor = 700_000
        let after = BasisEngine.basis(paid)
        #expect(paid.creditCards[0].statementLeftMinor == 0)
        #expect(paid.creditCards[0].unbilledLeftMinor == 160_000)
        #expect(after.netMinor == 11_870_000)
    }

    @Test func paymentBeyondTheWholeCardDebtLeavesNetUnchanged() {
        // F01: a payment is a transfer even beyond the whole debt; the extra stays on the card as credit.
        var paid = Self.c0
        let whole = paid.creditCards[0].statementMinor + paid.creditCards[0].unbilledMinor
        paid.accounts[0].balanceMinor -= whole + 50_000; paid.creditCards[0].paidSinceCloseMinor = whole + 50_000
        #expect(paid.creditCards[0].creditMinor == 50_000)
        let before = BasisEngine.basis(Self.c0), after = BasisEngine.basis(paid)
        #expect(after.netMinor == before.netMinor)
        #expect(after.owedMinor == before.owedMinor - whole)
        #expect(after.inAccountMinor == before.inAccountMinor - whole)
    }

    @Test func notMineAccountStaysOutOfCashAndNet() {
        var more = Self.c0
        more.accounts[2].balanceMinor += 1_000_000
        #expect(BasisEngine.basis(more) == BasisEngine.basis(Self.c0))
    }

    @Test func l02DeficitAtSalaryIsOffsetOrCarriedAndNoHalalaVanishes() {
        // «لك الآن» −42000 at the salary; surplus 500000. On: offset 42000, surplus 458000, carry 0. Off: carry −42000.
        let on = CycleClose.close(.init(availableNowMinor: -42_000, dailyMinor: 40_000, surplusMinor: 500_000))
        #expect(on.offsetMinor == 42_000)
        #expect(on.surplusAfterMinor == 458_000)
        #expect(on.carryMinor == 0)
        let off = CycleClose.close(.init(availableNowMinor: -42_000, dailyMinor: 40_000, surplusMinor: 500_000, autoOffset: false))
        #expect(off.carryMinor == -42_000)
        #expect(off.surplusAfterMinor == 500_000)
        // (لك الآن + الفوائض) before = after = 458000 in both.
        for result in [on, off] { #expect(result.carryMinor + result.surplusAfterMinor == 458_000) }
    }

    @Test func l14OffsetCapIsPerCycleNotPerEvent() {
        // Four deficits of 40000 in one cycle; cap 3 × 40000 = 120000.
        let outcomes = OffsetEngine.offset(deficitsMinor: [40_000, 40_000, 40_000, 40_000], dailyMinor: 40_000, surplusMinor: 1_000_000, enabled: true)
        #expect(outcomes.map(\.offsetMinor) == [40_000, 40_000, 40_000, 0])
        #expect(outcomes[3] == .init(offsetMinor: 0, remainingDeficitMinor: 40_000, shortfall: .cycleCapReached))
        #expect(outcomes.map(\.offsetMinor).reduce(0, +) <= 3 * 40_000)
    }

    @Test func offsetNeverTakesMoreThanTheSurplusHolds() {
        // L13 spirit: no negative surplus; a deficit above 3 dailies is not offset at all.
        let outcomes = OffsetEngine.offset(deficitsMinor: [30_000, 130_000], dailyMinor: 40_000, surplusMinor: 20_000, enabled: true)
        #expect(outcomes[0] == .init(offsetMinor: 20_000, remainingDeficitMinor: 10_000, shortfall: .surplusEmpty))
        #expect(outcomes[1].shortfall == .tooLarge)
    }

    @Test func remainderGoesToSurplusUpToItsCapThenReserve() {
        // «الباقي للفوائض حتى ١٠٬٠٠٠ ثم الاحتياطي»: surplus 950000, cap 1000000, leftover 80000 → 50000 + 30000.
        let result = CycleClose.close(.init(availableNowMinor: 80_000, dailyMinor: 40_000, surplusMinor: 950_000))
        #expect(result.toSurplusMinor == 50_000)
        #expect(result.toReserveMinor == 30_000)
        #expect(result.surplusAfterMinor == 1_000_000)
        #expect(CycleClose.close(.init(availableNowMinor: 80_000, dailyMinor: 40_000, surplusMinor: 0, remainder: .ask)).awaitingChoiceMinor == 80_000)
    }

    @Test func reserveRunwayInDailiesAndAfterObligations() {
        // §7.5: 100000 = 250 dailies = 8 months and 10 days.
        #expect(RunwayEngine.runway(balanceMinor: 10_000_000, dailyMinor: 40_000, cycleLengthDays: 30) == Runway(days: 250, cycles: 8, extraDays: 10))
        // RM9: obligations 3660 per cycle: ⌊10000000 × 30 ÷ (1200000 + 366000)⌋ = ⌊191.57⌋ = 191 days = 6 cycles 11 days.
        #expect(RunwayEngine.runway(balanceMinor: 10_000_000, dailyMinor: 40_000, cycleLengthDays: 30, obligationsPerCycleMinor: 366_000)
                == Runway(days: 191, cycles: 6, extraDays: 11))
        #expect(RunwayEngine.runway(balanceMinor: 10_000_000, dailyMinor: 0, cycleLengthDays: 30) == nil)
    }

    @Test func l05ZeroLimitIsALimitAndNoneIsNot() {
        #expect(LimitEngine.effectiveLimit(.fixed(limitMinor: 0), cycleIncomeMinor: 0, cycleAllowanceMinor: 0) == 0)
        #expect(LimitEngine.effectiveLimit(.none, cycleIncomeMinor: 0, cycleAllowanceMinor: 0) == nil)
        #expect(LimitEngine.shouldAlert80(spentMinor: 10_000, limitMinor: 0, alreadyFiredThisCycle: false))
        #expect(!LimitEngine.shouldAlert80(spentMinor: 10_000, limitMinor: nil, alreadyFiredThisCycle: false))
    }

    @Test func percentLimitFollowsEachCyclesBaseAndAlertsOncePerCycle() {
        // 30% of income: 1500000 → 450000; next cycle 1200000 → 360000.
        let mode = CategoryLimitMode.percent(basisPoints: 3_000, base: .income)
        #expect(LimitEngine.effectiveLimit(mode, cycleIncomeMinor: 1_500_000, cycleAllowanceMinor: 0) == 450_000)
        #expect(LimitEngine.effectiveLimit(mode, cycleIncomeMinor: 1_200_000, cycleAllowanceMinor: 0) == 360_000)
        // 80% of 450000 = 360000.
        #expect(LimitEngine.shouldAlert80(spentMinor: 360_000, limitMinor: 450_000, alreadyFiredThisCycle: false))
        #expect(!LimitEngine.shouldAlert80(spentMinor: 359_999, limitMinor: 450_000, alreadyFiredThisCycle: false))
        #expect(!LimitEngine.shouldAlert80(spentMinor: 440_000, limitMinor: 450_000, alreadyFiredThisCycle: true))
    }

    @Test func withinDayIsPendingUntilMessagesAreResolved() {
        #expect(WithinDayEngine.evaluate(dailySpentMinor: 40_000, dailyMinor: 40_000, hasUnresolvedMessage: false) == .met)
        #expect(WithinDayEngine.evaluate(dailySpentMinor: 40_001, dailyMinor: 40_000, hasUnresolvedMessage: false) == .missed)
        #expect(WithinDayEngine.evaluate(dailySpentMinor: 0, dailyMinor: 40_000, hasUnresolvedMessage: true) == .pending)
    }

    @Test func roundingIsHalfAwayFromZero() {
        #expect(MoneyMath.divideRounded(5, by: 2) == 3)
        #expect(MoneyMath.divideRounded(-5, by: 2) == -3)
        #expect(MoneyMath.divideRounded(4, by: 3) == 1)
        #expect(MoneyMath.applying(basisPoints: 4_000, to: 1_500_000) == 600_000)
        #expect(MoneyMath.applying(basisPoints: 10_000, to: 1_000_000_000_000_000) == 1_000_000_000_000_000)
        #expect(MoneyMath.applying(basisPoints: 5_000, to: Int.max) == 4_611_686_018_427_387_904)
        #expect(MoneyMath.applying(basisPoints: 10_000, to: Int.min) == Int.min)
        #expect(MoneyMath.applying(basisPoints: 3_333, to: 15_001) == 5_000)
        #expect(MoneyMath.applying(basisPoints: 5_000, to: -5) == -3)
    }
}
