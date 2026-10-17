import Foundation
import Testing
@testable import MadarCore
struct SalaryRecurrenceTests {
    @Test func freeFirstDateAndEarlySalaryKeepTheOwnersAnchor() throws {
        let rent = try #require(SalaryRecurrence(every: 6, unit: .month, first: try .init("2027-02-18")))
        #expect(rent.preview(from: try .init("2026-10-16")) == [try .init("2027-02-18"), try .init("2027-08-18"), try .init("2028-02-18")])
        #expect(rent.expectedEnd(after: try .init("2026-10-16")) == (try .init("2027-02-18")))
        #expect(rent.expectedEnd(after: try .init("2027-02-16")) == (try .init("2027-08-18")))
        let month = try #require(SalaryRecurrence(every: 1, unit: .month, first: try .init("2026-01-31")))
        #expect(month.expectedEnd(after: try .init("2026-01-28")) == (try .init("2026-02-28")))
        #expect(month.occurrence(2) == (try .init("2026-03-31")))
    }
    @Test func hijriMonthsKeepTheOriginalDay() throws {
        var c = Calendar(identifier: .islamicUmmAlQura); c.timeZone = .gmt
        let first = GregorianDay.containing(try #require(c.date(from: .init(year: 1448, month: 1, day: 10))), in: .gmt)
        let p = try #require(SalaryRecurrence(every: 2, unit: .month, first: first, hijri: true))
        let next = try #require(p.occurrence(1)), parts = c.dateComponents([.year,.month,.day], from: next.date(in: .gmt))
        #expect(parts.year == 1448); #expect(parts.month == 3); #expect(parts.day == 10)
    }
}
