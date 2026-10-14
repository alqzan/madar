import Foundation
import MadarCore

/// Only completed memorized faces enter this value. Partial ranges remain in recent review separately.
public struct QuranPlanningPage: Equatable, Sendable {
    public let page: Int
    public let lastReviewed: GregorianDay
    public let nextDue: GregorianDay
    public let grade: QuranReviewRating
    public let strength: Int
    public let isDue: Bool
    public let isFar: Bool

    public init(page: Int, lastReviewed: GregorianDay, nextDue: GregorianDay,
                grade: QuranReviewRating = .good, today: GregorianDay) throws {
        guard (1...604).contains(page) else { throw QuranPlanError.invalidPages }
        self.page = page; self.lastReviewed = lastReviewed; self.nextDue = nextDue; self.grade = grade
        let interval = Swift.max(1, lastReviewed.distance(to: nextDue))
        let elapsed = Swift.max(0, lastReviewed.distance(to: today))
        let weight: Double = switch grade { case .mastered: 1; case .good: 0.85; case .needsMastery: 0.6 }
        strength = Int((100 * weight * pow(2, -Double(elapsed) / Double(interval) / 2)).rounded())
        isDue = nextDue <= today
        // RQ4 is the only far definition. Never use a fixed age (20/30 days).
        isFar = nextDue.distance(to: today) >= interval || strength < 50
    }

    static func weakestFirst(_ left: Self, _ right: Self) -> Bool {
        left.strength == right.strength ? left.page < right.page : left.strength < right.strength
    }
}

public struct QuranRecoveryPlan: Codable, Equatable, Sendable {
    public let startDayKey: GregorianDay
    public let days: Int
    public let pages: [Int]
    public let cancelled: Bool
    public init(startDayKey: GregorianDay, days: Int, pages: [Int], cancelled: Bool = false) throws {
        guard [5, 7, 14].contains(days) else { throw QuranPlanError.invalidRecoveryDays }
        guard pages.allSatisfy({ (1...604).contains($0) }) else { throw QuranPlanError.invalidPages }
        self.startDayKey = startDayKey; self.days = days; self.pages = pages.uniqued(); self.cancelled = cancelled
    }
    public static func starting(on day: GregorianDay, days: Int, candidates: [QuranPlanningPage]) throws -> Self {
        try Self(startDayKey: day, days: days, pages: candidates.filter(\.isFar)
            .sorted(by: QuranPlanningPage.weakestFirst).map(\.page))
    }
    /// Pass live review facts only. Rest days also serve review, so recovery uses calendar days.
    public func share(on day: GregorianDay, reviewedOn: [Int: GregorianDay]) -> [Int] {
        guard !cancelled, day >= startDayKey else { return [] }
        let atDayStart = pages.filter { page in
            guard let review = reviewedOn[page] else { return true }
            return review < startDayKey || review >= day
        }
        let completedToday = atDayStart.filter { reviewedOn[$0] == day }.count
        let remaining = atDayStart.filter { reviewedOn[$0] != day }
        let daysLeft = Swift.max(1, days - startDayKey.distance(to: day))
        let quota = (atDayStart.count + daysLeft - 1) / daysLeft
        return Array(remaining.prefix(Swift.max(0, quota - completedToday)))
    }
}

public enum QuranRecoveryEngine {
    public static func raise(on day: GregorianDay, pages: [QuranPlanningPage]) throws -> QuranDailyAllotment {
        let chosen = pages.filter(\.isFar).sorted {
            if $0.lastReviewed != $1.lastReviewed { return $0.lastReviewed < $1.lastReviewed }
            return QuranPlanningPage.weakestFirst($0, $1)
        }.prefix(5).map(\.page)
        return try QuranDailyAllotment(dayKey: day.adding(days: 1), kind: .reviewExtra,
                                      pages: chosen, origin: .raise, originDayKey: day)
    }

    /// A frozen selection (including an empty one) wins on restart. Test eligibility comes from live test grades.
    public static func testPages(on day: GregorianDay, lastTest: GregorianDay?, frozen: [Int]?,
                                 pages: [QuranPlanningPage], recent: Set<Int>, selectionIndex: Int = 0) -> [Int] {
        guard lastTest.map({ $0.distance(to: day) >= 3 }) ?? true else { return [] }
        if let frozen { return frozen }
        let older = pages.filter { !recent.contains($0.page) }
        let pool = (older.isEmpty ? pages : older).sorted {
            let l = $0.lastReviewed.distance(to: day) + ($0.grade == .needsMastery ? 5 : 0)
            let r = $1.lastReviewed.distance(to: day) + ($1.grade == .needsMastery ? 5 : 0)
            return l == r ? $0.page < $1.page : l > r
        }
        guard !pool.isEmpty else { return [] }
        let topCount = (pool.count + 2) / 3
        // The app injects a random nonnegative index and persists the result in QuranDayState.
        return [pool[Swift.max(0, selectionIndex) % topCount].page]
    }
}

public struct QuranActivityDay: Sendable {
    public let dayKey: GregorianDay
    public let kind: QuranSessionKind
    public let gradedPages: Set<Int>
    public let hifzAyahs: Set<Int>
    public let isDeleted: Bool
    public init(dayKey: GregorianDay, kind: QuranSessionKind, gradedPages: Set<Int> = [],
                hifzAyahs: Set<Int> = [], isDeleted: Bool = false) {
        self.dayKey = dayKey; self.kind = kind; self.gradedPages = gradedPages
        self.hifzAyahs = hifzAyahs; self.isDeleted = isDeleted
    }
    public var countsForStreak: Bool {
        guard !isDeleted else { return false }
        switch kind {
        case .hifz: return !hifzAyahs.isEmpty
        case .review, .free, .qiyam: return !gradedPages.isEmpty
        case .drill: return false
        }
    }
    public var countsForReviewHabit: Bool {
        !isDeleted && [.review, .free, .qiyam].contains(kind) && !gradedPages.isEmpty
    }
}

