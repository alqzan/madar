import Testing
@testable import MadarMoney

struct AmountBoundaryTests {
    @Test func currencyInputIsExactAndRejectsOverflowInsteadOfCrashing() throws {
        #expect(MoneyAmountInput.minor("12.34", exponent: 2) == 1234)
        #expect(MoneyAmountInput.minor("1.250", exponent: 3) == 1250)
        #expect(MoneyAmountInput.minor("1500", exponent: 0) == 1500)
        // Thousands groups typed on either keyboard are read as a whole amount; a lone comma group is not guessed.
        #expect(MoneyAmountInput.minor("1,500", exponent: 0) == 1500)
        #expect(MoneyAmountInput.minor("١٬٥٠٠", exponent: 0) == 1500)
        #expect(MoneyAmountInput.minor("1,500.25", exponent: 2) == 150025)
        #expect(MoneyAmountInput.minor("1,5", exponent: 2) == nil)
        #expect(MoneyAmountInput.minor("12,34", exponent: 2) == nil)
        #expect(MoneyAmountInput.minor("1,2345", exponent: 0) == nil)
        #expect(MoneyAmountInput.minor("1.251", exponent: 2) == nil)
        #expect(MoneyAmountInput.minor("99999999999999999999", exponent: 2) == nil)
        #expect(MoneyAmountInput.minor("999999999999999999", exponent: 2) == nil)
        let parsed = BankMessageParser.parse("شراء 999999999999999999 SAR", timeZone: .gmt)
        #expect(parsed.amountMinor == nil)
        #expect(throws: FXError.amountOverflow) { try FX.homeAmount(amountMinor: Int.max, currency: "USD", rate: "3.75") }
    }
    @Test func splitUsesFullWidthIntermediateAndKeepsLastHalala() throws {
        // 9e12 minor units / 3 remains valid even though multiplying by a 3e12 weight exceeds Int.
        let total = 9_000_000_000_001
        #expect(AllocationEngine.distribute(total, weights: [3_000_000_000_000, 3_000_000_000_000, 3_000_000_000_000]) == [3_000_000_000_000, 3_000_000_000_000, 3_000_000_000_001])
    }
}
