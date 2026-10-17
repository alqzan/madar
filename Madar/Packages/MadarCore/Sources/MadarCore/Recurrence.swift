import Foundation

/// Owner, 16 Oct 2026 (M5-X00): anything recurring takes a free interval (every N days, weeks, months or years) and a
/// free first due day. Pure value arithmetic on Gregorian civil days; no time zone, no stored state.
public enum RecurrenceUnit: String, Codable, Sendable, CaseIterable {
    case day, week, month, year
    /// The longest interval accepted for each unit (DECISIONS, M5-X00).
    public var maxEvery: Int {
        switch self { case .day: 365; case .week: 104; case .month: 120; case .year: 10 }
    }
}

public struct Recurrence: Hashable, Sendable {
    public let every: Int
    public let unit: RecurrenceUnit
    public let first: GregorianDay

    public init?(every: Int, unit: RecurrenceUnit, first: GregorianDay) {
        guard (1...unit.maxEvery).contains(every) else { return nil }
        self.every = every; self.unit = unit; self.first = first
    }
    /// Reads the stored Obligation fields; nil when any of them is missing or invalid (the old monthly `dueDay` row).
    public init?(every: Int?, unit: String?, firstDayKey: String?) {
        guard let every, let unit = unit.flatMap(RecurrenceUnit.init(rawValue:)), let key = firstDayKey, let first = try? GregorianDay(key) else { return nil }
        self.init(every: every, unit: unit, first: first)
    }

    private static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }

    /// The n-th due day (0 = the first). Always computed from the first day, never chained from the previous one, so a
    /// 31st stays on the month's last day when a month is shorter (31 Jan → 28/29 Feb → 31 Mar). Negative n counts back.
    public func occurrence(_ n: Int) -> GregorianDay? {
        let component: Calendar.Component, value: Int
        switch unit {
        case .day: component = .day; value = n * every
        case .week: component = .day; value = n * every * 7
        case .month: component = .month; value = n * every
        case .year: component = .month; value = n * every * 12
        }
        let calendar = Self.calendar
        guard let date = calendar.date(byAdding: component, value: value, to: first.date(in: .gmt)) else { return nil }
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return try? GregorianDay(year: p.year ?? 0, month: p.month ?? 0, day: p.day ?? 0)
    }

    /// The index n with occurrence(n) ≤ day < occurrence(n + 1); negative before the first.
    func floorIndex(_ day: GregorianDay) -> Int {
        func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
        var n: Int
        switch unit {
        case .day, .week: n = floorDiv(MadarCalendarDays.distance(from: first, to: day), every * (unit == .week ? 7 : 1))
        case .month, .year:
            let months = (day.year * 12 + day.month) - (first.year * 12 + first.month)
            n = floorDiv(months, every * (unit == .year ? 12 : 1))
        }
        while let at = occurrence(n), at > day { n -= 1 }
        while let at = occurrence(n + 1), at <= day { n += 1 }
        return n
    }

    /// Due days in [start, end), from the first one on.
    public func occurrences(from start: GregorianDay, before end: GregorianDay) -> [GregorianDay] {
        guard start < end else { return [] }
        var n = max(0, floorIndex(start)), result: [GregorianDay] = []
        while result.count < 5_000, let at = occurrence(n), at < end {
            if at >= start { result.append(at) }
            n += 1
        }
        return result
    }

    /// The first due day on or after `day` (the first one when `day` is before it).
    public func next(onOrAfter day: GregorianDay) -> GregorianDay? {
        var n = max(0, floorIndex(day))
        if let at = occurrence(n), at < day { n += 1 }
        return occurrence(n)
    }
    /// The first due day strictly after `day`.
    public func next(after day: GregorianDay) -> GregorianDay? { next(onOrAfter: day.adding(days: 1)) }

    /// The next `count` due days from `today` (today included): the sheet's live preview.
    public func preview(from today: GregorianDay, count: Int = 3) -> [GregorianDay] {
        guard count > 0, let start = next(onOrAfter: today) else { return [] }
        var n = floorIndex(start), result: [GregorianDay] = []
        while result.count < count, let at = occurrence(n) { result.append(at); n += 1 }
        return result
    }

    /// Which due day a linked payment on `day` settles: the nearest one, a tie going to the earlier (a late payment).
    /// A payment nearer to the period before the first due day settles nothing (nil).
    public func occurrenceIndex(paidOn day: GregorianDay) -> Int? {
        let n = floorIndex(day)
        guard let low = occurrence(n) else { return nil }
        let chosen: Int
        if let high = occurrence(n + 1), MadarCalendarDays.distance(from: day, to: high) < MadarCalendarDays.distance(from: low, to: day) { chosen = n + 1 } else { chosen = n }
        return chosen >= 0 ? chosen : nil
    }

    /// Due days in [start, end) that no linked payment settled (§8: one definition of «paid» for every reader).
    public func unpaid(from start: GregorianDay, before end: GregorianDay, paidOn payments: [GregorianDay]) -> [GregorianDay] {
        let settled = Set(payments.compactMap(occurrenceIndex(paidOn:)))
        return occurrences(from: start, before: end).filter { day in !settled.contains(floorIndex(day)) }
    }
}

