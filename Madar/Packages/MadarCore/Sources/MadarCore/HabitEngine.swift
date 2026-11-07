import Foundation

/// `interval` (FB-39, owner 6 Nov: «كل ٣ أيام»، «كل ٤٠ يومًا»): each period is `intervalDays` consecutive days
/// counted from the habit's first date; any day inside the period counts.
public enum HabitFrequency: String, Codable, Sendable { case daily, weekly, monthly, yearly, interval }
public enum HabitMeasure: String, Codable, Sendable { case once, count, duration, health }
/// Rules are versioned; identity, archived state and owning-room facts are deliberately outside this pure engine.
public struct HabitRule: Codable, Equatable, Sendable {
    public var effectiveFrom: GregorianDay
    public var frequency: HabitFrequency = .daily
    public var measure: HabitMeasure = .once
    public var unit: String? = nil
    public var target = 1
    public var minimum: Int? = nil
    /// Foundation weekday numbers, Sunday = 1. Designated days define the period target (RL3).
    public var weekdays: [Int] = []
    public var monthDays: [Int] = []
    public var hijri = false
    public var yearMonth = 1
    public var yearDay = 1
    public var restWeekdays: [Int] = []
    public var windowAnchor: Prayer? = nil
    public var windowStart: Int? = nil
    public var windowEnd: Int? = nil
    public var intervalDays: Int? = nil
    public init(effectiveFrom: GregorianDay) { self.effectiveFrom = effectiveFrom }
    public func validate() throws {
        guard target > 0, minimum.map({ $0 > 0 && $0 <= target }) ?? true,
              weekdays.allSatisfy({ (1...7).contains($0) }), restWeekdays.allSatisfy({ (1...7).contains($0) }),
              monthDays.allSatisfy({ (1...31).contains($0) }), (1...12).contains(yearMonth), (1...31).contains(yearDay),
              (windowStart == nil) == (windowEnd == nil),
              frequency == .interval ? (intervalDays.map { (2...3660).contains($0) } ?? false) : intervalDays == nil else { throw CoreError.invalidCommand }
        if let start = windowStart, let end = windowEnd {
            let difference = end.subtractingReportingOverflow(start)
            guard !difference.overflow, (-1439...1440).contains(difference.partialValue), difference.partialValue != 0,
                  windowAnchor != nil || ((0..<1440).contains(start) && (0..<1440).contains(end)) else { throw CoreError.invalidCommand }
        }
        if measure == .duration && unit != "minutes" { throw CoreError.invalidCommand }
        if measure == .health && unit != "steps" && unit != "exerciseMinutes" { throw CoreError.invalidCommand }
    }
}
public struct HabitFact: Sendable {
    public let id: UUID
    public let day: GregorianDay
    public let periodKey: String
    public let delta: Int
    public let unit: String?
    public init(id: UUID, day: GregorianDay, periodKey: String, delta: Int, unit: String? = nil) { self.id = id; self.day = day; self.periodKey = periodKey; self.delta = delta; self.unit = unit }
}
public struct HabitBreak: Sendable {
    public let from: GregorianDay
    /// Exclusive; unfreezing today leaves the earlier frozen days intact.
    public let until: GregorianDay?
    public init(from: GregorianDay, until: GregorianDay? = nil) { self.from = from; self.until = until }
    public func contains(_ day: GregorianDay) -> Bool { day >= from && (until == nil || day < until!) }
    public static func validateStart(_ day: GregorianDay, today: GregorianDay) throws {
        guard day >= today.adding(days: -1), day <= today else { throw CoreError.invalidCommand }
    }
}
public struct HabitWeekChange: Sendable {
    public let day: GregorianDay
    public let start: MadarWeekStart
    public init(day: GregorianDay, start: MadarWeekStart) { self.day = day; self.start = start }
}
public struct HabitCalendarChange: Sendable {
    public let day: GregorianDay
    public let source: HijriSource
    public let offset: Int
    public init(day: GregorianDay, source: HijriSource, offset: Int) { self.day=day;self.source=source;self.offset=offset }
}
public enum HabitOutcome: String, Sendable { case waiting, complete, minimum, missed, excluded }
public struct HabitPeriodResult: Sendable {
    public let key: String
    public let start: GregorianDay
    public let end: GregorianDay
    public let rule: HabitRule
    public let dueDays: [GregorianDay]
    public let target: Int
    public let value: Int
    public let outcome: HabitOutcome
    public var met: Bool { outcome == .complete || outcome == .minimum }
}
public struct HabitSummary: Sendable {
    public let periods: [HabitPeriodResult]
    public let streak: Int
    public let consecutiveMisses: Int
    public var current: HabitPeriodResult? { periods.last }
    public var atRisk: Bool { streak > 0 && consecutiveMisses > 0 }
}
public enum HabitEngine {
    public static func weekday(_ day: GregorianDay) -> Int { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c.component(.weekday, from: day.date(in: .gmt)) }
    private static func weekStart(_ day: GregorianDay, _ start: MadarWeekStart) -> GregorianDay { day.adding(days: -((weekday(day) - (start == .saturday ? 7 : 1) + 7) % 7)) }
    private static func intervalStart(_ day: GregorianDay, origin: GregorianDay, length: Int) -> GregorianDay {
        let offset = MadarCalendarDays.distance(from: origin, to: day)
        return origin.adding(days: Int((Double(offset) / Double(length)).rounded(.down)) * length)
    }
    private static func naturalStart(_ day: GregorianDay, _ rule: HabitRule, _ days: MadarCalendarDays, _ week: MadarWeekStart, anchor: GregorianDay? = nil) -> GregorianDay {
        switch rule.frequency {
        case .daily: day
        case .interval: intervalStart(day, origin: anchor ?? rule.effectiveFrom, length: rule.intervalDays ?? 1)
        case .weekly: weekStart(day, week)
        case .monthly: rule.hijri ? days.hijriMonthStart(containing: day) : try! GregorianDay(year: day.year, month: day.month, day: 1)
        case .yearly: rule.hijri ? MadarYear.hijriYear(day, days).start : try! GregorianDay(year: day.year, month: 1, day: 1)
        }
    }
    private static func next(_ start: GregorianDay, _ rule: HabitRule, _ days: MadarCalendarDays, _ week: MadarWeekStart, extendWeek: Bool = true) -> GregorianDay {
        switch rule.frequency {
        case .daily: return start.adding(days: 1)
        case .interval: return start.adding(days: rule.intervalDays ?? 1)
        case .weekly:
            let first = weekStart(start, week); return first < start && extendWeek ? first.adding(days: 14) : first.adding(days: 7)
        case .monthly:
            if rule.hijri { return days.hijriMonthStart(containing: start).adding(days: days.hijriMonthLength(containing: start)) }
            return start.adding(days: MadarCalendarDays.gregorianMonthLength(year: start.year, month: start.month) - start.day + 1)
        case .yearly:
            if rule.hijri { let year = MadarYear.hijriYear(start, days); return year.start.adding(days: year.length) }
            return try! GregorianDay(year: start.year + 1, month: 1, day: 1)
        }
    }
    public static func periodKey(_ start: GregorianDay, rule: HabitRule, days: MadarCalendarDays) -> String {
        switch rule.frequency {
        case .daily, .weekly, .interval: return start.description
        case .monthly, .yearly:
            let h = days.hijri(start), year = rule.hijri ? h.year : start.year, month = rule.hijri ? h.month : start.month
            return (rule.hijri ? "h:" : "g:") + String(format: "%04d", year) + (rule.frequency == .monthly ? String(format: "-%02d", month) : "")
        }
    }
    /// Values are sums of immutable events, deduplicated by event identity, never max-merged.
    /// Linked habits supply owner facts and `ownerStreak`; they never create HabitEvent rows.
    public static func evaluate(rules: [HabitRule], facts: [HabitFact], pauses: [HabitBreak] = [], today: GregorianDay,
                                days: MadarCalendarDays, weekStart initialWeek: MadarWeekStart = .saturday,
                                weekChanges: [HabitWeekChange] = [], calendarChanges: [HabitCalendarChange] = [], breakAfter: Int = 2, ownerStreak: Int? = nil) throws -> HabitSummary {
        let rules = rules.sorted { $0.effectiveFrom < $1.effectiveFrom }
        let orderedWeeks=weekChanges.enumerated().sorted { a,b in a.element.day == b.element.day ? a.offset < b.offset : a.element.day < b.element.day }.map(\.element)
        let orderedCalendars=calendarChanges.enumerated().sorted { a,b in a.element.day == b.element.day ? a.offset < b.offset : a.element.day < b.element.day }.map(\.element)
        for rule in rules { try rule.validate() }
        guard let first = rules.first, first.effectiveFrom <= today, (1...3).contains(breakAfter) else { return .init(periods: [], streak: 0, consecutiveMisses: 0) }
        var identities = Set<UUID>(); let facts = facts.filter { identities.insert($0.id).inserted }
        // Keep original order for overflow checks while indexing each fact only once.
        var factsByDay: [GregorianDay: [(Int, HabitFact)]] = [:]
        var factsByKey: [String: [(Int, HabitFact)]] = [:]
        for (index, fact) in facts.enumerated() where fact.day >= first.effectiveFrom && fact.day <= today && !pauses.contains(where: { $0.contains(fact.day) }) {
            if fact.periodKey.isEmpty { factsByDay[fact.day, default: []].append((index, fact)) }
            else { factsByKey[fact.periodKey, default: []].append((index, fact)) }
        }
        func calendar(at day:GregorianDay)->MadarCalendarDays {
            guard let change=orderedCalendars.last(where:{$0.day<=day})else{return days}
            return MadarCalendarDays(zone:days.zone,source:change.source,offset:change.offset)
        }
        let creationDays=days
        var cursor = naturalStart(first.effectiveFrom, first, creationDays, initialWeek), week = initialWeek
        var results: [HabitPeriodResult] = [], streak = 0, misses = 0, lastFrequency = first.frequency
        while cursor <= today {
            // A closed period keeps the calendar in force at its start, as it keeps its policy.
            let periodDays=calendar(at:cursor)
            if let change = orderedWeeks.last(where: { $0.day < cursor }) { week = change.start }
            let atStart = rules.last(where: { $0.effectiveFrom <= max(cursor, first.effectiveFrom) }) ?? first
            let frequencyChanged = atStart.frequency != lastFrequency
            var end = next(cursor, atStart, periodDays, week, extendWeek: !frequencyChanged)
            if let changed = rules.first(where: { $0.effectiveFrom > cursor && $0.effectiveFrom < end && $0.frequency != atStart.frequency }) { end = changed.effectiveFrom }
            // A goal/unit/window edit affects its current period, never an earlier closed period.
            let rule = rules.last(where: { $0.effectiveFrom < end && $0.effectiveFrom <= today && $0.frequency == atStart.frequency }) ?? atStart
            if rule.frequency != lastFrequency { streak = 0; misses = 0; lastFrequency = rule.frequency }
            var due: [GregorianDay] = [], scheduled = 0, eligible = 0, day = cursor
            var periodFacts: [(Int, HabitFact)] = []
            func isScheduled(_ day: GregorianDay) -> Bool {
                let h = periodDays.hijri(day), monthLength = rule.hijri ? periodDays.hijriMonthLength(containing: day) : MadarCalendarDays.gregorianMonthLength(year: day.year, month: day.month)
                var isDue = true
                switch rule.frequency {
                case .daily, .interval: break
                case .weekly: isDue = rule.weekdays.isEmpty || rule.weekdays.contains(weekday(day))
                case .monthly: isDue = rule.monthDays.isEmpty || Set(rule.monthDays.map { min($0, monthLength) }).contains(rule.hijri ? h.day : day.day)
                case .yearly: isDue = (rule.hijri ? h.month : day.month) == rule.yearMonth && (rule.hijri ? h.day : day.day) == min(rule.yearDay, monthLength)
                }
                return isDue && !rule.restWeekdays.contains(weekday(day))
            }
            while day < end {
                if let found = factsByDay[day] { periodFacts.append(contentsOf: found) }
                if isScheduled(day) {
                    scheduled += 1
                    if day >= first.effectiveFrom && !pauses.contains(where: { $0.contains(day) }) { due.append(day); eligible += 1 }
                }
                day = day.adding(days: 1)
            }
            if frequencyChanged {
                var leading = rule.frequency == .interval ? cursor : naturalStart(cursor, rule, periodDays, week)
                while leading < cursor { if isScheduled(leading) { scheduled += 1 }; leading = leading.adding(days:1) }
            }
            let designated = (rule.frequency == .weekly && !rule.weekdays.isEmpty) || (rule.frequency == .monthly && !rule.monthDays.isEmpty)
            let base = rule.measure == .once ? 1 : rule.target, divisor = max(1, scheduled)
            let prorated = (base / divisor) * eligible + ((base % divisor) * eligible + divisor - 1) / divisor
            let target = designated ? eligible : (eligible == 0 ? 0 : max(1, prorated))
            let key = periodKey(cursor, rule: rule, days: periodDays)
            if let found = factsByKey[key] { periodFacts.append(contentsOf: found) }
            periodFacts.sort { $0.0 < $1.0 }
            // Events retain their stored day/period key; evaluate by actual day for policy transitions and weekly history.
            var sum = 0
            for (_, fact) in periodFacts where fact.unit == nil || fact.unit == rule.unit { let added = sum.addingReportingOverflow(fact.delta); guard !added.overflow else { throw CoreError.invalidCommand }; sum = added.partialValue }
            let value = max(0, sum)
            let outcome: HabitOutcome = target == 0 ? .excluded : value >= target ? .complete : (rule.minimum.map { value >= min($0, target) } ?? false) ? .minimum : end <= today ? .missed : .waiting
            let result = HabitPeriodResult(key: key, start: cursor, end: end, rule: rule, dueDays: due, target: target, value: value, outcome: outcome)
            results.append(result)
            if result.met { streak += 1; misses = 0 }
            else if outcome == .missed { misses += 1; if misses >= breakAfter { streak = 0 } }
            cursor = end
        }
        return .init(periods: results, streak: ownerStreak ?? streak, consecutiveMisses: misses)
    }
    /// Window instants are supplied in the active place, and assigned by their START to a Madar day.
    public static func window(rule: HabitRule, civilDay: GregorianDay, place: ActivePlace, prayer: PrayerDay?) -> DateInterval? {
        guard let start = rule.windowStart, let end = rule.windowEnd else { return nil }
        let anchor: Date
        if let name = rule.windowAnchor {
            guard let prayer, prayer.place == place, prayer.day == civilDay else { return nil }
            anchor = prayer.time(for: name)
        } else {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
            var a = civilDay.components; a.hour = start / 60; a.minute = start % 60
            var b = (end <= start ? civilDay.adding(days: 1) : civilDay).components; b.hour = end / 60; b.minute = end % 60
            guard let from = calendar.date(from: a), let to = calendar.date(from: b), from < to else { return nil }
            return .init(start: from, end: to)
        }
        let from = anchor.addingTimeInterval(Double(start) * 60), duration = end > start ? end - start : end - start + 1440
        guard duration > 0 else { return nil }
        return .init(start: from, duration: Double(duration) * 60)
    }
    public static func isNow(_ current: HabitPeriodResult, today: GregorianDay, instant: Date, window: DateInterval?, pauses: [HabitBreak]) -> Bool {
        guard current.dueDays.contains(today), !current.met, !pauses.contains(where: { $0.contains(today) }), let window else { return false }
        return instant >= window.start && instant < window.end
    }
}
