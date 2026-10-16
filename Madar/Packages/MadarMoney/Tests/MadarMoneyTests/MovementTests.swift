import Foundation
import Testing
@testable import MadarMoney

/// M5-E02 golden cases: the F01 movement table (with RM1, RM4, RM5), F02 allocations (L03, L10–L13), F03 (L04,
/// instalments) and F04 currency. Expected values from §7.5 and the fixes file; invariants where the spec gives none.
@Suite struct MovementTests {
    // MARK: F01 and the table's invariants

    @Test func everyRowMovesNetAsCashMinusDebt() throws {
        let all: [Movement] = [.purchase(.account), .purchase(.debitCard), .purchase(.prepaidCard), .purchase(.creditCard), .purchase(.cashWallet),
                               .bnplPurchase, .bnplInstalment, .loanInstalment, .billPayment(linkedToObligation: true), .cardPayment,
                               .ownTransfer, .withdrawal, .externalTransfer(notSpend: false), .income(isSalary: true), .refund(.account),
                               .refund(.creditCard), .cashbackEarned, .cashbackRedeemed(.account), .cashbackRedeemed(.creditCard)]
        for movement in all {
            let e = MovementEngine.effect(movement, amountMinor: 10_000)
            #expect(e.netMinor == e.cashMinor - e.debtMinor, "\(movement)")
        }
    }

    @Test func f01TableOnTheAcceptanceMovements() throws {
        let a = 10_000
        // Own transfer: nothing changes. Withdrawal: cash 0 (bank − wallet +), charged by default.
        #expect(MovementEngine.effect(.ownTransfer, amountMinor: a) == .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: 0))
        #expect(MovementEngine.effect(.withdrawal, amountMinor: a) == .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: a))
        #expect(MovementEngine.effect(.withdrawal, amountMinor: a, settings: .init(cashWithdrawalAsSpend: false)).budgetChargeMinor == 0)
        // Cash spent from the wallet is not charged again while withdrawals are spending; charged when they are not.
        #expect(MovementEngine.effect(.purchase(.cashWallet), amountMinor: a).budgetChargeMinor == 0)
        #expect(MovementEngine.effect(.purchase(.cashWallet), amountMinor: a, settings: .init(cashWithdrawalAsSpend: false)).budgetChargeMinor == a)
        // Credit card purchase: debt +, net −, budget − on the purchase day. Card payment: cash −, debt −, budget 0.
        #expect(MovementEngine.effect(.purchase(.creditCard), amountMinor: a) == .init(cashMinor: 0, debtMinor: a, budgetChargeMinor: a))
        #expect(MovementEngine.effect(.cardPayment, amountMinor: a) == .init(cashMinor: -a, debtMinor: -a, budgetChargeMinor: 0))
        // Partial refund to a credit card: debt −, net +, budget + to the original's allocations.
        #expect(MovementEngine.effect(.refund(.creditCard), amountMinor: 4_000) == .init(cashMinor: 0, debtMinor: -4_000, budgetChargeMinor: -4_000))
        // Tamara instalment: cash −, debt −, net 0, budget 0. Loan instalment: cash −, net −, budget 0.
        #expect(MovementEngine.effect(.bnplInstalment, amountMinor: a).netMinor == 0)
        #expect(MovementEngine.effect(.loanInstalment, amountMinor: a) == .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: 0))
        // Earned cashback changes nothing; redeemed to the account raises cash and net, never the budget.
        #expect(MovementEngine.effect(.cashbackEarned, amountMinor: a) == .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: 0))
        #expect(MovementEngine.effect(.cashbackRedeemed(.account), amountMinor: a) == .init(cashMinor: a, debtMinor: 0, budgetChargeMinor: 0))
    }

    @Test func rm1DebitAndPrepaidPurchasesNeverBecomeCardDebt() throws {
        for method in [Movement.PayFrom.debitCard, .prepaidCard] {
            #expect(MovementEngine.effect(.purchase(method), amountMinor: 4_200) == .init(cashMinor: -4_200, debtMinor: 0, budgetChargeMinor: 4_200))
        }
    }

