import Foundation
import Testing
@testable import MadarMoney

/// M5-V19: expected values by hand from F06 («حساب الوالدة لا يدخل لك فعلًا»), RM5 (an untracked wallet's balance is not
/// owned cash) and the canonical's rows (`mal/28-Z-R19-acc`) used as inputs.
struct AccountsTreeTests {
    // Current 128,500.00; platinum card 6,800.00; travel card 1,800.00; Tamara 1,200.00; tracked wallet 0; mother's 14,200.00.
    let roots = [
        AccountRoot(id: "current", side: .cash, amountMinor: 12_850_000),
        AccountRoot(id: "platinum", side: .creditCard, amountMinor: 680_000),
        AccountRoot(id: "travel", side: .creditCard, amountMinor: 180_000),
        AccountRoot(id: "tamara", side: .instalment, amountMinor: 120_000),
        AccountRoot(id: "wallet", side: .cash, amountMinor: 0),
        AccountRoot(id: "mother", side: .cash, amountMinor: 1_420_000, counts: false),
    ]

    @Test func trunkIsCashMinusDebtAndTheCutRootStaysOut() {
        // 128,500 − (6,800 + 1,800 + 1,200) = 118,700; the 14,200 is drawn but never summed.
        #expect(AccountsTree.totals(roots) == .init(cashMinor: 12_850_000, owedMinor: 980_000, netMinor: 11_870_000, leftOutMinor: 1_420_000))
    }

    @Test func theTrunkIsTheBasisNumber() {
        let basis = BasisEngine.basis(.init(accounts: [.init(balanceMinor: 12_850_000), .init(balanceMinor: 0)],
            creditCards: [.init(statementMinor: 680_000, unbilledMinor: 0), .init(statementMinor: 100_000, unbilledMinor: 80_000)],
            installments: [.init(amountMinor: 40_000), .init(amountMinor: 40_000), .init(amountMinor: 40_000)]))
        #expect(AccountsTree.totals(roots).netMinor == basis.netMinor)
    }

    @Test func untrackedWalletIsLeftOutLikeAnAccountThatIsNotMine() {
        // RM5: an untracked wallet's top-ups are spending, so its balance is not owned cash.
        let wallet = [AccountRoot(id: "current", side: .cash, amountMinor: 50_000), AccountRoot(id: "urpay", side: .cash, amountMinor: 7_500, counts: false)]
        #expect(AccountsTree.totals(wallet) == .init(cashMinor: 50_000, owedMinor: 0, netMinor: 50_000, leftOutMinor: 7_500))
        // Debts larger than cash: «لك فعلًا» goes below zero, never clamped.
        #expect(AccountsTree.totals([.init(id: "a", side: .cash, amountMinor: 10_000), .init(id: "c", side: .creditCard, amountMinor: 25_000)]).netMinor == -15_000)
    }

    @Test func rootWeightFollowsTheSquareRootOfTheAmount() {
        #expect(AccountsTree.rootWeight(amountMinor: 12_850_000, largestMinor: 12_850_000) == 1)
        #expect(AccountsTree.rootWeight(amountMinor: 0, largestMinor: 12_850_000) == 0)
        #expect(AccountsTree.rootWeight(amountMinor: 250, largestMinor: 1_000) == 0.5)
        #expect(AccountsTree.rootWeight(amountMinor: 5, largestMinor: 0) == 0)
    }

    @Test func newestEvidenceTellsHowTheBalanceIsKnown() {
        let day: TimeInterval = 86_400, start = Date(timeIntervalSince1970: 1_790_000_000)
        // Only the opening balance.
        #expect(AccountsTree.source(openingAt: start, reconciledAt: nil, message: nil) == .entered(at: start))
        // A later message that printed the book's own balance confirms it.
        #expect(AccountsTree.source(openingAt: start, reconciledAt: nil, message: (start + day, 12_850_000, 12_850_000)) == .message(at: start + day))
        // A message printed 320.00 less than the book.
        #expect(AccountsTree.source(openingAt: start, reconciledAt: nil, message: (start + day, 12_850_000, 12_882_000))
            == .messageDiffers(at: start + day, printedMinor: 12_850_000, differenceMinor: -32_000))
        // A reconciliation after the message wins; on the same instant the reconciliation still wins.
        #expect(AccountsTree.source(openingAt: start, reconciledAt: start + 2 * day, message: (start + day, 1, 1)) == .reconciled(at: start + 2 * day))
        #expect(AccountsTree.source(openingAt: start, reconciledAt: start + day, message: (start + day, 1, 1)) == .reconciled(at: start + day))
        // Nothing known.
        #expect(AccountsTree.source(openingAt: nil, reconciledAt: nil, message: nil) == nil)
    }
}
