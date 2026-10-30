import Foundation
import Testing
@testable import MadarCore

/// Owner, 30 Oct: expected values are worked by hand from the rules in `ReadingPace`, not read off the code.
@Suite("Reading pace and chapters")
struct ReadingPaceTests {
    private func day(_ text: String) throws -> GregorianDay { try GregorianDay(text) }

    @Test("Seconds per page needs three counted sessions and ten pages")
    func pace() throws {
        let d = try day("2026-10-28")
        let three = [ReadingPaceSample(day: d, seconds: 900, pages: 10), .init(day: d, seconds: 900, pages: 10), .init(day: d, seconds: 900, pages: 10)]
        #expect(ReadingPace.secondsPerPage(three) == 90)                    // 2700 s over 30 pages
        #expect(ReadingPace.secondsPerPage(Array(three.prefix(2))) == nil)  // two sessions are not a pace
        let thin = [ReadingPaceSample(day: d, seconds: 900, pages: 3), .init(day: d, seconds: 900, pages: 3), .init(day: d, seconds: 900, pages: 3)]
        #expect(ReadingPace.secondsPerPage(thin) == nil)                    // nine pages
        // A 59-second session never counts, so the other two fall below three.
        #expect(ReadingPace.secondsPerPage([three[0], three[1], .init(day: d, seconds: 59, pages: 10)]) == nil)
    }

    @Test("Pages become minutes rounded up, minutes become pages rounded down")
    func conversions() {
        #expect(ReadingPace.minutes(forPages: 10, secondsPerPage: 90) == 15)
        #expect(ReadingPace.minutes(forPages: 7, secondsPerPage: 90) == 11)   // 10.5
        #expect(ReadingPace.minutes(forPages: 1, secondsPerPage: 10) == 1)    // never zero
        #expect(ReadingPace.minutes(forPages: 0, secondsPerPage: 90) == nil)
        #expect(ReadingPace.pages(forMinutes: 15, secondsPerPage: 90) == 10)
        #expect(ReadingPace.pages(forMinutes: 20, secondsPerPage: 90) == 13)  // 13.33
        #expect(ReadingPace.pages(forMinutes: 1, secondsPerPage: 600) == 1)   // never zero
    }

    @Test("Days to finish uses the last fourteen days, rest days included")
    func finish() throws {
        let today = try day("2026-10-30")
        let recent = try ["2026-10-28", "2026-10-29", "2026-10-30"].map { ReadingPaceSample(day: try day($0), seconds: 1200, pages: 20) }
        #expect(ReadingPace.daysToFinish(remainingPages: 100, samples: recent, today: today) == 24)  // 60 pages / 14 days = 4.29 a day; 100 / 4.29 = 23.3
        #expect(ReadingPace.daysToFinish(remainingPages: 0, samples: recent, today: today) == 0)
        #expect(ReadingPace.daysToFinish(remainingPages: 100, samples: Array(recent.prefix(2)), today: today) == nil)   // two days of reading
        let old = [ReadingPaceSample(day: try day("2026-10-10"), seconds: 1200, pages: 20)]                              // 20 days ago: outside the window
        #expect(ReadingPace.daysToFinish(remainingPages: 100, samples: Array(recent.prefix(2)) + old, today: today) == nil)
    }

    @Test("Chapters come from the outline and the pages read")
    func chapters() {
        let three = Data(#"[{"title":"أ"},{"title":"ب"},{"title":"ج"}]"#.utf8)
        #expect(ReadingChapters.chapterCount(tocJSON: three) == 3)
        #expect(ReadingChapters.chapterCount(tocJSON: Data(#"[{"title":"أ"}]"#.utf8)) == nil)   // one entry is not a structure
        #expect(ReadingChapters.chapterCount(tocJSON: Data("not json".utf8)) == nil)
        #expect(ReadingChapters.chapterCount(tocJSON: nil) == nil)
        let fraction = ReadingChapters.chapters(pagesRead: 30, bookPages: 300, chapterCount: 12)
        #expect(fraction != nil && abs(fraction! - 1.2) < 0.000_001)
        #expect(ReadingChapters.chapters(pagesRead: 30, bookPages: nil, chapterCount: 12) == nil)
    }
}
