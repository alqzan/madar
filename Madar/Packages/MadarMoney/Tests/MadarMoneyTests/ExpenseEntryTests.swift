import Testing
@testable import MadarMoney

/// M5-V17. Expected values are worked by hand from §7.5 (F02 allocations, L12 remainder, RM2 headline, the 30% card
/// line, three dailies for a big expense), never read from the engine's output.
struct ExpenseEntryTests {
    @Test func arabicDecimalKeyboardKeepsTheHalala() {
        #expect(MoneyAmountInput.minor("٤٢٫٠١", exponent: 2) == 4201)
        #expect(MoneyAmountInput.minor("١٢٣٤", exponent: 0) == 1234)
        #expect(MoneyAmountInput.minor("١٫٢٥٠", exponent: 3) == 1250)
        #expect(MoneyAmountInput.minor("٤٢٫٠١٥", exponent: 2) == nil)
        #expect(MoneyAmountInput.minor("-٤٢", exponent: 2) == nil)
    }
    @Test func splitPutsTheEnvelopeFloorFirstAndTheRemainderOnTheDaily() {
        // 42.00 at 25%: 4200 × 25 ÷ 100 = 1050 from the envelope, 3150 from «يومك».
        #expect(ExpenseEntry.split(chargeMinor: 4_200, share: .quarter) == .init(dailyMinor: 3_150, envelopeMinor: 1_050))
        // 42.01 at 25%: ⌊4201 × 25 ÷ 100⌋ = 1050; the halala left over lands on «يومك» (L12): 3151.
        #expect(ExpenseEntry.split(chargeMinor: 4_201, share: .quarter) == .init(dailyMinor: 3_151, envelopeMinor: 1_050))
        // 0.03 at 50%: ⌊3 × 50 ÷ 100⌋ = 1 and 2.
        #expect(ExpenseEntry.split(chargeMinor: 3, share: .half) == .init(dailyMinor: 2, envelopeMinor: 1))
        #expect(ExpenseEntry.split(chargeMinor: 4_200, share: .daily) == .init(dailyMinor: 4_200, envelopeMinor: 0))
        #expect(ExpenseEntry.split(chargeMinor: 4_200, share: .envelope) == .init(dailyMinor: 0, envelopeMinor: 4_200))
        // Cash already counted when withdrawn: no charge, nothing to split.
        #expect(ExpenseEntry.split(chargeMinor: 0, share: .half) == .init(dailyMinor: 0, envelopeMinor: 0))
    }

    @Test func sourcesAreEmptyForTheDailyAndAddUpOtherwise() {
        #expect(ExpenseEntry.sources(.init(dailyMinor: 4_200, envelopeMinor: 0), envelopeID: "e").isEmpty)
        let quarter = ExpenseEntry.sources(.init(dailyMinor: 3_151, envelopeMinor: 1_050), envelopeID: "e")
        #expect(quarter.map(\.0) == [.envelope("e"), .daily]); #expect(quarter.map(\.1) == [1_050, 3_151])
        let all = ExpenseEntry.sources(.init(dailyMinor: 0, envelopeMinor: 4_200), envelopeID: "e")
        #expect(all.map(\.0) == [.envelope("e")]); #expect(all.map(\.1) == [4_200])
    }

    /// A 30-day cycle at 400 a day, day 6, spent 120 on day 6 and 400 on each of days 1–5 except day 2 (200):
    /// accrued 6 × 400 = 2400; spent 400 + 200 + 400 + 400 + 400 + 120 = 1920; «لك الآن» 480.
    static let input = CycleInput(expectedLengthDays: 30, policies: [.init(mode: .fixed(allowanceMinor: 40_000))])
    static let spent = [1: 40_000, 2: 20_000, 3: 40_000, 4: 40_000, 5: 40_000, 6: 12_000]

