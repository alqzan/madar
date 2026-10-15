import Foundation

/// §7.1 «السنة وما يهمّك», B03 and B04: pure calendar math over Madar day keys. Counting is by day-key difference,
/// never by hours; a day key's Hijri date is read at its local noon, as `MadarDay.resolve` stores it.
public struct MadarCalendarDays: Sendable {
    public let zone: TimeZone
    public let source: HijriSource
    public let offset: Int
    public init(zone: TimeZone, source: HijriSource = .ummAlQura, offset: Int = 0) { self.zone = zone; self.source = source; self.offset = offset }
    public func hijri(_ day: GregorianDay) -> HijriDate {
        HijriCalendar.date(for: day.date(in: zone).addingTimeInterval(12 * 3600), timeZone: zone, source: source, sightingOffset: offset)
    }
    public func isLastHijriDay(_ day: GregorianDay) -> Bool { hijri(day.adding(days: 1)).day == 1 }
    public func hijriMonthStart(containing day: GregorianDay) -> GregorianDay { day.adding(days: -(hijri(day).day - 1)) }
    /// 29 or 30, from the calendar in force (Umm al-Qura or sighting with its correction).
    public func hijriMonthLength(containing day: GregorianDay) -> Int { hijri(hijriMonthStart(containing: day).adding(days: 29)).day == 30 ? 30 : 29 }
    public static func distance(from a: GregorianDay, to b: GregorianDay) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.dateComponents([.day], from: a.date(in: .gmt), to: b.date(in: .gmt)).day ?? 0
    }
    static func gregorianMonthLength(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)!.count
    }
}

/// A period on the strip: `elapsed` counts the whole days before today, so the first day shows 0 and the last shows
/// one day left; elapsed + remaining = length.
public struct MadarPeriod: Equatable, Sendable {
    public let start: GregorianDay
    public let length: Int
    public let elapsed: Int
    public var remaining: Int { length - elapsed }
    /// Basis points (YearSnapshot `*ProgressBp`).
    public var basisPoints: Int { length > 0 ? elapsed * 10_000 / length : 0 }
}

public enum MadarWeekStart: String, Sendable { case saturday, sunday }

public struct MadarLandmark: Equatable, Sendable {
    public enum Name: String, Sendable { case ramadan, eidAlFitr, arafah, hijriNewYear, gregorianYearEnd }
    public let name: Name
    public let day: GregorianDay
    public let hijri: HijriDate
    public let daysLeft: Int
}

public enum MadarYear {
    public static func gregorianYear(_ today: GregorianDay) -> MadarPeriod {
        let start = try! GregorianDay(year: today.year, month: 1, day: 1), next = try! GregorianDay(year: today.year + 1, month: 1, day: 1)
        return .init(start: start, length: MadarCalendarDays.distance(from: start, to: next), elapsed: MadarCalendarDays.distance(from: start, to: today))
    }
    public static func gregorianMonth(_ today: GregorianDay) -> MadarPeriod {
        .init(start: try! GregorianDay(year: today.year, month: today.month, day: 1), length: MadarCalendarDays.gregorianMonthLength(year: today.year, month: today.month), elapsed: today.day - 1)
    }
    public static func hijriMonth(_ today: GregorianDay, _ days: MadarCalendarDays) -> MadarPeriod {
        .init(start: days.hijriMonthStart(containing: today), length: days.hijriMonthLength(containing: today), elapsed: days.hijri(today).day - 1)
    }
    public static func hijriYear(_ today: GregorianDay, _ days: MadarCalendarDays) -> MadarPeriod {
        var start = days.hijriMonthStart(containing: today)
        for _ in 0..<12 where days.hijri(start).month != 1 { start = days.hijriMonthStart(containing: start.adding(days: -1)) }
        var next = start, length = 0
        for _ in 0..<12 { let month = days.hijriMonthLength(containing: next); length += month; next = next.adding(days: month) }
        return .init(start: start, length: length, elapsed: MadarCalendarDays.distance(from: start, to: today))
    }
    /// `core.weekStart` (default Saturday, RL10).
    public static func week(_ today: GregorianDay, start: MadarWeekStart) -> MadarPeriod {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let weekday = calendar.component(.weekday, from: today.date(in: .gmt)) // 1 = Sunday … 7 = Saturday
        let elapsed = start == .saturday ? weekday % 7 : weekday - 1
        return .init(start: today.adding(days: -elapsed), length: 7, elapsed: elapsed)
    }
    /// B04 «أهلّة الشهر الهجري»: drawn from the Hijri day, not astronomy. f = (d − 0.5) / L, lit = (1 − cos 2πf) / 2.
    public static func crescent(day: Int, length: Int) -> (lit: Double, waxing: Bool) {
        let f = (Double(day) - 0.5) / Double(length)
        return ((1 - cos(2 * .pi * f)) / 2, f < 0.5)
    }
    /// Ramadan, Eid al-Fitr, Arafah, Hijri new year and the Gregorian year end: next on or after today, nearest first.
    public static func landmarks(_ today: GregorianDay, _ days: MadarCalendarDays) -> [MadarLandmark] {
        let hijri: [(MadarLandmark.Name, Int, Int)] = [(.ramadan, 9, 1), (.eidAlFitr, 10, 1), (.arafah, 12, 9), (.hijriNewYear, 1, 1)]
        var list = hijri.compactMap { name, month, day in
            MadarUpcomingRule(calendar: .hijri, month: month, day: day, repeats: .yearly).next(onOrAfter: today, days).map { MadarLandmark(name: name, day: $0, hijri: days.hijri($0), daysLeft: MadarCalendarDays.distance(from: today, to: $0)) }
        }
        let end = try! GregorianDay(year: today.year, month: 12, day: 31)
        list.append(.init(name: .gregorianYearEnd, day: end, hijri: days.hijri(end), daysLeft: MadarCalendarDays.distance(from: today, to: end)))
        return list.sorted { $0.daysLeft == $1.daysLeft ? $0.name.rawValue < $1.name.rawValue : $0.daysLeft < $1.daysLeft }
    }
    /// «رمضان بعد كم»; nil while Ramadan is under way.
    public static func ramadanIn(_ today: GregorianDay, _ days: MadarCalendarDays) -> Int? {
        guard days.hijri(today).month != 9, let start = MadarUpcomingRule(calendar: .hijri, month: 9, day: 1, repeats: .yearly).next(onOrAfter: today, days) else { return nil }
        return MadarCalendarDays.distance(from: today, to: start)
    }
}

