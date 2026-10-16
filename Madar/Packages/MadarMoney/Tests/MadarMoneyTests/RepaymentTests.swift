import Testing
@testable import MadarMoney
struct RepaymentTests {
    @Test func canonicalNineHundredOnThreeSalaries() throws {
        let p = try #require(RepaymentEngine.preview(debtMinor: 90_000, salaries: 3, dailyMinor: 40_000, cycleDays: 30))
        #expect(p.installmentsMinor == [30_000, 30_000, 30_000]); #expect(p.dailyAfterMinor == [39_000, 39_000, 39_000])
    }
    @Test func remainderNegativeForecastAndRealCycleLength() throws {
        let p = try #require(RepaymentEngine.preview(debtMinor: 100_001, salaries: 3, dailyMinor: 1_000, cycleDays: 29))
        #expect(p.installmentsMinor == [33_333, 33_333, 33_335]); #expect(p.dailyAfterMinor == [-149, -149, -149])
        #expect(RepaymentEngine.preview(debtMinor: 0, salaries: 3, dailyMinor: 1, cycleDays: 30) == nil)
        #expect(RepaymentEngine.preview(debtMinor: 1, salaries: 7, dailyMinor: 1, cycleDays: 30) == nil)
    }

    /// L03 golden row: «سفر» 200000 with saving 50000/salary; a 300000 expense → −100000, repaid over two salaries.
    /// The next salary writes +50000 (fund) and +50000 (repay) under two keys; the saving plan does not change.
    @Test func l03AdoptedRepaymentPaysTwoSalariesBesideTheUnchangedSavingPlan() throws {
        var ledger = AllocationLedger()
        ledger.commit([AllocationRow(target: .envelope("safar"), amountMinor: 200_000, kind: .fund, idempotencyKey: "fund:c0:save")])
        ledger.commit(try AllocationEngine.spend(transactionID: "big", homeAmountMinor: 300_000, over: [(.envelope("safar"), 300_000)]))
        let debt = -ledger.balance(.envelope("safar"))
        #expect(debt == 100_000)
        let save = EnvelopePlanSpec(id: "save", target: .envelope("safar"), source: .salary, perPaycheckMinor: 50_000)
        var state = RepaymentPlanState(totalMinor: debt, paychecks: 2)
        for (cycle, expected) in [("c1", 50_000), ("c2", 50_000)] {
            let repay = try #require(EnvelopePlanSpec.repayment(id: "repay", target: .envelope("safar"), source: .salary, state))
            let rows = PlanEngine.salaryFunding(cycleID: cycle, salaryTransactionID: "salary-" + cycle, plans: [save, repay], surplusMinor: 0, reserveMinor: 0).rows
            #expect(rows.map(\.amountMinor) == [50_000, expected])
            #expect(rows.map(\.idempotencyKey) == ["fund:\(cycle):save", "fund:\(cycle):repay"])
            #expect(rows.map(\.kind) == [.fund, .repay])
            ledger.commit(rows)
            state.paidMinor += expected; state.paidCount += 1
        }
        #expect(save.perPaycheckMinor == 50_000)
        #expect(EnvelopePlanSpec.repayment(id: "repay", target: .envelope("safar"), source: .salary, state) == nil)
        // 200000 − 300000 + 2 × 50000 saving + 2 × 50000 repayment = 100000.
        #expect(ledger.balance(.envelope("safar")) == 100_000)
    }
    /// 100001 over three salaries: 33333 + 33333 + (100001 − 66666 = 33335); hand arithmetic, not engine output.
    @Test func lastSalaryPaysTheExactRemainderWhateverTheDates() throws {
        var state = RepaymentPlanState(totalMinor: 100_001, paychecks: 3)
        var paid: [Int] = []
        while let next = RepaymentEngine.nextPayment(state) { paid.append(next); state.paidMinor += next; state.paidCount += 1 }
        #expect(paid == [33_333, 33_333, 33_335])
        #expect(state.paidMinor == 100_001)
        // Two early salaries in one cycle still count as two payments; a late one counts once: progress is by payment.
        #expect(RepaymentEngine.nextPayment(.init(totalMinor: 100_001, paychecks: 3, paidMinor: 66_666, paidCount: 2)) == 33_335)
    }
    /// L13: a surplus-funded payment that fell short (20000 of 50000) leaves 80000; the last salary pays 80000.
    @Test func shortPaymentIsCaughtUpByTheLastSalary() throws {
        #expect(RepaymentEngine.nextPayment(.init(totalMinor: 100_000, paychecks: 2, paidMinor: 20_000, paidCount: 1)) == 80_000)
        // After the planned count, whatever is still owed stays due rather than vanishing.
        #expect(RepaymentEngine.nextPayment(.init(totalMinor: 100_000, paychecks: 2, paidMinor: 90_000, paidCount: 2)) == 10_000)
        #expect(RepaymentEngine.nextPayment(.init(totalMinor: 100_000, paychecks: 2, paidMinor: 100_000, paidCount: 2)) == nil)
        #expect(RepaymentEngine.nextPayment(.init(totalMinor: 0, paychecks: 2)) == nil)
    }
}
