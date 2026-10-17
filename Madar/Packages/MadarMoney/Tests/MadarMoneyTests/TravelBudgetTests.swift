import Foundation
import Testing
@testable import MadarMoney

struct TravelBudgetTests {
    @Test func dailyPlanPreservesRemainderAndDates() {
        // 5000 across seven days: six × 714.28 plus the last 714.32, exactly 5000.
        #expect(TravelBudget.dailyMinor(targetMinor: 500_000, durationDays: 7, day: 1) == 71_428)
        #expect(TravelBudget.dailyMinor(targetMinor: 500_000, durationDays: 7, day: 7) == 71_432)
        #expect(TravelBudget.dailyMinor(targetMinor: 500_000, durationDays: 7, day: 8) == nil)
        #expect(TravelBudget.dailyMinor(targetMinor: 1, durationDays: 0, day: 1) == nil)
    }
    @Test func currencyExponentsAndDisplayConversionUsePinnedFacts() throws {
        #expect(CurrencyExponents.specified.exponent("TRY") == 2)
        #expect(CurrencyExponents.specified.exponent("JPY") == 0)
        #expect(CurrencyExponents.specified.exponent("KWD") == 3)
        #expect(CurrencyExponents.specified.exponent("CLF") == 4)
        #expect(CurrencyExponents.specified.exponent("ZZZ") == nil)
        #expect(try TravelBudget.foreignAmount(homeMinor: 46_28, currency: "USD", rate: "3.75") == 12_34)
        #expect(try TravelBudget.foreignAmount(homeMinor: 37_50, currency: "JPY", rate: "0.025") == 1500)
        #expect(try TravelBudget.foreignAmount(homeMinor: 15_25, currency: "KWD", rate: "12.2") == 1250)
        #expect(try FX.homeAmount(amountMinor: 12_34, currency: "USD", rate: "3.75") == 46_28)
    }
    @Test func stampsTrackTheActualRemainderWithoutDecimalTruncation() {
        #expect(TravelBudget.stampsRemaining(dailyMinor: 71428, spentMinor: 23100) == 6)
        #expect(TravelBudget.stampsRemaining(dailyMinor: 40000, spentMinor: 20000) == 5)
        #expect(TravelBudget.stampsRemaining(dailyMinor: 0, spentMinor: 10) == 0)
        #expect(TravelBudget.stampsRemaining(dailyMinor: 40000, spentMinor: 50000) == 0)
        #expect(TravelBudget.stampsRemaining(dailyMinor: Int.max, spentMinor: 0) == 10)
        #expect(BankMessageParser.parse("شراء 770.00 TRY\nلدى: مقهى", timeZone: TimeZone(identifier: "Asia/Riyadh")!).amountMinor == 77000)
    }
    @Test func rateInputAcceptsArabicDigitsAndRejectsAmbiguity() {
        #expect(TravelBudget.canonicalRate(" ٠٫١٢٣٤٥٦٧٨٩٠١٢ ") == "0.123456789012")
        #expect(TravelBudget.canonicalRate("۰٫۲۵") == "0.25")
        for raw in ["0", "-1", "1,25", "1٫2٫3", "0.1234567890123", "1e2", ""] { #expect(TravelBudget.canonicalRate(raw) == nil) }
    }
}
