import Foundation
import Testing
@testable import MadarMoney

/// M5-E04: the F11 fixtures, as amended by RM7. Expected values from §7.5 «Fixtures».
@Suite struct ZakatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Pool 12850000 from the C0 owned accounts; the mother's account is outside it.
    var c0: ZakatInput {
        ZakatInput(accounts: [.init(balanceMinor: 9_000_000), .init(balanceMinor: 3_850_000), .init(balanceMinor: 500_000, owned: false)],
                   owedAllMinor: 980_000, goldPricePerGramMinor: 40_000, goldPriceSetAt: now, hawlStartHijri: "h:1447-09-01")
    }

    @Test func noneDeductsNothing() {
        var input = c0; input.debtsPolicy = .none
        let result = ZakatEngine.assess(input, now: now)
        // 12850000 × 2.5% = 321250 (٣٬٢١٢٫٥٠).
        #expect(result.poolMinor == 12_850_000)
        #expect(result.outcome == .due(amountMinor: 321_250))
        #expect(result.approximate)
    }

    @Test func allOwedDeductsTheWholeOfWhatIsOwed() {
        var input = c0; input.debtsPolicy = .allOwed
        // (12850000 − 980000) × 2.5% = 296750.
        #expect(ZakatEngine.assess(input, now: now).outcome == .due(amountMinor: 296_750))
    }

    @Test func nisabFromTheGoldPrice() {
        var input = c0; input.debtsPolicy = .none
        // 85 g × 40000 = 3400000.
        #expect(ZakatEngine.assess(input, now: now).nisabMinor == 3_400_000)
    }

    @Test func belowNisabShowsNoAmount() {
        let input = ZakatInput(accounts: [.init(balanceMinor: 3_000_000)], debtsPolicy: .none, goldPricePerGramMinor: 40_000, goldPriceSetAt: now)
        #expect(ZakatEngine.assess(input, now: now).outcome == .belowNisab)
    }

    @Test func unsetDebtChoiceAsksBeforeAnyNumber() {
        #expect(ZakatEngine.assess(c0, now: now).outcome == .askDebts)
    }

    @Test func aFortyDayOldPriceAsksToBeUpdated() {
        var input = c0; input.debtsPolicy = .none
        input.goldPriceSetAt = now.addingTimeInterval(-40 * 86_400)
        #expect(ZakatEngine.assess(input, now: now).goldPriceStale)
        input.goldPriceSetAt = now.addingTimeInterval(-29 * 86_400)
        #expect(!ZakatEngine.assess(input, now: now).goldPriceStale)
    }

    @Test func unknownHawlAsksForADate() {
        var input = c0; input.hawlStartHijri = nil
        #expect(ZakatEngine.assess(input, now: now).hawlUnknown)
    }

    @Test func noPriceMeansNoNisabAndNoGuess() {
        var input = c0; input.debtsPolicy = .none; input.goldPricePerGramMinor = nil
        #expect(ZakatEngine.assess(input, now: now).outcome == .askGoldPrice)
    }

    @Test func dueNowDeductsOnlyWhatFellDue() {
        var input = c0; input.debtsPolicy = .dueNow; input.dueNowMinor = 680_000
        // (12850000 − 680000) × 2.5% = 304250.
        #expect(ZakatEngine.assess(input, now: now).outcome == .due(amountMinor: 304_250))
    }

    @Test func excludedAccountsAndOtherAssets() {
        var input = c0; input.debtsPolicy = .none
        input.accounts[1].include = false; input.otherAssetsMinor = 1_000_000
        // (9000000 + 1000000) × 2.5% = 250000.
        #expect(ZakatEngine.assess(input, now: now).outcome == .due(amountMinor: 250_000))
    }
}
