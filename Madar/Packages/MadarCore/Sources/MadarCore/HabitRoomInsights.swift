import Foundation

/// What one habit gave the habits room to read: its evaluated periods, the days it was done and the instants it was logged.
public struct HabitRoomSeries: Sendable {
    public let id: UUID
    public let periods: [HabitPeriodResult]
    public let doneDays: [GregorianDay]
    public let loggedAt: [Date]
    public init(id: UUID, periods: [HabitPeriodResult], doneDays: [GregorianDay], loggedAt: [Date]) {
        self.id = id; self.periods = periods; self.doneDays = doneDays; self.loggedAt = loggedAt
    }
    var isDaily: Bool { periods.last?.rule.frequency == .daily && periods.last?.rule.measure != .abstain }
}

/// Owner, 17 Nov 2026 («ما لاحظه مدار»): everything the lower half of the habits room says, computed from the habits' own
/// evaluated periods and log times. Pure: a note appears only when there is enough data, otherwise the function answers nil.
public enum HabitRoomInsights {
    /// 6 ص … 11 م, one bucket per hour.
    public static let hourRange = 6...23
    /// The days a weekday rate reads (about four months).
    public static let weekdayWindow = 120
    public static let minimumLogs = 8

    public struct WeekdayStat: Equatable, Sendable {
        /// `Calendar` numbering: 1 = Sunday … 7 = Saturday.
        public let weekday: Int
        public let rate: Double?
        public let samples: Int
    }
    public struct Peak: Equatable, Sendable {
        /// First hour of the busiest stretch and the hour it ends (24-hour clock, end exclusive).
        public let from: Int
        public let to: Int
        /// The share of every log that falls inside the stretch.
        public let share: Double
    }
    public enum Trend: Equatable, Sendable { case rising(from: Double, to: Double), falling(from: Double, to: Double), steady(Double) }
    public struct Mover: Equatable, Sendable {
        public let id: UUID
        public let before: Double
        public let now: Double
        public var rising: Bool { now > before }
    }
    public struct YearMonth: Equatable, Sendable {
        public let index: Int
        public let start: GregorianDay
        public let length: Int
        public var end: GregorianDay { start.adding(days: length) }
    }
    public struct Extremes: Equatable, Sendable {
        public let best: Int
        public let worst: Int?
    }

    // MARK: Weekdays

    /// The share of countable days kept on each weekday, over the last `weekdayWindow` closed days of every daily habit.
    public static func weekdayRates(_ series: [HabitRoomSeries], today: GregorianDay) -> [WeekdayStat] {
        var met = [Int: Int](), total = [Int: Int]()
        for s in series where s.isDaily {
            for p in countedDays(s, from: today.adding(days: -weekdayWindow), to: today) {
                let w = HabitEngine.weekday(p.start); total[w, default: 0] += 1; if p.met { met[w, default: 0] += 1 }
            }
        }
        return (1...7).map { w in .init(weekday: w, rate: total[w].map { Double(met[w, default: 0]) / Double($0) }, samples: total[w, default: 0]) }
    }
    /// A longer habit has no «rate» per weekday; it has the share of its logs that fell on each.
    public static func weekdayShares(_ doneDays: [GregorianDay]) -> [WeekdayStat] {
        var count = [Int: Int]()
        for d in doneDays { count[HabitEngine.weekday(d), default: 0] += 1 }
        let all = doneDays.count
        return (1...7).map { w in .init(weekday: w, rate: all == 0 ? nil : Double(count[w, default: 0]) / Double(all), samples: all) }
    }
    /// The one or two weekdays that fall clearly below the rest: every weekday needs three samples, the weakest sit within
    /// three points of the minimum, and the minimum is at least ten points under the overall rate. Weakest first.
    public static func weakestWeekdays(_ stats: [WeekdayStat]) -> [Int]? {
        guard stats.count == 7, stats.allSatisfy({ $0.samples >= 3 && $0.rate != nil }) else { return nil }
        let totalSamples = stats.reduce(0) { $0 + $1.samples }
        let overall = stats.reduce(0.0) { $0 + $1.rate! * Double($1.samples) } / Double(totalSamples)
        let sorted = stats.sorted { ($0.rate!, $0.weekday) < ($1.rate!, $1.weekday) }
        guard let minimum = sorted.first?.rate, overall - minimum >= 0.10 else { return nil }
        return Array(sorted.filter { $0.rate! <= minimum + 0.03 }.prefix(2).map(\.weekday))
    }
    /// The strongest weekday of a longer habit, when one day holds at least half of its logs (needs `minimumLogs` logs... of any day).
    public static func dominantWeekday(_ shares: [WeekdayStat]) -> Int? {
        guard let top = shares.max(by: { ($0.rate ?? -1, -$0.weekday) < ($1.rate ?? -1, -$1.weekday) }), let rate = top.rate, top.samples >= 4, rate >= 0.5 else { return nil }
        return top.weekday
    }

