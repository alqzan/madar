import Foundation

/// Owner, 30 Oct 2026: the reading goal can be minutes, pages or chapters, and Madar says what a pages or chapters goal
/// usually costs in minutes, and when the book in hand is likely to end, from the reader's own past sessions.
/// Everything here is derived from `ReadingSession` rows each time; nothing is stored.
public struct ReadingPaceSample: Equatable, Sendable {
    public let day: GregorianDay
    public let seconds: Int
    public let pages: Int
    public init(day: GregorianDay, seconds: Int, pages: Int) { self.day = day; self.seconds = seconds; self.pages = pages }
}

public enum ReadingPace {
    /// A pace needs enough reading to be a pace: three sessions and ten pages, and only sessions that counted both time and pages.
    public static let minimumSamples = 3, minimumPages = 10
    /// «بهذه الوتيرة» looks at the last two weeks and needs three different days with reading in them.
    public static let windowDays = 14, minimumReadingDays = 3
    /// An estimate is shown only for a goal this size or smaller: past a day's reading it is no longer a guess about today.
    public static let maximumEstimatedMinutes = 600

    private static func dayGap(from a: GregorianDay, to b: GregorianDay) -> Int {
        Int((b.date(in: .gmt).timeIntervalSince(a.date(in: .gmt)) / 86_400).rounded())
    }

    public static func secondsPerPage(_ samples: [ReadingPaceSample]) -> Double? {
        let counted = samples.filter { $0.seconds >= 60 && $0.pages > 0 }
        let pages = counted.reduce(0) { $0 + $1.pages }
        guard counted.count >= minimumSamples, pages >= minimumPages else { return nil }
        return Double(counted.reduce(0) { $0 + $1.seconds }) / Double(pages)
    }

    /// Whole minutes, rounded up, at least one: «١٠ صفحات» at 90 seconds a page is 15 minutes.
    public static func minutes(forPages pages: Int, secondsPerPage: Double) -> Int? {
        guard pages > 0, secondsPerPage.isFinite, secondsPerPage > 0 else { return nil }
        let minutes = Int((Double(pages) * secondsPerPage / 60).rounded(.up))
        return minutes <= maximumEstimatedMinutes ? max(1, minutes) : nil
    }

    /// The reverse: how many pages a minutes goal usually covers, rounded down, at least one.
    public static func pages(forMinutes minutes: Int, secondsPerPage: Double) -> Int? {
        guard minutes > 0, secondsPerPage.isFinite, secondsPerPage > 0 else { return nil }
        return max(1, Int((Double(minutes) * 60 / secondsPerPage).rounded(.down)))
    }

    /// Calendar days to finish `remainingPages` at the pace of the last `windowDays` days (rest days included, because the
    /// reader rests too). Nil when the reading is too thin to promise anything.
    public static func daysToFinish(remainingPages: Int, samples: [ReadingPaceSample], today: GregorianDay) -> Int? {
        guard remainingPages > 0 else { return 0 }
        let recent = samples.filter { $0.pages > 0 && dayGap(from: $0.day, to: today) >= 0 && dayGap(from: $0.day, to: today) < windowDays }
        guard Set(recent.map(\.day)).count >= minimumReadingDays else { return nil }
        let pages = recent.reduce(0) { $0 + $1.pages }
        guard pages > 0 else { return nil }
        let perDay = Double(pages) / Double(windowDays)
        return Int((Double(remainingPages) / perDay).rounded(.up))
    }
}

/// «فصل»: a chapter is counted from the pages read and the book's own outline, since a session ends mid-chapter as often as not.
public enum ReadingChapters {
    /// The number of top-level entries in a book's outline (`Book.tocJSON`), when it has at least two. Outlines that record
    /// nesting (`depth`) count only the shallowest level, so a chapter's sub-sections are not chapters; older outlines, which
    /// do not, count every entry.
    public static func chapterCount(tocJSON: Data?) -> Int? {
        guard let tocJSON, let object = try? JSONSerialization.jsonObject(with: tocJSON) as? [Any], object.count >= 2 else { return nil }
        let depths = object.compactMap { ($0 as? [String: Any])?["depth"] as? Int }
        let count = depths.count == object.count ? depths.filter { $0 == (depths.min() ?? 0) }.count : object.count
        return count >= 2 ? count : nil
    }

    /// The share of the book's chapters that `pagesRead` pages make: 30 of 300 pages in a 12-chapter book is 1.2 chapters.
    public static func chapters(pagesRead: Int, bookPages: Int?, chapterCount: Int?) -> Double? {
        guard pagesRead > 0, let bookPages, bookPages > 0, let chapterCount, chapterCount > 0 else { return nil }
        return Double(pagesRead) * Double(chapterCount) / Double(bookPages)
    }
}