    @Test func rm4ObligationLinkedPaymentsAreBudgetNeutral() throws {
        #expect(MovementEngine.effect(.billPayment(linkedToObligation: true), amountMinor: 41_000).budgetChargeMinor == 0)
        #expect(MovementEngine.effect(.billPayment(linkedToObligation: false), amountMinor: 41_000).budgetChargeMinor == 41_000)
    }

    @Test func ignoredPurchaseKeepsCashRightAndLeavesTheBudget() throws {
        // F06: «تجاهله من الميزانيات» → no allocations; cash and «لك فعلًا» stay right.
        let e = MovementEngine.effect(.purchase(.account), amountMinor: 9_000, ignoredFromBudget: true)
        #expect(e == .init(cashMinor: -9_000, debtMinor: 0, budgetChargeMinor: 0))
    }

    @Test func externalTransferIsSpendUnlessMarkedOtherwise() throws {
        #expect(MovementEngine.effect(.externalTransfer(notSpend: false), amountMinor: 5_000).budgetChargeMinor == 5_000)
        #expect(MovementEngine.effect(.externalTransfer(notSpend: true), amountMinor: 5_000).budgetChargeMinor == 0)
    }

    // MARK: RM5 pairing

    @Test func rm5OwnTransferLegsPairAndOthersStayExternal() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let legs = [
            BankLeg(id: "out1", accountID: "current", direction: .out, amountMinor: 500_000, at: t0),
            BankLeg(id: "in1", accountID: "savings", direction: .in, amountMinor: 500_000, at: t0.addingTimeInterval(90)),
            // Same amount but 20 minutes later: outside the window.
            BankLeg(id: "out2", accountID: "current", direction: .out, amountMinor: 70_000, at: t0.addingTimeInterval(3_600)),
            BankLeg(id: "in2", accountID: "savings", direction: .in, amountMinor: 70_000, at: t0.addingTimeInterval(3_600 + 1_200)),
            // To the mother's account: not owned, never internal.
            BankLeg(id: "out3", accountID: "current", direction: .out, amountMinor: 30_000, at: t0.addingTimeInterval(7_200)),
            BankLeg(id: "in3", accountID: "mother", accountOwned: false, direction: .in, amountMinor: 30_000, at: t0.addingTimeInterval(7_230)),
        ]
        let pairs = TransferPairing.pairs(legs)
        #expect(pairs.count == 1)
        #expect(pairs.first?.out == "out1")
        #expect(pairs.first?.in == "in1")
    }

    // MARK: F02 allocations

    @Test func l12SplitIsExactAndCommittedOnce() throws {
        // 100 over three sources → 33 + 33 + 34; two previews then «اعتمد» → three allocations only.
        let rows = try AllocationEngine.spend(transactionID: "t", homeAmountMinor: 100, weighted: [(.daily, 1), (.envelope("e"), 1), (.reserve, 1)])
        #expect(rows.map(\.amountMinor) == [-33, -33, -34])
        #expect(rows.map(\.amountMinor).reduce(0, +) == -100)
        var ledger = AllocationLedger()
        _ = try AllocationEngine.spend(transactionID: "t", homeAmountMinor: 100, weighted: [(.daily, 1), (.envelope("e"), 1), (.reserve, 1)]) // preview
        ledger.commit(rows); ledger.commit(rows)
        #expect(ledger.rows.count == 3)
    }

    @Test func mixedSpendUndoRestoresEverySource() throws {
        var ledger = AllocationLedger()
        ledger.commit([AllocationRow(target: .envelope("e"), amountMinor: 200_000, kind: .fund, idempotencyKey: "fund:c1:p"),
                       AllocationRow(target: .reserve, amountMinor: 1_000_000, kind: .fund, idempotencyKey: "fund:c1:r")])
        ledger.commit(try AllocationEngine.spend(transactionID: "big", homeAmountMinor: 300_000, over: [(.daily, 40_000), (.envelope("e"), 160_000), (.reserve, 100_000)]))
        #expect(ledger.live(transactionID: "big").reduce(0) { $0 + $1.amountMinor } == -300_000)
        #expect(ledger.balance(.envelope("e")) == 40_000)
        ledger.undo(transactionID: "big")
        #expect(ledger.balance(.envelope("e")) == 200_000)
        #expect(ledger.balance(.reserve) == 1_000_000)
        #expect(ledger.balance(.daily) == 0)
    }

    @Test func refundReturnsToTheOriginalsAllocationsInProportion() throws {
        let original = try AllocationEngine.spend(transactionID: "o", homeAmountMinor: 90_000, over: [(.daily, 30_000), (.envelope("e"), 60_000)])
        let refund = AllocationEngine.refund(refundTransactionID: "r", homeAmountMinor: 45_000, original: original)
        // Half the purchase back: 15000 to «يومك», 30000 to the envelope.
        #expect(refund.map(\.amountMinor) == [15_000, 30_000])
        #expect(refund.map(\.target) == [.daily, .envelope("e")])
    }

    @Test func l03RepaymentPlanIsSeparateFromTheSavingPlan() throws {
        // «سفر» balance 200000, saving 50000/salary; a big expense 300000 from it, repaid over two salaries.
        var ledger = AllocationLedger()
        ledger.commit([AllocationRow(target: .envelope("safar"), amountMinor: 200_000, kind: .fund, idempotencyKey: "fund:c0:save")])
        ledger.commit(try AllocationEngine.spend(transactionID: "big", homeAmountMinor: 300_000, over: [(.envelope("safar"), 300_000)]))
        #expect(ledger.balance(.envelope("safar")) == -100_000)
        let plans = [EnvelopePlanSpec(id: "save", target: .envelope("safar"), source: .salary, perPaycheckMinor: 50_000),
                     EnvelopePlanSpec(id: "repay", target: .envelope("safar"), kind: .repay, source: .salary, perPaycheckMinor: 50_000, remainingPaychecks: 2)]
        let next = PlanEngine.salaryFunding(cycleID: "c1", salaryTransactionID: "salary1", plans: plans, surplusMinor: 0, reserveMinor: 0)
        #expect(next.rows.map(\.amountMinor) == [50_000, 50_000])
        #expect(Set(next.rows.map(\.idempotencyKey)) == ["fund:c1:save", "fund:c1:repay"])
        ledger.commit(next.rows)
        // A repeated salary message funds nothing twice.
        #expect(ledger.commit(PlanEngine.salaryFunding(cycleID: "c1", salaryTransactionID: "salary1", plans: plans, surplusMinor: 0, reserveMinor: 0).rows).isEmpty)
        #expect(ledger.balance(.envelope("safar")) == 0)
    }

    @Test func l13SurplusFundingGivesWhatItHasAndSaysWhatIsShort() throws {
        // Plan 50000 from the surplus while the surplus holds 20000 → 20000 moved, «ينقص 30000», surplus not negative.
        let plan = EnvelopePlanSpec(id: "goal", target: .goal("g"), source: .surplus, perPaycheckMinor: 50_000)
        let result = PlanEngine.salaryFunding(cycleID: "c1", salaryTransactionID: "s", plans: [plan], surplusMinor: 20_000, reserveMinor: 0)
        var ledger = AllocationLedger(rows: [AllocationRow(target: .surplus, amountMinor: 20_000, kind: .fund, idempotencyKey: "seed")])
        ledger.commit(result.rows)
        #expect(ledger.balance(.goal("g")) == 20_000)
        #expect(ledger.balance(.surplus) == 0)
        #expect(result.shortfalls == [.init(planID: "goal", shortMinor: 30_000)])
        #expect(result.rows.reduce(0) { $0 + $1.amountMinor } == 0)
    }

    @Test func l10TripSpendingLandsOnTheTripEnvelopeOnce() throws {
        // Trip of 5 days, envelope 500000, a purchase worth 120000 → envelope 380000, daily 0 on trip days, total effect once.
        var ledger = AllocationLedger(rows: [AllocationRow(target: .envelope("trip"), amountMinor: 500_000, kind: .fund, idempotencyKey: "fund:c1:trip")])
        let charge = MovementEngine.effect(.purchase(.creditCard), amountMinor: 120_000).budgetChargeMinor
        ledger.commit(try AllocationEngine.spend(transactionID: "dinner", homeAmountMinor: charge, over: [(.envelope("trip"), charge)]))
        #expect(ledger.balance(.envelope("trip")) == 380_000)
        #expect(ledger.balance(.daily) == 0)
        var cycle = CycleEngineTests.c0
        cycle.pausedDays = [3, 4, 5, 6, 7]
        #expect((3...7).map { CycleEngine.day($0, cycle).allowanceMinor } == [0, 0, 0, 0, 0])
        #expect(ledger.live(transactionID: "dinner").reduce(0) { $0 + $1.amountMinor } == -120_000)
    }

    @Test func l11TamaraPurchaseIsChargedOnceAndInstalmentsAreNeutral() throws {
        // 120000 in 3 × 40000; two paid.
        let purchase = MovementEngine.effect(.bnplPurchase, amountMinor: 120_000)
        #expect(purchase.debtMinor == 120_000)
        #expect(purchase.netMinor == -120_000)
        var ledger = AllocationLedger()
        ledger.commit(try AllocationEngine.spend(transactionID: "tamara", homeAmountMinor: purchase.budgetChargeMinor, over: [(.envelope("tamara"), 120_000)]))
        #expect(ledger.balance(.envelope("tamara")) == -120_000)
        // «لك الآن» does not move: nothing on «يومك».
        #expect(ledger.balance(.daily) == 0)
        var items = [InstallmentState(amountMinor: 40_000), InstallmentState(amountMinor: 40_000), InstallmentState(amountMinor: 40_000)]
        for i in 0..<2 {
            let e = MovementEngine.effect(.bnplInstalment, amountMinor: 40_000)
            #expect(e == .init(cashMinor: -40_000, debtMinor: -40_000, budgetChargeMinor: 0))
            items = InstallmentEngine.pay(items, index: i, amountMinor: 40_000)
        }
        #expect(items.reduce(0) { $0 + $1.leftMinor } == 40_000)
    }

    @Test func partialInstalmentPaymentKeepsItOpen() throws {
        let items = InstallmentEngine.pay([InstallmentState(amountMinor: 40_000)], index: 0, amountMinor: 15_000)
        #expect(!InstallmentEngine.isClosed(items[0]))
        #expect(items[0].leftMinor == 25_000)
    }

    // MARK: F03

    @Test func l04MidCycleReconciliationCountsTheDailiesNotYetAccrued() throws {
        // 30-day cycle at 40000; start balance 2000000; recorded 380000; day 10 the bank says 1620000.
        let cycle = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 40_000))])
        let result = ReconciliationEngine.reconcile(lastConfirmedMinor: 2_000_000, inflowsMinor: 0, outflowsMinor: 380_000, observedMinor: 1_620_000,
                                                    notYetAccruedMinor: ReconciliationEngine.notYetAccrued(elapsedDays: 10, cycle))
        // Expected 1620000, difference 0; «لم يُستحق بعد من يومياتك 800000» = 20 × 40000.
        #expect(result == .init(expectedMinor: 1_620_000, observedMinor: 1_620_000, deltaMinor: 0, notYetAccruedMinor: 800_000))
    }

    @Test func adjustmentIsBudgetNeutralUnlessItIsUnrecordedSpend() throws {
        #expect(MovementEngine.effect(.adjustment(unrecordedSpend: false), amountMinor: -12_000) == .init(cashMinor: -12_000, debtMinor: 0, budgetChargeMinor: 0))
        #expect(MovementEngine.effect(.adjustment(unrecordedSpend: true), amountMinor: -12_000).budgetChargeMinor == 12_000)
    }

    // MARK: F04

    @Test func f04HomeAmountsRoundHalfAwayFromZero() throws {
        // Test rates from §7.5 (not real rates): USD 1234 × 3.75 = 4628; JPY 1500 × 0.025 = 3750; KWD 1250 × 12.2 = 1525.
        #expect(try FX.homeAmount(amountMinor: 1_234, currency: "USD", rate: "3.75") == 4_628)
        #expect(try FX.homeAmount(amountMinor: 1_500, currency: "JPY", rate: "0.025") == 3_750)
        #expect(try FX.homeAmount(amountMinor: 1_250, currency: "KWD", rate: "12.2") == 1_525)
        #expect(try FX.homeAmount(amountMinor: 9_999, currency: "SAR", rate: "1") == 9_999)
    }

    @Test func f04RefundUsesTheOriginalRateAndAFullRefundMatchesExactly() throws {
        let original = (amountMinor: 1_234, homeAmountMinor: try FX.homeAmount(amountMinor: 1_234, currency: "USD", rate: "3.75"), currency: "USD", rate: Optional("3.75"))
        #expect(try FX.refundHomeAmount(refundMinor: 1_234, original: original) == 4_628)
        // Partial: 617 × 3.75 = 2313.75 → 2314.
        #expect(try FX.refundHomeAmount(refundMinor: 617, original: original) == 2_314)
        // The refund message states the riyal amount: that wins.
        #expect(try FX.refundHomeAmount(refundMinor: 617, original: original, statedHomeMinor: 2_300) == 2_300)
    }

    @Test func f04RatesAreCanonicalDecimalStrings() throws {
        for bad in ["", "3,75", "-1", "0", "1e3", "3.", ".5", "1.1234567890123"] {
            #expect(throws: FXError.self) { try FX.parseRate(bad) }
        }
        #expect(throws: FXError.unknownCurrency("XYZ")) { try FX.homeAmount(amountMinor: 1, currency: "XYZ", rate: "1") }
    }

    // MARK: Review fixes (16 Oct)

    @Test func spendRefusesPartsThatDoNotAddUp() {
        // home 100 split as 120 + 10 would have turned the envelope part into funding.
        #expect(throws: AllocationEngine.SplitError.partsDoNotAddUp) { try AllocationEngine.spend(transactionID: "t", homeAmountMinor: 100, over: [(.daily, 120), (.envelope("e"), 10)]) }
        #expect(throws: AllocationEngine.SplitError.negativePart) { try AllocationEngine.spend(transactionID: "t", homeAmountMinor: 100, over: [(.daily, 120), (.envelope("e"), -20)]) }
    }

    @Test func partialRefundsThatCompleteTheOriginalDoNotDriftAHalala() throws {
        // USD 1235 × 3.75 = 4631.25 → 4631. Refund 617 → 2313.75 → 2314; the completing 618 gets 4631 − 2314 = 2317 (not 2318).
        let home = try FX.homeAmount(amountMinor: 1_235, currency: "USD", rate: "3.75")
        #expect(home == 4_631)
        let original = (amountMinor: 1_235, homeAmountMinor: home, currency: "USD", rate: Optional("3.75"))
        let first = try FX.refundHomeAmount(refundMinor: 617, original: original)
        #expect(first == 2_314)
        let second = try FX.refundHomeAmount(refundMinor: 618, original: original, priorRefundsMinor: 617, priorRefundsHomeMinor: first)
        #expect(second == 2_317)
        #expect(first + second == home)
    }

    @Test func feesAreChargedAndReversalsAreRefunds() {
        #expect(MovementEngine.effect(.fee(onCard: false), amountMinor: 2_500) == .init(cashMinor: -2_500, debtMinor: 0, budgetChargeMinor: 2_500))
        #expect(MovementEngine.effect(.fee(onCard: true), amountMinor: 2_500) == .init(cashMinor: 0, debtMinor: 2_500, budgetChargeMinor: 2_500))
        #expect(MovementEngine.effect(.reversal(.creditCard), amountMinor: 9_000) == MovementEngine.effect(.refund(.creditCard), amountMinor: 9_000))
    }
}
