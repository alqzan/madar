import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer
import MadarQuran

public struct HabitReading: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let source: String?
    public let archived: Bool
    public let homeOnly: Bool
    public let reminder: String
    public let summary: HabitSummary
    public let firstEffectiveFrom: GregorianDay
    public let paused: Bool
    public let isNow: Bool
    /// Days the habit was done, newest first, each with the diary line linked to it (item 26 «منذ آخر مرة»).
    public var times: [HabitTime] = []
    public var lastTime: HabitTime? { times.first }
    public func refreshed(in readings: [HabitReading]) -> HabitReading? {
        readings.first { $0.id == id }
    }
}
public struct HabitTime: Equatable, Sendable {
    public let day: GregorianDay
    public let entryID: UUID?
}
public struct HabitRepository {
    public let context: ModelContext
    public init(context: ModelContext) { self.context = context }
    static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    static func rule(_ row: HabitPolicy) throws -> HabitRule {
        var r = HabitRule(effectiveFrom: try GregorianDay(row.effectiveFrom))
        r.frequency = HabitFrequency(rawValue: row.frequency) ?? .daily; r.measure = HabitMeasure(rawValue: row.measure) ?? .once
        r.target = row.target ?? 1; r.minimum = row.minimum; r.unit = row.unit
        r.weekdays = (row.weekdays ?? []).compactMap { weekdays.firstIndex(of: $0).map { $0 + 1 } }
        r.restWeekdays = (row.restWeekdays ?? []).compactMap { weekdays.firstIndex(of: $0).map { $0 + 1 } }
        r.monthDays = row.monthDays ?? []; r.hijri = row.monthCalendar == "hijri"; r.yearMonth = row.yearMonth ?? 1; r.yearDay = row.yearDay ?? 1
        r.windowAnchor = row.windowAnchor.flatMap(Prayer.init(rawValue:)); r.windowStart = row.windowStartMin; r.windowEnd = row.windowEndMin
        return r
    }
    static func apply(_ rule: HabitRule, to row: HabitPolicy) {
        row.effectiveFrom = rule.effectiveFrom.description; row.frequency = rule.frequency.rawValue; row.measure = rule.measure.rawValue
        row.unit = rule.unit; row.target = rule.target; row.minimum = rule.minimum
        row.weekdays = rule.weekdays.map { weekdays[$0-1] }; row.restWeekdays = rule.restWeekdays.map { weekdays[$0-1] }
        row.monthDays = rule.monthDays; row.monthCalendar = rule.hijri ? "hijri" : "gregorian"; row.yearMonth = rule.yearMonth; row.yearDay = rule.yearDay
        row.windowAnchor = rule.windowAnchor?.rawValue; row.windowStartMin = rule.windowStart; row.windowEndMin = rule.windowEnd
    }
    static func travelDay(at instant: Date, place: ActivePlace, boundary: DayBoundary, options: PrayerCalculationOptions) -> GregorianDay {
        let civil = GregorianDay.containing(instant, in: place.timeZone)
        guard boundary != .midnight else { return civil }
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: options) }
        return (try? MadarDay.resolve(instant: instant, place: place, boundary: boundary, prayerDays: days).date) ?? civil
    }
    static func travelBreak(start: Date, end: Date?, place: ActivePlace, boundary: DayBoundary, options: PrayerCalculationOptions) -> HabitBreak {
        let from = travelDay(at: start, place: place, boundary: boundary, options: options)
        let returnDay = end.map { travelDay(at: $0, place: place, boundary: boundary, options: options) }
        // Trips use half-open instants, but habits are evaluated in whole day buckets.
        // Keep the travel day frozen when departure and return share one date instead of
        // constructing an empty [day, day) break.
        let until = returnDay == from ? from.adding(days: 1) : returnDay
        return HabitBreak(from: from, until: until)
    }
    public func readings(at now: Date, includeArchived: Bool = false, liveHealth: [UUID:Int] = [:]) throws -> [HabitReading] {
        let settings = try SettingsStore(context: context), prayers = try PrayerRepository(context: context), place = prayers.place(at: now)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "fajr") ?? .fajr
        let calendar = MadarCalendarDays(zone: place.timeZone, source: HijriSource(rawValue: (try settings.value(for: "core.hijriSource")).string ?? "ummAlQura") ?? .ummAlQura, offset: Int((try settings.value(for: "core.hijriOffset")).number ?? 0))
        let policies = try context.fetch(FetchDescriptor<HabitPolicy>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let events = try context.fetch(FetchDescriptor<HabitEvent>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let pauses = try context.fetch(FetchDescriptor<HabitPause>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let legacy = try context.fetch(FetchDescriptor<HabitLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.start != nil }
        let habits = try context.fetch(FetchDescriptor<Habit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && (includeArchived || $0.archivedAt == nil) }.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        // Group the rows once: each habit then reads its own rows instead of scanning every row three or four times.
        let policiesByHabit = Dictionary(grouping: policies, by: \.habitID)
        let eventsByHabit = Dictionary(grouping: events, by: \.habitID)
        let pausesByHabit = Dictionary(grouping: pauses, by: \.habitID)
        let legacyByHabit = Dictionary(grouping: legacy, by: \.habitID)
        let weekHistory = try HabitWeekHistory.load(context)
        // Linked sources do not depend on the habit, so each is read once per call.
        var jamaahCache: (facts: [HabitFact], streak: Int)?
        var reviewCache: (facts: [HabitFact], streak: Int)?
        var readingCache: [HabitFact]?
        var diaryCache: [HabitFact]?
        var wirdCache: (facts: [HabitFact], streak: Int)?
        var result: [HabitReading] = []
        for habit in habits {
            let habitEvents = eventsByHabit[habit.id] ?? []
            let rules = try (policiesByHabit[habit.id] ?? []).map(Self.rule)
            let epochs=habitEvents.filter{$0.calendarSource != nil}.sorted { $0.dayKey == $1.dayKey ? $0.updatedAt < $1.updatedAt : $0.dayKey < $1.dayKey }
            var breaks = try (pausesByHabit[habit.id] ?? []).map { p -> HabitBreak in
                var until = try p.toDayKey.map(GregorianDay.init)
                if let tripID = p.tripID, let trip = trips.first(where: { $0.id == tripID }),
                   let end = trip.end,
                   let tripPlace = try? ActivePlace(latitude: trip.lat, longitude: trip.lon, timeZoneID: trip.tzID) {
                    until = Self.travelDay(at: end, place: tripPlace, boundary: boundary, options: prayers.tripOptions)
                }
                return .init(from: try GregorianDay(p.fromDayKey), until: until)
            }
            if habit.homeOnly, (try settings.value(for: "bahw.travelFreezesHome")) == .bool(true) {
                breaks += trips.filter { !$0.dismissed }.compactMap { trip in
                    guard let start = trip.start,
                          let tripPlace = try? ActivePlace(latitude: trip.lat, longitude: trip.lon, timeZoneID: trip.tzID) else { return nil }
                    return Self.travelBreak(start: start, end: trip.end, place: tripPlace, boundary: boundary, options: prayers.tripOptions)
                }
            }
            var facts = try habitEvents.filter { $0.delta != 0 }.map { HabitFact(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: $0.periodKey, delta: $0.delta, unit: $0.unit) }
            facts += (legacyByHabit[habit.id] ?? []).map { .init(id: $0.id, day: (try? GregorianDay($0.periodKey)) ?? GregorianDay.containing($0.eventAt, in: TimeZone(identifier: $0.tzID) ?? place.timeZone), periodKey: $0.periodKey, delta: $0.value) }
            var ownerStreak: Int? = nil
            if let source = habit.linkedSource {
                if source != "walking" { facts = [] }
                switch source {
                case "walking":
                    facts = facts.map { fact in
                        let unit = rules.filter{$0.effectiveFrom<=fact.day}.max(by:{$0.effectiveFrom<$1.effectiveFrom})?.unit
                        return HabitFact(id:fact.id,day:fact.day,periodKey:"",delta:fact.delta,unit:unit)
                    }
                    if let value=liveHealth[habit.id],let rule=rules.max(by:{$0.effectiveFrom<$1.effectiveFrom}) {facts.append(.init(id:StableIdentity.uuid(for:"live-health:\(habit.id):\(today)"),day:today,periodKey:"",delta:value,unit:rule.unit))}

                case "jamaah":
                    if jamaahCache == nil {
                        jamaahCache = (try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.status == "jamaah" }.map { .init(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: "", delta: 1) },
                                       try prayers.snapshot(now: now).statistics.congregationStreak)
                    }
                    facts = jamaahCache!.facts; ownerStreak = jamaahCache!.streak
                case "review":
                    if reviewCache == nil {
                        let snapshot = try QuranRepository(context: context, catalog: QuranResources.catalog()).snapshot(at: now)
                        var seen = Set<String>()
                        let reviewFacts: [HabitFact] = snapshot.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }.flatMap { session in
                            session.grades.compactMap { grade -> HabitFact? in
                                guard seen.insert(session.dayKey.description + ":" + String(grade.page)).inserted else { return nil }
                                return HabitFact(id: StableIdentity.uuid(for: "habit-review:\(session.dayKey):\(grade.page)"), day: session.dayKey, periodKey: "", delta: 1)
                            }
                        }
                        reviewCache = (reviewFacts, QuranProgressEngine.streak(activities: snapshot.activities, through: today, restDay: snapshot.restDay).days)
                    }
                    facts = reviewCache!.facts; ownerStreak = reviewCache!.streak
                case "reading":
                    // §7.6: a session under 60 active seconds keeps its place but never counts for the habit.
                    // Both units are offered per day; the engine keeps the one the period's rule measures.
                    // Owner, 30 Oct: «فصول» is the third unit, counted from the pages read and the book's outline (a book with no outline adds none).
                    if let cached = readingCache { facts = cached; break }
                    var seconds: [String: Int] = [:], pages: [String: Int] = [:], chapters: [String: Double] = [:]
                    let outlines = Dictionary(try context.fetch(FetchDescriptor<Book>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { ($0.id, ($0.pages, ReadingChapters.chapterCount(tocJSON: $0.tocJSON))) }, uniquingKeysWith: { first, _ in first })
                    for row in try context.fetch(FetchDescriptor<ReadingSession>()) where row.deletedAt == nil && row.mergedInto == nil && row.activeSeconds >= 60 && !row.dayKey.isEmpty {
                        seconds[row.dayKey, default: 0] += row.activeSeconds; pages[row.dayKey, default: 0] += max(0, row.pagesCounted)
                        if let id = row.bookID, let outline = outlines[id], let share = ReadingChapters.chapters(pagesRead: row.pagesCounted, bookPages: outline.0, chapterCount: outline.1) { chapters[row.dayKey, default: 0] += share }
                    }
                    facts = try seconds.keys.sorted().flatMap { key -> [HabitFact] in
                        let day = try GregorianDay(key)
                        return [HabitFact(id: StableIdentity.uuid(for: "habit-reading:\(key):minutes"), day: day, periodKey: "", delta: seconds[key, default: 0] / 60, unit: "minutes"),
                                HabitFact(id: StableIdentity.uuid(for: "habit-reading:\(key):pages"), day: day, periodKey: "", delta: pages[key, default: 0], unit: "pages"),
                                HabitFact(id: StableIdentity.uuid(for: "habit-reading:\(key):chapters"), day: day, periodKey: "", delta: Int(chapters[key, default: 0].rounded(.down)), unit: "chapters")]
                    }
                    readingCache = facts
                case "wird":
                    // Owner, 6 Nov 2026 («عادات التطبيق… والورد»): one time per day on which a new hifz portion was
                    // recorded in the Quran room (a hifz session with its ayahs, not deleted), the Quran's own fact.
                    if wirdCache == nil {
                        let snapshot = try QuranRepository(context: context, catalog: QuranResources.catalog()).snapshot(at: now)
                        let days = Set(snapshot.activities.filter { $0.kind == .hifz && $0.countsForStreak }.map(\.dayKey))
                        wirdCache = (days.sorted().map { HabitFact(id: StableIdentity.uuid(for: "habit-wird:\($0)"), day: $0, periodKey: "", delta: 1) },
                                     QuranProgressEngine.streak(activities: snapshot.activities, through: today, restDay: snapshot.restDay).days)
                    }
                    facts = wirdCache!.facts
                case "diaryLine":
                    if let cached = diaryCache { facts = cached; break }
                    let entries = try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.source != "autoPinned" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let chains = DiaryRevisionChains(entries.map { .init(id: $0.id, replaces: $0.source == "revision" ? $0.sourceID.flatMap(UUID.init(uuidString:)) : nil) })
                    facts = try entries.filter { chains.heads.contains($0.id) }.map { .init(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: "", delta: 1) }
                    diaryCache = facts
                    // Diary has no independent streak counter; no second competing definition is exposed.
                default: continue
                }
            }
            let firstDay = rules.map(\.effectiveFrom).min() ?? today
            let fallbackWeek = try settings.value(for: "core.weekStart").string ?? "saturday"
            let initialWeek = weekHistory.flatMap { h in h.changes.last(where: { $0.day < firstDay.description })?.start ?? h.initial } ?? fallbackWeek
            let legacyWeekChanges = try (weekHistory?.changes ?? []).filter { $0.day >= firstDay.description }.map { HabitWeekChange(day: try GregorianDay($0.day), start: MadarWeekStart(rawValue: $0.start) ?? .saturday) }
            let initialEpoch=epochs.first
            let epochCalendar=MadarCalendarDays(zone:calendar.zone,source:initialEpoch?.calendarSource.flatMap(HijriSource.init(rawValue:)) ?? calendar.source,offset:initialEpoch?.calendarOffset ?? calendar.offset)
            let calendarChanges=try epochs.map { HabitCalendarChange(day:try GregorianDay($0.dayKey),source:$0.calendarSource.flatMap(HijriSource.init(rawValue:)) ?? calendar.source,offset:$0.calendarOffset ?? calendar.offset) }
            let weekChanges=epochs.isEmpty ? legacyWeekChanges : try epochs.map {HabitWeekChange(day:try GregorianDay($0.dayKey),start:$0.weekStart.flatMap(MadarWeekStart.init(rawValue:)) ?? MadarWeekStart(rawValue: initialWeek) ?? .saturday)}
            let epochWeek=initialEpoch?.weekStart ?? initialWeek
            let summary = try HabitEngine.evaluate(rules: rules, facts: facts, pauses: breaks, today: today, days: epochCalendar,
                weekStart: MadarWeekStart(rawValue: epochWeek) ?? .saturday, weekChanges: weekChanges, calendarChanges:calendarChanges,
                breakAfter: Int((try settings.value(for: "bahw.streakBreakAfter")).number ?? 2), ownerStreak: ownerStreak)
            let civil = GregorianDay.containing(now, in: place.timeZone), options = prayers.activeTrip(at: now) == nil ? prayers.options : prayers.tripOptions
            let window = summary.current.flatMap { current in
                [civil.adding(days: -1), civil].compactMap { day -> DateInterval? in
                    let anchor = PrayerTimesEngine.calculate(day: day, place: place, options: options)
                    guard let candidate = HabitEngine.window(rule: current.rule, civilDay: day, place: place, prayer: anchor) else { return nil }
                    let startDay = GregorianDay.containing(candidate.start, in: place.timeZone)
                    let startPrayers = PrayerTimesEngine.calculate(day: startDay, place: place, options: options).map { [$0] } ?? []
                    guard let owned = try? MadarDay.resolve(instant: candidate.start, place: place, boundary: boundary, prayerDays: startPrayers), owned.date == today else { return nil }
                    return candidate
                }.first { now >= $0.start && now < $0.end }
            }
            // A day counts as done when its logged times net above zero (an undo writes the inverse event).
            let links = Dictionary(habitEvents.filter { $0.delta > 0 && $0.entryID != nil }.sorted { $0.updatedAt < $1.updatedAt }.map { ($0.dayKey, $0.entryID!) }, uniquingKeysWith: { _, b in b })
            let net = Dictionary(facts.map { ($0.day, $0.delta) }, uniquingKeysWith: +)
            let times = net.filter { $0.value > 0 && $0.key <= today }.keys.sorted(by: >).map { HabitTime(day: $0, entryID: links[$0.description]) }
            result.append(.init(id: habit.id, name: habit.name, source: habit.linkedSource, archived: habit.archivedAt != nil, homeOnly: habit.homeOnly, reminder: habit.reminder, summary: summary, firstEffectiveFrom: firstDay, paused: breaks.contains { $0.contains(today) }, isNow: summary.current.map { HabitEngine.isNow($0, today: today, instant: now, window: window, pauses: breaks) } ?? false, times: times))
        }
        return result
    }
}
