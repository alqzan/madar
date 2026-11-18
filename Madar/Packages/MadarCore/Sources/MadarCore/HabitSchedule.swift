import Foundation

/// A goal that grows by `step` every `everyDays` days from its start value (the rule's target) up to `cap`.
public struct HabitRamp: Equatable, Sendable {
    public let step: Int
    public let everyDays: Int
    public let cap: Int
    public init(step: Int, everyDays: Int, cap: Int) { self.step = step; self.everyDays = everyDays; self.cap = cap }
}
/// The window a habit keeps during Ramadan: anchored to a prayer (offsets in minutes) or on the local clock (minutes of the day).
public struct HabitRamadanWindow: Equatable, Sendable {
    public let anchor: Prayer?
    public let start: Int
    public let end: Int
    public init(anchor: Prayer?, start: Int, end: Int) { self.anchor = anchor; self.start = start; self.end = end }
}

/// Owner, 17 Nov 2026 (ideas 8 and 16): both are plain dated versions of the same rule, so no schema change is needed.
/// Pure: the editor asks for the plan and sends it as `steps` with the save command; the engine already applies a rule from its date.
public enum HabitSchedule {
    public static let maximumSteps = 100
    public static let horizonDays = 3660

    /// The coming Ramadans as [first day, first day of Shawwal): the current one starts today when it is under way.
    public static func ramadanSpans(from today: GregorianDay, days: MadarCalendarDays, count: Int = 2) -> [(start: GregorianDay, end: GregorianDay)] {
        var spans: [(start: GregorianDay, end: GregorianDay)] = [], open: GregorianDay?, day = today
        let limit = today.adding(days: 800)
        while day <= limit, spans.count < count {
            let inRamadan = days.hijri(day).month == 9
            if inRamadan, open == nil { open = day }
            if !inRamadan, let start = open { spans.append((start, day)); open = nil }
            day = day.adding(days: 1)
        }
        return spans
    }

    /// The highest goal a growing plan really reaches inside the stored steps and horizon. A cap above it is a promise the plan cannot keep.
    public static func reachableCap(start: Int, step: Int, everyDays: Int, cap: Int) -> Int {
        guard step > 0, everyDays > 0, cap > start else { return min(start, cap) }
        let steps = min(maximumSteps, horizonDays / everyDays)
        return min(cap, start + steps * step)
    }

    /// `rule` is today's version (its target is the start value); `steps` are the later versions, each a full rule.
    public static func plan(base rule: HabitRule, ramp: HabitRamp?, ramadan: HabitRamadanWindow?, today: GregorianDay, days: MadarCalendarDays) -> (rule: HabitRule, steps: [HabitRule]) {
        let origin = max(rule.effectiveFrom, today)
        let spans = ramadan == nil ? [] : ramadanSpans(from: origin, days: days)
        func inRamadan(_ day: GregorianDay) -> Bool { spans.contains { day >= $0.start && day < $0.end } }
        func target(on day: GregorianDay) -> Int {
            guard let ramp, ramp.everyDays > 0 else { return rule.target }
            return min(ramp.cap, rule.target + MadarCalendarDays.distance(from: origin, to: day) / ramp.everyDays * ramp.step)
        }
        func shaped(_ day: GregorianDay) -> HabitRule {
            var shaped = rule; shaped.effectiveFrom = day; shaped.target = target(on: day)
            if let ramadan, inRamadan(day) { shaped.windowAnchor = ramadan.anchor; shaped.windowStart = ramadan.start; shaped.windowEnd = ramadan.end }
            return shaped
        }
        var dates = Set<GregorianDay>()
        if let ramp, ramp.step > 0, ramp.everyDays > 0 {
            var k = 1
            while rule.target + (k - 1) * ramp.step < ramp.cap, k <= maximumSteps { dates.insert(origin.adding(days: k * ramp.everyDays)); k += 1 }
        }
        for span in spans { dates.insert(span.start); dates.insert(span.end) }
        // Today's version itself already carries the Ramadan window when it starts inside Ramadan.
        let first = rule.effectiveFrom >= today ? shaped(rule.effectiveFrom) : rule
        let steps = dates.filter { $0 > rule.effectiveFrom && $0 <= today.adding(days: horizonDays) }.sorted().prefix(maximumSteps).map(shaped)
        return (first, Array(steps))
    }
}