/// B03 «يوم تنتظره»: the stored row keeps the rule; occurrences are derived. A missing day falls back to the month's
/// last day (Hijri 30 in a 29-day month → 29; 29 February → 28; 31 in a shorter month → its last day).
public struct MadarUpcomingRule: Equatable, Sendable {
    public enum Repeats: String, Sendable { case none, yearly, monthly }
    public let calendar: FirstCalendar
    public let year: Int?
    public let month: Int
    public let day: Int
    public let repeats: Repeats
    public let countFrom: GregorianDay?
    public init(calendar: FirstCalendar, year: Int? = nil, month: Int, day: Int, repeats: Repeats, countFrom: GregorianDay? = nil) {
        self.calendar = calendar; self.year = year; self.month = month; self.day = day; self.repeats = repeats; self.countFrom = countFrom
    }
    public func matches(_ candidate: GregorianDay, _ days: MadarCalendarDays) -> Bool {
        let (y, m, d, last): (Int, Int, Int, Bool)
        if calendar == .hijri { let h = days.hijri(candidate); (y, m, d, last) = (h.year, h.month, h.day, days.isLastHijriDay(candidate)) }
        else { (y, m, d) = (candidate.year, candidate.month, candidate.day); last = d == MadarCalendarDays.gregorianMonthLength(year: y, month: m) }
        if repeats != .monthly, m != month { return false }
        if repeats == .none, let year, y != year { return false }
        return d == day || (d < day && last)
    }
    /// The first occurrence on or after `today`; nil when a one-time day has passed (searched within ~13 months).
    public func next(onOrAfter today: GregorianDay, _ days: MadarCalendarDays) -> GregorianDay? {
        let horizon = repeats == .none ? 800 : 400
        return (0...horizon).lazy.map { today.adding(days: $0) }.first { matches($0, days) }
    }
    public func previous(before day: GregorianDay, _ days: MadarCalendarDays) -> GregorianDay? {
        guard repeats != .none else { return nil }
        return (1...400).lazy.map { day.adding(days: -$0) }.first { matches($0, days) }
    }
    /// The ring closes from countStart to the next occurrence; countStart = max(countFrom, the day after the previous one).
    public func ring(today: GregorianDay, _ days: MadarCalendarDays) -> (next: GregorianDay, daysLeft: Int, closed: Double)? {
        guard let next = next(onOrAfter: today, days) else { return nil }
        let start = [countFrom, previous(before: next, days).map { $0.adding(days: 1) }].compactMap { $0 }.max() ?? today
        let span = MadarCalendarDays.distance(from: start, to: next), done = MadarCalendarDays.distance(from: start, to: today)
        return (next, MadarCalendarDays.distance(from: today, to: next), span > 0 ? min(1, max(0, Double(done) / Double(span))) : 1)
    }
}
