import Testing
@testable import MadarMoney

struct CardPlanningTests {
    @Test func f07CashbackAndUtilisationAreMinorUnitEstimates() {
        // Canonical scenario: 2,000 SAR purchase, rates 0.5% and 1.5% → 10 / 30 SAR.
        #expect(CardPlanning.cashbackEstimate(purchaseMinor: 200_000, rateBp: 50) == 1_000)
        #expect(CardPlanning.cashbackEstimate(purchaseMinor: 200_000, rateBp: 150) == 3_000)
        // C0 card: 6,800 billed + 1,800 unbilled; 20,000 test limit → 43%.
        #expect(CardPlanning.utilisationBp(owedMinor: 680_000 + 180_000, limitMinor: 2_000_000) == 4_300)
        #expect(CardPlanning.cashbackEstimate(purchaseMinor: 1, rateBp: 5_000) == 1, "Half a minor unit rounds away from zero")
    }
    @Test func interestScenarioIsExplicitAndUnknownRatesStayUnknown() {
        // F07 requires an estimate, never a promised bank charge. 1,000 SAR × 24% × 30/365
        // = 19.726027… SAR → 1,973 minor units, by hand.
        #expect(CardPlanning.interestEstimate(unpaidMinor: 100_000, annualRateBp: 2_400, days: 30) == 1_973)
        #expect(CardPlanning.interestEstimate(unpaidMinor: 100_000, annualRateBp: nil, days: 30) == nil)
        #expect(CardPlanning.interestEstimate(unpaidMinor: 0, annualRateBp: 2_400, days: 30) == 0)
        #expect(CardPlanning.utilisationBp(owedMinor: 100, limitMinor: 0) == nil)
    }
    @Test func knownCashDueDatesDoNotInventSalary() {
        // C0 cash less its 6,800 statement, 2,850 loan and 410 bills, in date order.
        #expect(CardPlanning.cashAfter(availableMinor: 12_850_000, dueMinor: [680_000, 285_000, 41_000]) == [12_170_000, 11_885_000, 11_844_000])
        #expect(CardPlanning.cashAfter(availableMinor: 100, dueMinor: [60, 80]) == [40, -40])
        #expect(CardPlanning.cashAfter(availableMinor: .min, dueMinor: [1]) == nil)
        #expect(CardPlanning.rateAmount(.max, numerator: .max, denominator: 1) == nil)
    }
}
