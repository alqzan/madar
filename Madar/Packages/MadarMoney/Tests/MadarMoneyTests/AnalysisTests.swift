import Testing
@testable import MadarMoney

/// Expected values are worked by hand from the rules in AnalysisEngine's documentation (M5-V14), not read from its output.
struct AnalysisTests {
    @Test func percentChangeRoundsHalfAwayFromZeroAndRefusesAnEmptyBase() {
        // 870 against 1,000: (870 − 1000) × 100 ÷ 1000 = −13 exactly.
        #expect(AnalysisEngine.percentChange(currentMinor: 87_000, previousMinor: 100_000) == -13)
        // 1,005 against 1,000 = +0.5 → +1; 995 against 1,000 = −0.5 → −1 (away from zero, not toward it).
        #expect(AnalysisEngine.percentChange(currentMinor: 100_500, previousMinor: 100_000) == 1)
        #expect(AnalysisEngine.percentChange(currentMinor: 99_500, previousMinor: 100_000) == -1)
        // 1,440 against 2,057: −617 × 100 ÷ 2057 = −29.99… → −30.
        #expect(AnalysisEngine.percentChange(currentMinor: 144_000, previousMinor: 205_700) == -30)
        // 1,004 against 1,000 = +0.4 → 0, a real «no change»; 996 → −0.4 → 0.
        #expect(AnalysisEngine.percentChange(currentMinor: 100_400, previousMinor: 100_000) == 0)
        #expect(AnalysisEngine.percentChange(currentMinor: 99_600, previousMinor: 100_000) == 0)
        // Nothing spent before: no comparison, never «٠٪» and never infinity.
        #expect(AnalysisEngine.percentChange(currentMinor: 50_000, previousMinor: 0) == nil)
    }

    @Test func limitSharesFollowTheExpectedTodayRuleAndAddUpToTheLimit() {
        // Limit 3,000 over 31 days. Days 1–7: 300000 × 7 ÷ 31 = 67,741 (truncated).
        #expect(AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 31, fromDay: 1, throughDay: 7) == 67_741)
        // Days 8–14: 300000 × 14 ÷ 31 = 135,483; minus 67,741 = 67,742.
        #expect(AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 31, fromDay: 8, throughDay: 14) == 67_742)
        // The whole cycle is the limit, to the halala.
        #expect(AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 31, fromDay: 1, throughDay: 31) == 300_000)
        // Split anywhere, the parts still add up: 1–10 + 11–31.
        let a = AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 31, fromDay: 1, throughDay: 10)
        let b = AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 31, fromDay: 11, throughDay: 31)
        #expect(a == 96_774); #expect(a + b == 300_000)
        // A cycle running past its expected end: the extra days carry nothing (30-day limit, days 29–33 = days 29–30 only).
        // 300000 × 30 ÷ 30 − 300000 × 28 ÷ 30 = 300000 − 280000 = 20,000.
        #expect(AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 30, fromDay: 29, throughDay: 33) == 20_000)
        #expect(AnalysisEngine.limitShare(limitMinor: 300_000, cycleLengthDays: 30, fromDay: 31, throughDay: 33) == 0)
        // A fixed zero limit stays zero (L05).
        #expect(AnalysisEngine.limitShare(limitMinor: 0, cycleLengthDays: 30, fromDay: 1, throughDay: 7) == 0)
    }

    @Test func paceNeedsThreeKnownDaysAndProjectsOnlyWhileThePeriodRuns() {
        // Two days are not a trend.
        #expect(AnalysisEngine.pace(spentMinor: 50_000, allowanceMinor: 80_000, knownDays: 2, remainingDays: 28) == nil)
        // 16 known days, 6,240 spent of 6,400 dailies, 14 days to go.
        // Average spent 624000 ÷ 16 = 390; average daily 640000 ÷ 16 = 400.
        // Left now 160; at this pace 160 × 30 ÷ 16 = 300.
        let running = AnalysisEngine.pace(spentMinor: 624_000, allowanceMinor: 640_000, knownDays: 16, remainingDays: 14)
        #expect(running == .init(averageSpentMinor: 39_000, averageDailyMinor: 40_000, projectedLeftMinor: 30_000))
        // Over the line: −1,000 over 10 days with 20 to go → −1000 × 30 ÷ 10 = −3,000 (kept signed, L02).
        let over = AnalysisEngine.pace(spentMinor: 500_000, allowanceMinor: 400_000, knownDays: 10, remainingDays: 20)
        #expect(over?.projectedLeftMinor == -300_000); #expect(over?.averageSpentMinor == 50_000)
        // The average rounds to the nearest halala: 100,001 ÷ 3 = 33,333.67 → 33,334.
        #expect(AnalysisEngine.pace(spentMinor: 100_001, allowanceMinor: 120_000, knownDays: 3, remainingDays: 0)?.averageSpentMinor == 33_334)
        // A finished period has no projection.
        #expect(AnalysisEngine.pace(spentMinor: 100_001, allowanceMinor: 120_000, knownDays: 3, remainingDays: 0)?.projectedLeftMinor == nil)
    }

    @Test func roundedDivisionIsSymmetricAroundZero() {
        #expect(AnalysisEngine.roundedDivision(5, by: 2) == 3)
        #expect(AnalysisEngine.roundedDivision(-5, by: 2) == -3)
        #expect(AnalysisEngine.roundedDivision(7, by: 3) == 2)
        #expect(AnalysisEngine.roundedDivision(-7, by: 3) == -2)
        #expect(AnalysisEngine.roundedDivision(0, by: 9) == 0)
    }
}