public struct QuranStudyStreak: Equatable, Sendable {
    public let days: Int
    public let inGrace: Bool
}
public struct QuranPace: Equatable, Sendable {
    public let windowStart: GregorianDay
    public let hifzDays: Int
    public let completedPages: Int
    public let pagesPerHifzDay: Double?
}
public enum QuranForecast: Equatable, Sendable { case complete, unavailable, estimated(GregorianDay) }

public enum QuranProgressEngine {
    public static let paceWindowDays = 28
    public static func streak(activities: [QuranActivityDay], through day: GregorianDay,
                              restDay: QuranRestDay = .friday) -> QuranStudyStreak {
        let active = Set(activities.filter { $0.countsForStreak && $0.dayKey <= day }.map(\.dayKey))
        guard let first = active.min() else { return QuranStudyStreak(days: 0, inGrace: false) }
        var cursor = first, count = 0, missed = 0
        while cursor <= day {
            if !restDay.contains(cursor) {
                if active.contains(cursor) { count += 1; missed = 0 }
                else if cursor < day { // Today's unfinished target is still open.
                    missed += 1
                    if missed >= 2 { count = 0 }
                }
            }
            cursor = cursor.adding(days: 1)
        }
        return QuranStudyStreak(days: count, inGrace: count > 0 && missed == 1)
    }

    public static func pace(activities: [QuranActivityDay], completedOn: [Int: GregorianDay],
                            through day: GregorianDay, restDay: QuranRestDay = .friday) -> QuranPace {
        let liveHifz = activities.filter { !$0.isDeleted && $0.kind == .hifz && $0.dayKey <= day && !$0.hifzAyahs.isEmpty }
        let fullStart = day.adding(days: -(paceWindowDays - 1))
        let start = Swift.max(fullStart, liveHifz.map(\.dayKey).min() ?? fullStart)
        var cursor = start, hifzDays = 0
        while cursor <= day {
            if !restDay.contains(cursor) { hifzDays += 1 }
            cursor = cursor.adding(days: 1)
        }
        let completed = completedOn.filter { (1...604).contains($0.key) && $0.value >= start && $0.value <= day }.count
        let enough = Set(liveHifz.map(\.dayKey)).count >= 5 && Set(liveHifz.flatMap(\.hifzAyahs)).count >= 50
        let rate = enough && hifzDays > 0 && completed > 0 ? Double(completed) / Double(hifzDays) : nil
        return QuranPace(windowStart: start, hifzDays: hifzDays, completedPages: completed, pagesPerHifzDay: rate)
    }

    /// Calendar walk; caller supplies remaining faces and the plan-unit conversion from verified coverage.
    public static func forecast(remainingPages: Double, dailyPages: Double, startingOn day: GregorianDay,
                                restDay: QuranRestDay, allotments: [QuranDailyAllotment] = [],
                                pagesPerPlanUnit: Double = 1) -> QuranForecast {
        guard remainingPages.isFinite, remainingPages >= 0 else { return .unavailable }
        if remainingPages == 0 { return .complete }
        guard dailyPages.isFinite, dailyPages > 0, pagesPerPlanUnit.isFinite, pagesPerPlanUnit > 0 else { return .unavailable }
        let extras = Dictionary(grouping: QuranDailyPlanEngine.uniqueAllotments(allotments)
            .filter { $0.kind == .hifzExtra }, by: \.dayKey)
        var cursor = day, completed = 0.0
        // Bound tiny/invalid-rate forecasts by the GregorianDay supported range.
        while cursor.year < 9999 {
            if !restDay.contains(cursor) {
                completed += dailyPages + (extras[cursor] ?? []).reduce(0) { $0 + $1.amount * pagesPerPlanUnit }
                if completed + 1e-9 >= remainingPages { return .estimated(cursor) }
            }
            cursor = cursor.adding(days: 1)
        }
        return .unavailable
    }

    public static func meanStrength(_ pages: [QuranPlanningPage]) -> Double? {
        guard !pages.isEmpty else { return nil }
        return Double(pages.reduce(0) { $0 + $1.strength }) / Double(pages.count)
    }
}

public struct QuranQiyamAssignment: Equatable, Sendable {
    /// nil = «أعد ما شئت»; no duplicated grade or page fact is created for it.
    public let pageByRakah: [Int?]
    public var pagesToRecord: [Int] { pageByRakah.compactMap { $0 } }
}
public enum QuranQiyamEngine {
    public static func assignment(rakats: Int, pages: [QuranPlanningPage]) throws -> QuranQiyamAssignment {
        guard [2, 4, 6, 8].contains(rakats) else { throw QuranPlanError.invalidRakats }
        guard !pages.isEmpty else { return QuranQiyamAssignment(pageByRakah: []) }
        let ordered = pages.sorted {
            if $0.isDue != $1.isDue { return $0.isDue }
            if $0.nextDue != $1.nextDue { return $0.nextDue < $1.nextDue }
            return $0.page < $1.page
        }.map(\.page).uniqued()
        var result = Array(ordered.prefix(rakats)).map(Optional.some)
        result += Array(repeating: nil, count: rakats - result.count)
        return QuranQiyamAssignment(pageByRakah: result)
    }
}

extension GregorianDay {
    func distance(to later: GregorianDay) -> Int {
        Int((later.date(in: .gmt).timeIntervalSince1970 - date(in: .gmt).timeIntervalSince1970) / 86_400)
    }
}