/// Plain Arabic for a schedule: «كل ٦ أشهر»، «بعد ٤ أشهر ويومين». Number agreement follows MSA: 1 singular, 2 dual,
/// 3–10 plural, 11–99 singular accusative, and a hundred and above singular.
public enum RecurrencePhrase {
    public static func count(_ n: Int, _ unit: RecurrenceUnit, digits: MadarNumberFormatter = .init()) -> String {
        let forms: (one: String, two: String, few: String, many: String) = switch unit {
        case .day: ("يوم", "يومين", "أيام", "يومًا")
        case .week: ("أسبوع", "أسبوعين", "أسابيع", "أسبوعًا")
        case .month: ("شهر", "شهرين", "أشهر", "شهرًا")
        case .year: ("سنة", "سنتين", "سنوات", "سنة")
        }
        if n == 1 { return forms.one }
        if n == 2 { return forms.two }
        let tail = n % 100
        if (3...10).contains(tail) { return digits.string(n) + " " + forms.few }
        if (11...99).contains(tail) { return digits.string(n) + " " + forms.many }
        return digits.string(n) + " " + forms.one
    }

    /// «كل شهر»، «كل أسبوعين»، «كل ٦ أشهر»، «كل ١١ شهرًا».
    public static func every(_ recurrence: Recurrence, digits: MadarNumberFormatter = .init()) -> String {
        "كل " + count(recurrence.every, recurrence.unit, digits: digits)
    }

    /// Whole years, months then days from `from` to `to` (to ≥ from), month steps clamped from `from` like the schedule.
    public static func span(from: GregorianDay, to: GregorianDay) -> (years: Int, months: Int, days: Int) {
        guard from < to else { return (0, 0, 0) }
        var months = max(0, (to.year * 12 + to.month) - (from.year * 12 + from.month))
        func shifted(_ m: Int) -> GregorianDay? { Recurrence(every: 1, unit: .month, first: from)?.occurrence(m) }
        while months > 0, let at = shifted(months), at > to { months -= 1 }
        let base = shifted(months) ?? from
        return (months / 12, months % 12, MadarCalendarDays.distance(from: base, to: to))
    }

    /// «اليوم»، «غدًا»، «بعد ٤ أشهر ويومين»، «قبل ٣ أيام».
    public static func relative(from today: GregorianDay, to day: GregorianDay, digits: MadarNumberFormatter = .init()) -> String {
        if day == today { return "اليوم" }
        if day == today.adding(days: 1) { return "غدًا" }
        let ahead = day > today
        let s = ahead ? span(from: today, to: day) : span(from: day, to: today)
        var parts: [String] = []
        if s.years > 0 { parts.append(count(s.years, .year, digits: digits)) }
        if s.months > 0 { parts.append(count(s.months, .month, digits: digits)) }
        if s.days > 0 { parts.append(count(s.days, .day, digits: digits)) }
        return (ahead ? "بعد " : "قبل ") + parts.joined(separator: " و")
    }
}
