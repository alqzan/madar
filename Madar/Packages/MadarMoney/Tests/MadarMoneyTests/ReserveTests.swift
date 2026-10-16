import Testing
@testable import MadarMoney

struct ReserveTests {
    @Test func c0DailiesAndCoverageHaveDifferentMeaningsUnderRM9() throws {
        // Reserve 100,000 / daily 400 = 250 squares. Per cycle: 30×400 + loan 2,850 + bills 410.
        // floor(10,000,000×30 / 1,526,000) = 196 days; after taking half, 98 days and 125 squares.
        let preview = try ReserveEngine.preview(balanceMinor: 10000000, spendMinor: 5000000, dailyMinor: 40000, cycleLengthDays: 30, obligationsPerCycleMinor: 326000)
        #expect(preview.before.wholeDailies == 250); #expect(preview.before.runway?.days == 196)
        #expect(preview.after.wholeDailies == 125); #expect(preview.after.runway?.days == 98)
        #expect(preview.before.balanceMinor == preview.after.balanceMinor + preview.spentMinor)
    }
    @Test func zeroUnknownAndPartialDailyStayDistinct() throws {
        let unknown = ReserveEngine.read(balanceMinor: 10000, dailyMinor: nil, cycleLengthDays: 30, obligationsPerCycleMinor: 0)
        let zero = ReserveEngine.read(balanceMinor: 10000, dailyMinor: 0, cycleLengthDays: 30, obligationsPerCycleMinor: 0)
        #expect(unknown.dailyMinor == nil); #expect(zero.dailyMinor == 0)
        #expect(unknown.runway == nil); #expect(zero.runway == nil)
        let partial = ReserveEngine.read(balanceMinor: 10001, dailyMinor: 4000, cycleLengthDays: 30, obligationsPerCycleMinor: 0)
        #expect(partial.wholeDailies == 2); #expect(partial.partialDailyMinor == 2001)
        #expect(throws: ReserveEngine.Error.invalidSpend) { try ReserveEngine.preview(balanceMinor: 100, spendMinor: 101, dailyMinor: 10, cycleLengthDays: 30, obligationsPerCycleMinor: 0) }
    }
}
