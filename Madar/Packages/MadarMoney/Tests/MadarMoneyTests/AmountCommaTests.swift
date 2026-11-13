import Testing
@testable import MadarMoney

/// Review T14 item 13 and quick win 23: values by hand, exponent 2 (12.50 = 1250 minor units).
struct AmountCommaTests {
    @Test func decimalPointAndArabicSeparator() {
        #expect(MoneyAmountInput.minor("12.50", exponent: 2) == 1250)
        #expect(MoneyAmountInput.minor("١٢٫٥٠", exponent: 2) == 1250)
    }
    @Test func thousandsGroupIsAccepted() {
        #expect(MoneyAmountInput.minor("1,500", exponent: 2) == 150_000)
    }
    @Test func improperGroupIsRefusedNotMisread() {
        #expect(MoneyAmountInput.minor("1,5", exponent: 2) == nil)
    }
}