    @Test func headlineAfterAddsTheDailyPartToItsDay() {
        // 42 today from «يومك»: today 120 + 42 = 162 of 400, «لك الآن» 480 − 42 = 438.
        let today = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 6, dailyChargeMinor: 4_200)
        #expect(today.todaySpentMinor == 16_200); #expect(today.todayAllowanceMinor == 40_000); #expect(today.availableNowMinor == 43_800)
        #expect(today.overTodayMinor == nil); #expect(today.overCycleMinor == nil)
        // Yesterday's coffee: «اليوم» stays 120, «لك الآن» still drops by 42.
        let yesterday = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 5, dailyChargeMinor: 4_200)
        #expect(yesterday.todaySpentMinor == 12_000); #expect(yesterday.availableNowMinor == 43_800)
        // 300 today passes the day (420 − 400 = 20 over) but not the cycle (480 − 300 = 180 left): two different words (RM2).
        let over = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 6, dailyChargeMinor: 30_000)
        #expect(over.overTodayMinor == 2_000); #expect(over.overCycleMinor == nil); #expect(over.availableNowMinor == 18_000)
        // 600 today: 720 − 400 = 320 over the day and 480 − 600 = −120, the cycle is 120 over.
        let cycle = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 6, dailyChargeMinor: 60_000)
        #expect(cycle.overTodayMinor == 32_000); #expect(cycle.overCycleMinor == 12_000)
        // Cash under «السحب يُخصم من يومك»: no charge, nothing moves.
        let cash = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 6, dailyChargeMinor: 0)
        #expect(cash.todaySpentMinor == 12_000); #expect(cash.availableNowMinor == 48_000)
        // A day before the cycle began changes neither number.
        let outside = ExpenseEntry.headlineAfter(elapsedDays: 6, Self.input, dailySpentMinor: Self.spent, expenseDay: 0, dailyChargeMinor: 4_200)
        #expect(outside.availableNowMinor == 48_000)
    }

    @Test func dailyPartNamesAnAmountTheUserCanPicture() {
        // 42 of 400 = 105 ‰ → about a tenth (the canonical's «٠٫١ يومية»).
        #expect(ExpenseEntry.dailyPart(amountMinor: 4_200, dailyMinor: 40_000) == .about(.tenth))
        // 20 of 400 = 50 ‰ → less than a tenth.
        #expect(ExpenseEntry.dailyPart(amountMinor: 2_000, dailyMinor: 40_000) == .lessThanTenth)
        // 100 of 400 = 250 ‰ → a quarter; 200 = 500 ‰ → a half; 400 = the whole day.
        #expect(ExpenseEntry.dailyPart(amountMinor: 10_000, dailyMinor: 40_000) == .about(.quarter))
        #expect(ExpenseEntry.dailyPart(amountMinor: 20_000, dailyMinor: 40_000) == .about(.half))
        #expect(ExpenseEntry.dailyPart(amountMinor: 40_000, dailyMinor: 40_000) == .about(.whole))
        // 140 of 400 = 350 ‰ → a third; 290 = 725 ‰ → three quarters.
        #expect(ExpenseEntry.dailyPart(amountMinor: 14_000, dailyMinor: 40_000) == .about(.third))
        #expect(ExpenseEntry.dailyPart(amountMinor: 29_000, dailyMinor: 40_000) == .about(.threeQuarters))
        // 820 = 2050 ‰ → about two dailies; 1,000 = 2500 ‰ → rounds half up to three.
        #expect(ExpenseEntry.dailyPart(amountMinor: 82_000, dailyMinor: 40_000) == .dailies(2))
        #expect(ExpenseEntry.dailyPart(amountMinor: 100_000, dailyMinor: 40_000) == .dailies(3))
        // No «يومك» yet: nothing is said.
        #expect(ExpenseEntry.dailyPart(amountMinor: 4_200, dailyMinor: 0) == nil)
        #expect(ExpenseEntry.dailyPart(amountMinor: 4_200, dailyMinor: nil) == nil)
    }

    @Test func bigExpenseStartsAtThreeDailies() {
        #expect(!ExpenseEntry.isBig(amountMinor: 119_999, dailyMinor: 40_000))
        #expect(ExpenseEntry.isBig(amountMinor: 120_000, dailyMinor: 40_000))
        #expect(!ExpenseEntry.isBig(amountMinor: 120_000, dailyMinor: nil))
    }

    @Test func creditCardAfterTheLimitAndThirtyPercent() {
        // Owes 5,000 of a 20,000 limit, buys 1,000: 6,000 = 30% exactly, not above it.
        let at = ExpenseEntry.creditCardAfter(owedMinor: 500_000, purchaseMinor: 100_000, limitMinor: 2_000_000)
        #expect(at.owedMinor == 600_000); #expect(at.utilisationBp == 3_000); #expect(!at.aboveThirtyPercent); #expect(!at.overLimit)
        // One riyal more passes 30%.
        #expect(ExpenseEntry.creditCardAfter(owedMinor: 500_000, purchaseMinor: 100_100, limitMinor: 2_000_000).aboveThirtyPercent)
        // 19,950 + 100 = 20,050 passes the 20,000 limit.
        #expect(ExpenseEntry.creditCardAfter(owedMinor: 1_995_000, purchaseMinor: 10_000, limitMinor: 2_000_000).overLimit)
        // Unknown limit: owed only, no share and no warning.
        let unknown = ExpenseEntry.creditCardAfter(owedMinor: 0, purchaseMinor: 4_200, limitMinor: nil)
        #expect(unknown.owedMinor == 4_200); #expect(unknown.utilisationBp == nil); #expect(!unknown.overLimit)
    }

    @Test func riyalsFollowArabicCountedNouns() {
        let w: (Int) -> String = { String($0) }, f: (Int) -> String = { "\($0 / 100).\($0 % 100)" }
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 100, digits: w, fractional: f) == "ريالًا واحدًا")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 200, digits: w, fractional: f) == "ريالين")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 500, digits: w, fractional: f) == "5 ريالات")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 1_000, digits: w, fractional: f) == "10 ريالات")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 4_200, digits: w, fractional: f) == "42 ريالًا")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 10_000, digits: w, fractional: f) == "100 ريال")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 10_500, digits: w, fractional: f) == "105 ريالات")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 11_200, digits: w, fractional: f) == "112 ريالًا")
        #expect(ExpenseEntry.riyalsSpent(amountMinor: 1_850, digits: w, fractional: f) == "18.50 ريال")
    }
}
