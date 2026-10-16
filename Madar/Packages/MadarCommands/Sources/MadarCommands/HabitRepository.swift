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
    public let paused: Bool
    public let isNow: Bool
}
@MainActor public struct HabitRepository {
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
    public func readings(at now: Date, includeArchived: Bool = false, liveHealth: [UUID:Int] = [:]) throws -> [HabitReading] {
        let settings = try SettingsStore(context: context), prayers = try PrayerRepository(context: context), place = prayers.place(at: now)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let calendar = MadarCalendarDays(zone: place.timeZone, source: HijriSource(rawValue: (try settings.value(for: "core.hijriSource")).string ?? "ummAlQura") ?? .ummAlQura, offset: Int((try settings.value(for: "core.hijriOffset")).number ?? 0))
        let policies = try context.fetch(FetchDescriptor<HabitPolicy>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let events = try context.fetch(FetchDescriptor<HabitEvent>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let pauses = try context.fetch(FetchDescriptor<HabitPause>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let legacy = try context.fetch(FetchDescriptor<HabitLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.start != nil }
        let habits = try context.fetch(FetchDescriptor<Habit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && (includeArchived || $0.archivedAt == nil) }.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        var result: [HabitReading] = []
        for habit in habits {
            let rules = try policies.filter { $0.habitID == habit.id }.map(Self.rule)
            let epochs=events.filter{$0.habitID==habit.id && $0.calendarSource != nil}.sorted { $0.dayKey == $1.dayKey ? $0.updatedAt < $1.updatedAt : $0.dayKey < $1.dayKey }
            var breaks = try pauses.filter { $0.habitID == habit.id }.map { p -> HabitBreak in
                var until = try p.toDayKey.map(GregorianDay.init)
                if let tripID = p.tripID, let end = trips.first(where: { $0.id == tripID })?.end { until = GregorianDay.containing(end, in: place.timeZone) }
                return .init(from: try GregorianDay(p.fromDayKey), until: until)
            }
            if habit.homeOnly, (try settings.value(for: "bahw.travelFreezesHome")) == .bool(true) {
                breaks += trips.map { .init(from: GregorianDay.containing($0.start!, in: place.timeZone), until: $0.end.map { GregorianDay.containing($0, in: place.timeZone) }) }
            }
            var facts = try events.filter { $0.habitID == habit.id && $0.delta != 0 }.map { HabitFact(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: $0.periodKey, delta: $0.delta, unit: $0.unit) }
            facts += legacy.filter { $0.habitID == habit.id }.map { .init(id: $0.id, day: (try? GregorianDay($0.periodKey)) ?? GregorianDay.containing($0.eventAt, in: TimeZone(identifier: $0.tzID) ?? place.timeZone), periodKey: $0.periodKey, delta: $0.value) }
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
                    facts = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.status == "jamaah" }.map { .init(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: "", delta: 1) }
                    ownerStreak = try prayers.snapshot(now: now).statistics.congregationStreak
                case "review":
                    let snapshot = try QuranRepository(context: context, catalog: QuranResources.catalog()).snapshot(at: now)
                    var seen = Set<String>()
                    facts = snapshot.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }.flatMap { session in
                        session.grades.compactMap { grade in
                            guard seen.insert(session.dayKey.description + ":" + String(grade.page)).inserted else { return nil }
                            return HabitFact(id: StableIdentity.uuid(for: "habit-review:\(session.dayKey):\(grade.page)"), day: session.dayKey, periodKey: "", delta: 1)
                        }
                    }
                    ownerStreak = QuranProgressEngine.streak(activities: snapshot.activities, through: today, restDay: snapshot.restDay).days
                case "diaryLine":
                    let entries = try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.source != "autoPinned" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let chains = DiaryRevisionChains(entries.map { .init(id: $0.id, replaces: $0.source == "revision" ? $0.sourceID.flatMap(UUID.init(uuidString:)) : nil) })
                    facts = try entries.filter { chains.heads.contains($0.id) }.map { .init(id: $0.id, day: try GregorianDay($0.dayKey), periodKey: "", delta: 1) }
                    // Diary has no independent streak counter; no second competing definition is exposed.
                default: continue
                }
            }
            let weekHistory = try HabitWeekHistory.load(context), firstDay = rules.map(\.effectiveFrom).min() ?? today
            let fallbackWeek = try settings.value(for: "core.weekStart").string ?? "saturday"
            let initialWeek = weekHistory.flatMap { h in h.changes.last(where: { $0.day < firstDay.description })?.start ?? h.initial } ?? fallbackWeek
            let legacyWeekChanges = try (weekHistory?.changes ?? []).filter { $0.day >= firstDay.description }.map { HabitWeekChange(day: try GregorianDay($0.day), start: MadarWeekStart(rawValue: $0.start) ?? .saturday) }
            let initialEpoch=epochs.first
            let epochCalendar=MadarCalendarDays(zone:calendar.zone,source:initialEpoch?.calendarSource.flatMap(HijriSource.init(rawValue:)) ?? calendar.source,offset:initialEpoch?.calendarOffset ?? calendar.offset)
            let calendarChanges=try epochs.map { HabitCalendarChange(day:try GregorianDay($0.dayKey),source:$0.calendarSource.flatMap(HijriSource.init(rawValue:)) ?? calendar.source,offset:$0.calendarOffset ?? calendar.offset) }
            let weekChanges=epochs.isEmpty ? legacyWeekChanges : try epochs.map {HabitWeekChange(day:try GregorianDay($0.dayKey),start:$0.weekStart.flatMap(MadarWeekStart.init(rawValue:)) ?? .saturday)}
            let epochWeek=initialEpoch?.weekStart ?? initialWeek
            let summary = try HabitEngine.evaluate(rules: rules, facts: facts, pauses: breaks, today: today, days: epochCalendar,
                weekStart: MadarWeekStart(rawValue: epochWeek) ?? .saturday, weekChanges: weekChanges, calendarChanges:calendarChanges,
                breakAfter: Int((try settings.value(for: "bahw.streakBreakAfter")).number ?? 2), ownerStreak: ownerStreak)
            let civil = GregorianDay.containing(now, in: place.timeZone), options = prayers.activeTrip(at: now) == nil ? prayers.options : prayers.tripOptions
            let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "fajr") ?? .fajr
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
            result.append(.init(id: habit.id, name: habit.name, source: habit.linkedSource, archived: habit.archivedAt != nil, homeOnly: habit.homeOnly, reminder: habit.reminder, summary: summary, paused: breaks.contains { $0.contains(today) }, isNow: summary.current.map { HabitEngine.isNow($0, today: today, instant: now, window: window, pauses: breaks) } ?? false))
        }
        return result
    }
}
