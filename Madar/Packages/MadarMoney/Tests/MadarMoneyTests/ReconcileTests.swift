import Testing
@testable import MadarMoney

/// M5-V15 / F03: expected values by hand from the canonical rows (`mal/24-Z-R19-rec`) and the F01 movement table.
struct ReconcileTests {
    // Account: Madar 128,820.00, bank 128,500.00 → −320.00. Card: Madar owes 4,130.00, bank 4,250.00 → +120.00.
    let account = ReconcileLine(side: .account, expectedMinor: 12_882_000, observedMinor: 12_850_000)
    let card = ReconcileLine(side: .creditCard, expectedMinor: 413_000, observedMinor: 425_000)

    @Test func differencesAndTheirEffectOnNet() {
        #expect(account.deltaMinor == -32_000); #expect(account.isShortfall); #expect(account.netEffectMinor == -32_000)
        #expect(card.deltaMinor == 12_000); #expect(card.isShortfall); #expect(card.netEffectMinor == -12_000)
        // Settling both lowers «لك فعلًا» by 320 + 120 = 440.00.
        #expect(account.netEffectMinor + card.netEffectMinor == -44_000)
    }

    @Test func accountAdjustmentMovesCashAndOnlyMissedSpendTouchesTheBudget() throws {
        #expect(ReconcileEngine.effect(account, resolution: "adjust") == .init(cashMinor: -32_000, debtMinor: 0, budgetChargeMinor: 0))
        #expect(ReconcileEngine.effect(account, resolution: "unrecordedSpend") == .init(cashMinor: -32_000, debtMinor: 0, budgetChargeMinor: 32_000))
        #expect(ReconcileEngine.effect(account, resolution: "leave") == nil)
    }

    @Test func cardAdjustmentMovesDebtNotCash() {
        #expect(ReconcileEngine.effect(card, resolution: "unrecordedSpend") == .init(cashMinor: 0, debtMinor: 12_000, budgetChargeMinor: 12_000))
        #expect(ReconcileEngine.effect(card, resolution: "adjust") == .init(cashMinor: 0, debtMinor: 12_000, budgetChargeMinor: 0))
        // A card owing less than Madar thinks: debt falls, never a budget refund.
        let less = ReconcileLine(side: .creditCard, expectedMinor: 413_000, observedMinor: 400_000)
        #expect(MovementEngine.effect(.cardAdjustment(unrecordedSpend: true), amountMinor: less.deltaMinor) == .init(cashMinor: 0, debtMinor: -13_000, budgetChargeMinor: 0))
    }

    @Test func namesFollowTheSignOfTheDifference() {
        let surplus = ReconcileLine(side: .account, expectedMinor: 100_000, observedMinor: 105_000)
        let match = ReconcileLine(side: .account, expectedMinor: 134_000, observedMinor: 134_000)
        #expect(ReconcileEngine.names(for: account) == [.missedSpend, .bankFee, .unexplained])
        #expect(ReconcileEngine.names(for: surplus) == [.unexplained])
        #expect(ReconcileEngine.names(for: match).isEmpty)
        #expect(ReconcileEngine.resolution(.missedSpend, for: account) == "unrecordedSpend")
        #expect(ReconcileEngine.resolution(.bankFee, for: account) == "unrecordedSpend")
        #expect(ReconcileEngine.resolution(.unexplained, for: account) == "adjust")
        #expect(ReconcileEngine.resolution(nil, for: account) == "leave")
        #expect(ReconcileEngine.resolution(.missedSpend, for: surplus) == nil, "A surplus is never spending")
        #expect(ReconcileEngine.resolution(nil, for: match) == "adjust")
        #expect(ReconcileEngine.effect(match, resolution: "adjust") == nil, "A match writes no movement")
    }

    @Test func summaryCountsOpenDifferencesAndSettlements() {
        let match = ReconcileLine(side: .account, expectedMinor: 134_000, observedMinor: 134_000)
        // Canonical footer: two open differences, −320 and +120.
        #expect(ReconcileEngine.summary([(account, nil), (match, nil), (card, nil)]) == .init(open: 2, negativeMinor: -32_000, positiveMinor: 12_000, settlements: 0))
        // Both named: «تُكتب تسويتان».
        #expect(ReconcileEngine.summary([(account, .missedSpend), (match, nil), (card, .unexplained)]).settlements == 2)
    }

    @Test func installmentDifferenceStaysAnOpenDebtCheckWithoutSpendingOrMovement() {
        let providerBalance = ReconcileLine(side: .installment, expectedMinor: 80_000, observedMinor: 90_000)
        #expect(providerBalance.deltaMinor == 10_000)
        #expect(!providerBalance.isShortfall)
        #expect(providerBalance.netEffectMinor == -10_000, "More owed reduces net money")
        #expect(ReconcileEngine.names(for: providerBalance).isEmpty, "A provider difference has no spending classification")
        #expect(ReconcileEngine.resolution(nil, for: providerBalance) == "leave")
        #expect(ReconcileEngine.resolution(.unexplained, for: providerBalance) == nil)
        #expect(ReconcileEngine.effect(providerBalance, resolution: "leave") == nil)
        #expect(ReconcileEngine.summary([(providerBalance, nil)]) == .init(open: 1, negativeMinor: 0, positiveMinor: 10_000, settlements: 0))
    }

    @Test func nudgeMovesWholeUnitsAndStopsAtZero() {
        #expect(ReconcileEngine.nudge(12_850_000, units: -100, exponent: 2) == 12_840_000)
        #expect(ReconcileEngine.nudge(413_000, units: 10, exponent: 2) == 414_000)
        #expect(ReconcileEngine.nudge(500, units: -10, exponent: 2) == 0)
        #expect(ReconcileEngine.nudge(5_000, units: -10, exponent: 3) == 0)
        #expect(ReconcileEngine.nudge(5_000, units: 1, exponent: 0) == 5_001)
    }
}