    // MARK: Hours

    /// How many logs fell in each hour from 6 to 23, in `zone`.
    public static func hourBuckets(_ loggedAt: [Date], zone: TimeZone) -> [Int] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var buckets = [Int](repeating: 0, count: hourRange.count)
        for d in loggedAt { let h = calendar.component(.hour, from: d); if hourRange.contains(h) { buckets[h - hourRange.lowerBound] += 1 } }
        return buckets
    }
    /// The busiest stretch: the peak hour plus the neighbouring hours that hold at least half as much. Needs `minimumLogs` logs.
    public static func peak(_ buckets: [Int]) -> Peak? {
        let total = buckets.reduce(0, +)
        guard total >= minimumLogs, let top = buckets.max(), top > 0, let index = buckets.firstIndex(of: top) else { return nil }
        var low = index, high = index
        while low > 0, Double(buckets[low - 1]) >= Double(top) / 2 { low -= 1 }
        while high < buckets.count - 1, Double(buckets[high + 1]) >= Double(top) / 2 { high += 1 }
        let inside = buckets[low...high].reduce(0, +)
        return .init(from: hourRange.lowerBound + low, to: hourRange.lowerBound + high + 1, share: Double(inside) / Double(total))
    }
    /// The share of logs made before noon.
    public static func morningShare(_ buckets: [Int]) -> Double? {
        let total = buckets.reduce(0, +)
        guard total >= minimumLogs else { return nil }
        return Double(buckets.prefix(12 - hourRange.lowerBound).reduce(0, +)) / Double(total)
    }

    // MARK: Trend

    /// The kept share of each of the last `weeks` seven-day windows of the daily habits, oldest first. A window with fewer than
    /// four countable days is nil. The newest window ends the day before `today`, so an unfinished day never drags it down.
    public static func weeklyRates(_ series: [HabitRoomSeries], today: GregorianDay, weeks: Int = 8) -> [Double?] {
        (0..<weeks).reversed().map { k in
            let end = today.adding(days: -7 * k), start = end.adding(days: -7)
            var met = 0, total = 0
            for s in series where s.isDaily { for p in countedDays(s, from: start, to: end) { total += 1; if p.met { met += 1 } } }
            return total >= 4 ? Double(met) / Double(total) : nil
        }
    }
    /// A longer habit's own last `count` closed periods, each as the share of its target reached (1 when kept), oldest first.
    public static func periodRates(_ periods: [HabitPeriodResult], today: GregorianDay, count: Int = 8) -> [Double?] {
        let closed = periods.filter { $0.target > 0 && $0.outcome != .excluded && $0.end <= today.adding(days: 1) }
        let last = closed.suffix(count).map { p -> Double? in p.met ? 1 : min(1, Double(p.value) / Double(p.target)) }
        return Array(repeating: nil, count: count - last.count) + last
    }
    /// Rising, falling or steady: the mean of the first third against the last third of the points that exist. Needs five points.
    public static func trend(_ rates: [Double?]) -> Trend? {
        let valid = rates.compactMap { $0 }
        guard valid.count >= 5 else { return nil }
        let n = min(3, valid.count / 2)
        let first = valid.prefix(n).reduce(0, +) / Double(n), last = valid.suffix(n).reduce(0, +) / Double(n)
        if last - first >= 0.08 { return .rising(from: first, to: last) }
        if first - last >= 0.08 { return .falling(from: first, to: last) }
        return .steady(last)
    }
    /// The daily habit whose last 14 days moved most against the 14 before, when it moved at least 25 points and both spans
    /// have ten countable days.
    public static func mover(_ series: [HabitRoomSeries], today: GregorianDay) -> Mover? {
        var best: Mover?
        for s in series where s.isDaily {
            let recent = countedDays(s, from: today.adding(days: -14), to: today), before = countedDays(s, from: today.adding(days: -28), to: today.adding(days: -14))
            guard recent.count >= 10, before.count >= 10 else { continue }
            let r = Double(recent.filter(\.met).count) / Double(recent.count), b = Double(before.filter(\.met).count) / Double(before.count)
            guard abs(r - b) >= 0.25 else { continue }
            if best == nil || abs(r - b) > abs(best!.now - best!.before) { best = .init(id: s.id, before: b, now: r) }
        }
        return best
    }

    // MARK: Year

    /// The twelve months of the year that holds `today`, in the calendar the user reads first.
    public static func yearMonths(containing today: GregorianDay, calendar: FirstCalendar, days: MadarCalendarDays) -> [YearMonth] {
        if calendar == .gregorian {
            return (1...12).map { m in
                let start = try! GregorianDay(year: today.year, month: m, day: 1)
                return .init(index: m, start: start, length: MadarCalendarDays.gregorianMonthLength(year: today.year, month: m))
            }
        }
        var start = MadarYear.hijriYear(today, days).start, months = [YearMonth]()
        for m in 1...12 { let length = days.hijriMonthLength(containing: start); months.append(.init(index: m, start: start, length: length)); start = start.adding(days: length) }
        return months
    }
    /// How kept each day was, 0…1, for every day up to `today`: with no habit selected, the share of the daily habits met that
    /// day; with a daily habit selected, its own day; with a longer habit selected, 1 on a day it was done and 0 on the others
    /// since it began. A day with nothing countable is absent.
    public static func dayRates(_ series: [HabitRoomSeries], selected: UUID?, today: GregorianDay) -> [GregorianDay: Double] {
        var met = [GregorianDay: Double](), total = [GregorianDay: Double]()
        if let selected, let s = series.first(where: { $0.id == selected }), !s.isDaily {
            guard let first = s.periods.first?.start ?? s.doneDays.min(), first <= today else { return [:] }
            var rates = [GregorianDay: Double](), cursor = first
            while cursor <= today { rates[cursor] = 0; cursor = cursor.adding(days: 1) }
            for d in s.doneDays where d <= today && d >= first { rates[d] = 1 }
            return rates
        }
        for s in series where s.isDaily && (selected == nil || s.id == selected) {
            for p in s.periods where p.rule.frequency == .daily && p.target > 0 && p.outcome != .excluded && p.start <= today {
                total[p.start, default: 0] += 1; if p.met { met[p.start, default: 0] += 1 }
            }
        }
        return total.reduce(into: [GregorianDay: Double]()) { $0[$1.key] = met[$1.key, default: 0] / $1.value }
    }
    /// The month's value: the mean of its day rates (a month with fewer than seven rated days is nil). For a longer habit,
    /// `counting` gives the number of days it was done instead.
    public static func monthValues(_ months: [YearMonth], rates: [GregorianDay: Double], counting: Bool = false) -> [Double?] {
        months.map { m in
            let days = (0..<m.length).compactMap { rates[m.start.adding(days: $0)] }
            if counting { return days.isEmpty ? nil : days.reduce(0, +) }
            return days.count >= 7 ? days.reduce(0, +) / Double(days.count) : nil
        }
    }
    /// The best and the worst month among those that are over and have a value; the worst needs a second month.
    public static func extremes(_ values: [Double?], complete: [Bool]) -> Extremes? {
        let ranked = values.enumerated().compactMap { i, v -> (Int, Double)? in complete.indices.contains(i) && complete[i] ? v.map { (i, $0) } : nil }
        guard let best = ranked.max(by: { ($0.1, -$0.0) < ($1.1, -$1.0) }) else { return nil }
        let rest = ranked.filter { $0.0 != best.0 }
        guard let worst = rest.min(by: { ($0.1, $0.0) < ($1.1, $1.0) }), worst.1 < best.1 else { return .init(best: best.0, worst: nil) }
        return .init(best: best.0, worst: worst.0)
    }

    // MARK: Story

    /// The longest streak, derived from the periods and never stored, by the engine's own rule: a kept period adds one, a miss
    /// only counts against the run and `breakAfter` misses in a row end it, an excluded (frozen or not yet due) period changes
    /// nothing, a change of frequency starts again, and the open period never counts as a miss. `end` is the last day of the
    /// final kept period of the longest run.
    public static func longestStreak(_ periods: [HabitPeriodResult], today: GregorianDay, breakAfter: Int = 2) -> (length: Int, end: GregorianDay)? {
        var run = 0, misses = 0, best = 0, bestEnd: GregorianDay?, frequency = periods.first?.rule.frequency
        for p in periods {
            if p.rule.frequency != frequency { run = 0; misses = 0; frequency = p.rule.frequency }
            if p.target == 0 || p.outcome == .excluded { continue }
            if p.met { run += 1; misses = 0; if run > best { best = run; bestEnd = p.end.adding(days: -1) } }
            else if p.end <= today.adding(days: 1) && p.start < today {
                if p.rule.measure == .abstain { run = 0; misses = 0 }
                else { misses += 1; if misses >= breakAfter { run = 0 } }
            }
        }
        guard best > 0, let bestEnd else { return nil }
        return (best, bestEnd)
    }
    /// How many periods of the habit were kept since it began, out of those that counted.
    public static func keptPeriods(_ periods: [HabitPeriodResult]) -> (kept: Int, counted: Int) {
        let counted = periods.filter { $0.target > 0 && $0.outcome != .excluded }
        return (counted.filter(\.met).count, counted.count)
    }

    // MARK: Helpers

    private static func countedDays(_ s: HabitRoomSeries, from: GregorianDay, to: GregorianDay) -> [HabitPeriodResult] {
        s.periods.filter { $0.rule.frequency == .daily && $0.rule.measure != .abstain && $0.target > 0 && $0.outcome != .excluded && $0.start >= from && $0.start < to }
    }
}
