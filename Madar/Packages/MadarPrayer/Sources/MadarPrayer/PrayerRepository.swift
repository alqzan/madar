import Foundation
import SwiftData
import MadarCore
import MadarData

public final class PrayerRepository {
    public let context: ModelContext
    public let settings: SettingsStore
    public let home: ActivePlace
    public let options: PrayerCalculationOptions
    /// RP4: options used for a trip's place. Only the method differs; offsets and Asr school still apply.
    public let tripOptions: PrayerCalculationOptions
    public let placeName: String
    public let pendingDays: Int
    /// Prayer and night rows are read on first use: most callers only need the place, the times or the trip, and reading every
    /// prayer ever logged for that made each habit tap, diary line and reminder plan pay for the whole prayer history.
    /// Writers call `loadRows()` first so a failed read throws instead of looking like an empty history.
    private var loadedLogs: [PrayerLog]?
    private var loadedNights: [QiyamNight]?
    var logs: [PrayerLog] {
        if let loadedLogs { return loadedLogs }
        let rows = ((try? context.fetch(FetchDescriptor<PrayerLog>())) ?? []).filter { $0.mergedInto == nil }
        loadedLogs = rows; return rows
    }
    var nightRows: [QiyamNight] {
        if let loadedNights { return loadedNights }
        let rows = ((try? context.fetch(FetchDescriptor<QiyamNight>())) ?? []).filter { $0.mergedInto == nil }
        loadedNights = rows; return rows
    }
    public func loadRows() throws {
        loadedLogs = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.mergedInto == nil }
        loadedNights = try context.fetch(FetchDescriptor<QiyamNight>()).filter { $0.mergedInto == nil }
    }
    let trips: [Trip]
    public init(context: ModelContext) throws {
        self.context = context; settings = try SettingsStore(context: context)
        let city = try settings.value(for: "core.homeCity").object ?? [:]
        home = try ActivePlace(latitude: city["lat"]?.number ?? 24.7136, longitude: city["lon"]?.number ?? 46.6753, timeZoneID: city["tz"]?.string ?? "Asia/Riyadh")
        placeName = city["name"]?.string ?? "الرياض"
        let offsets = try settings.value(for: "salah.offsets").object ?? [:]
        options = try PrayerCalculationOptions(method: PrayerCalculationMethod(rawValue: settings.value(for: "salah.method").string ?? "") ?? .ummAlQura, hanafiAsr: settings.value(for: "salah.asr").string == "hanafi", highLatitudeRule: PrayerHighLatitudeRule(rawValue: settings.value(for: "salah.highLatitudeRule").string ?? "") ?? .auto, offsets: Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0, Int(offsets[$0.rawValue]?.number ?? 0)) }), hijriSource: HijriSource(rawValue: settings.value(for: "core.hijriSource").string ?? "") ?? .ummAlQura, sightingOffset: Int(settings.value(for: "core.hijriOffset").number ?? 0))
        var forTrip = options
        forTrip.method = PrayerCalculationMethod(rawValue: try settings.value(for: "salah.tripMethod").string ?? "") ?? options.method
        tripOptions = forTrip
        pendingDays = min(14, max(3, Int(try settings.value(for: "salah.pendingDays").number ?? 7)))
        trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed && $0.start != nil }
    }
    public func activeTrip(at date: Date) -> PrayerTrip? {
        guard let row = trips.filter({ $0.start! <= date && ($0.end == nil || date < $0.end!) }).max(by: { $0.start! < $1.start! }), let place = try? ActivePlace(latitude: row.lat, longitude: row.lon, timeZoneID: row.tzID) else { return nil }
        return .init(id: row.id, city: row.city, place: place, start: row.start!, end: row.end)
    }
    /// OR-09: every leg of the journey this trip belongs to, oldest first (journey key = journeyID ?? id).
    public func journeyLegs(of tripID: UUID) -> [(city: String, country: String, start: Date, end: Date?)] {
        guard let leg = trips.first(where: { $0.id == tripID }) else { return [] }
        let key = leg.journeyID ?? leg.id
        return trips.filter { ($0.journeyID ?? $0.id) == key }.sorted { $0.start! < $1.start! }.map { ($0.city, $0.country, $0.start!, $0.end) }
    }
    /// Prayer times for one day and place, worked out once per repository. The options are fixed for the repository's life, and the
    /// snapshot asks for the same day many times (each cell, its window end, the next day's Fajr) for every day since tracking began.
    private struct TimesKey: Hashable { let day: GregorianDay; let place: ActivePlace; let trip: Bool }
    private var timesMemo: [TimesKey: PrayerDay?] = [:]
    func times(_ day: GregorianDay, _ place: ActivePlace, trip: Bool) -> PrayerDay? {
        let key = TimesKey(day: day, place: place, trip: trip)
        if let known = timesMemo[key] { return known }
        let value = PrayerTimesEngine.calculate(day: day, place: place, options: trip ? tripOptions : options)
        timesMemo[key] = .some(value)
        return value
    }
    public func place(at date: Date) -> ActivePlace { activeTrip(at: date)?.place ?? home }
    public func calculationOptions(at date: Date) -> PrayerCalculationOptions {
        activeTrip(at: date) == nil ? options : tripOptions
    }
    public func prayerDay(at date: Date) -> GregorianDay {
        let place = place(at: date); let civil = GregorianDay.containing(date, in: place.timeZone)
        guard let times = times(civil, place, trip: activeTrip(at: date) != nil) else { return civil }
        return date < times.fajr ? civil.adding(days: -1) : civil
    }
    public func occurrence(_ ref: PrayerReference) -> PrayerOccurrence? {
        guard let homeTimes = times(ref.day, home, trip: false) else {
            return tripOccurrence(ref)
        }
        if let trip = tripOccurrence(ref) { return trip }
        let base = homeTimes.time(for: ref.prayer)
        return .init(reference: ref, time: base, place: home, tripID: nil)
    }
    private func tripOccurrence(_ ref: PrayerReference) -> PrayerOccurrence? {
        var earliest: PrayerOccurrence?
        for row in trips {
            guard let place = try? ActivePlace(latitude: row.lat, longitude: row.lon, timeZoneID: row.tzID),
                  let times = times(ref.day, place, trip: true) else { continue }
            let actual = times.time(for: ref.prayer)
            guard let active = activeTrip(at: actual), active.id == row.id else { continue }
            if earliest.map({ actual < $0.time }) ?? true {
                earliest = .init(reference: ref, time: actual, place: place, tripID: row.id)
            }
        }
        return earliest
    }
    public func missedWindowEnd(_ ref: PrayerReference) -> Date? {
        switch ref.prayer {
        case .fajr:
            guard let fajr = occurrence(ref), let times = times(ref.day, fajr.place, trip: fajr.tripID != nil) else { return nil }
            return times.sunrise
        case .dhuhr: return occurrence(.init(day: ref.day, prayer: .asr))?.time
        case .asr: return occurrence(.init(day: ref.day, prayer: .maghrib))?.time
        case .maghrib: return occurrence(.init(day: ref.day, prayer: .isha))?.time
        case .isha: return occurrence(.init(day: ref.day.adding(days: 1), prayer: .fajr))?.time
        }
    }
    public func tracking(at now: Date) throws -> PrayerTracking {
        let value = try settings.value(for: "salah.trackingStart").object ?? [:]
        let start = value["dayKey"]?.string.flatMap { try? GregorianDay($0) } ?? prayerDay(at: now)
        let row = try context.fetch(FetchDescriptor<Setting>()).filter { $0.key == "salah.trackingStart" && $0.mergedInto == nil && $0.deletedAt == nil }.max { $0.updatedAt < $1.updatedAt }
        let first = row.map { prayerDay(at: $0.createdAt) } ?? start
        let edits = Int(value["edits"]?.number ?? 0)
        return .init(day: start, firstRun: first, editAnchor: edits == 1 ? row.map { prayerDay(at: $0.updatedAt) } : nil, edits: edits)
    }
    /// Set only while `snapshot` reads: lookups then use per-day indexes built once, because the snapshot asks for every
    /// day since tracking began and a scan of all rows per cell made opening the prayer room slow with months of history.
    /// Writers (the mutation handler) never set it, so their reads stay live against rows they change.
    private var reading = false
    private lazy var liveLogIndex: [String: PrayerLog] = {
        var index: [String: PrayerLog] = [:]
        for row in logs where row.deletedAt == nil {
            let key = row.dayKey + "|" + row.prayer
            if let existing = index[key], !(existing.updatedAt == row.updatedAt ? existing.id.uuidString > row.id.uuidString : existing.updatedAt < row.updatedAt) { continue }
            index[key] = row
        }
        return index
    }()
    func log(_ ref: PrayerReference, includeDeleted: Bool = false) -> PrayerLog? {
        if reading && !includeDeleted { return liveLogIndex[ref.day.description + "|" + ref.prayer.rawValue] }
        return logs.filter { $0.dayKey == ref.day.description && $0.prayer == ref.prayer.rawValue && (includeDeleted || $0.deletedAt == nil) }.max { a, b in a.updatedAt == b.updatedAt ? a.id.uuidString > b.id.uuidString : a.updatedAt < b.updatedAt }
    }
    public func day(_ day: GregorianDay, now: Date) throws -> PrayerDaySummary {
        try self.day(day, now: now, start: tracking(at: now).day, current: prayerDay(at: now))
    }
    /// `start` and `current` are the same for every day of one snapshot, so the snapshot reads them once.
    private func day(_ day: GregorianDay, now: Date, start: GregorianDay, current: GregorianDay) throws -> PrayerDaySummary {
        return .init(day: day, cells: Prayer.allCases.map { prayer in
            let ref = PrayerReference(day: day, prayer: prayer), occurrence = occurrence(ref)
            let row = log(ref).flatMap { ["jamaah", "alone", "qada"].contains($0.status) ? $0 : nil }
            let due = occurrence.map { $0.time <= now } ?? false
            let expiredPending = due && day.adding(days: pendingDays) <= current
            let status = row.flatMap { PrayerDisplayStatus(rawValue: $0.status) } ?? (due && day >= start ? (expiredPending ? .unconfirmed : .pending) : .future)
            let zone = row.flatMap { TimeZone(identifier: $0.tzID) } ?? occurrence?.place.timeZone ?? home.timeZone
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let friday = prayer == .dhuhr && calendar.component(.weekday, from: day.date(in: zone)) == 6 && row?.shortened != true
            let windowEnded = missedWindowEnd(ref).map { now >= $0 } ?? false
            return PrayerCell(reference: ref, status: status, heart: row?.heart.flatMap(PrayerHeart.init(rawValue:)), time: occurrence == nil ? nil : row?.eventAt ?? occurrence?.time, prayerTime: occurrence?.time, shortened: row?.shortened == true, fridayKind: row?.fridayKind.flatMap(FridayPrayerKind.init(rawValue:)), pairID: row?.pairID, isFriday: friday, canLog: day >= start && (due || occurrence == nil), canMarkMissed: false, canMakeUp: day >= start && windowEnded)
        })
    }
    public func nightRequiresRestore(_ night: GregorianDay) -> Bool {
        nightRows.filter { $0.nightKey == night.description }.max { $0.updatedAt < $1.updatedAt }?.deletedAt != nil
    }
    public func defaultNight(at now: Date) -> GregorianDay {
        let current = prayerDay(at: now)
        if let isha = occurrence(.init(day: current, prayer: .isha)), now >= isha.time { return current }
        return current.adding(days: -1)
    }
    public func snapshot(now: Date) throws -> PrayerSnapshot {
        if loadedLogs == nil || loadedNights == nil { try loadRows() }
        reading = true; defer { reading = false }
        let current = prayerDay(at: now), track = try tracking(at: now)
        let today = try day(current, now: now, start: track.day, current: current)
        // History includes the Hijri month plus the pending window, not fabricated rows.
        let currentHijri = HijriCalendar.date(for: current.date(in: home.timeZone).addingTimeInterval(43200), timeZone: home.timeZone, source: options.hijriSource, sightingOffset: options.sightingOffset)
        var monthStart = current
        for _ in 0..<31 {
            let previous = monthStart.adding(days: -1)
            let hijri = HijriCalendar.date(for: previous.date(in: home.timeZone).addingTimeInterval(43200), timeZone: home.timeZone, source: options.hijriSource, sightingOffset: options.sightingOffset)
            guard hijri.year == currentHijri.year && hijri.month == currentHijri.month else { break }; monthStart = previous
        }
        var all: [PrayerDaySummary] = []; var cursor = track.day
        // Tracking is user-edit limited to 30 days before first run. Bound corrupt/future metadata safely.
        guard cursor <= current else { throw PrayerDomainError.invalidTrackingStart }
        while cursor <= current { all.append(try day(cursor, now: now, start: track.day, current: current)); cursor = cursor.adding(days: 1) }
        let month = all.filter { $0.day >= monthStart }
        // Qada is now a status on a completed prayer, not an outstanding-debt collection.
        let qada: [PrayerQada] = []
        let nights = nightRows.filter { $0.deletedAt == nil }.compactMap { row -> PrayerNight? in guard let day = try? GregorianDay(row.nightKey) else { return nil }; return .init(night: day, rakaat: row.rakaat, witr: row.witr, quranSessionID: row.quranSessionID) }.sorted { $0.night < $1.night }
        let cells = all.flatMap(\.cells)
        let next = (0...1).flatMap { offset in Prayer.allCases.compactMap { occurrence(.init(day: current.adding(days: offset), prayer: $0)) } }.filter { $0.time > now }.min { $0.time < $1.time }
        let active = activeTrip(at: now)
        let unconfirmed = cells.filter { $0.status == .unconfirmed }
        return .init(today: today, history: Array(all.suffix(32).reversed()), tracking: track, pending: cells.filter { $0.status == .pending }.map(\.reference), unconfirmed: unconfirmed.map(\.reference), unconfirmedFridayNoon: Set(unconfirmed.filter(\.isFriday).map(\.reference)), pendingHeart: cells.filter { [.jamaah, .alone, .qada].contains($0.status) && $0.heart == nil }.map(\.reference), statistics: PrayerAnalytics.statistics(month: month, all: all, qada: qada, currentDay: current), qada: qada, nights: nights, nightDefault: defaultNight(at: now), activeTrip: active, next: next, estimated: abs((active?.place ?? home).latitude) > 48, placeName: active?.city ?? placeName, hasTimes: today.cells.contains { $0.time != nil })
    }
}
public enum PrayerAnalytics {
    public static func statistics(month: [PrayerDaySummary], all: [PrayerDaySummary], qada: [PrayerQada], currentDay: GregorianDay) -> PrayerStatistics {
        let cells = month.flatMap(\.cells), counted = cells.filter { [.jamaah, .alone, .qada].contains($0.status) }
        let onTime = counted.filter { [.jamaah, .alone].contains($0.status) }.count
        var heart: [PrayerHeart: Int] = [:]
        for cell in cells { if let value = cell.heart { heart[value, default: 0] += 1 } }
        func streak(_ level: PrayerStreakLevel) -> Int { PrayerStreaks.length(all, level: level, qada: qada, before: currentDay) }
        var commitment: [Prayer: (jamaah: Int, alone: Int, denominator: Int)] = [:]
        for prayer in Prayer.allCases { let rows = counted.filter { $0.reference.prayer == prayer }; commitment[prayer] = (rows.filter { $0.status == .jamaah }.count, rows.filter { $0.status == .alone }.count, rows.count) }
        return .init(onTime: onTime, denominator: counted.count, madeUp: counted.filter { $0.status == .qada }.count, owed: 0, prayerStreak: streak(.onTime), congregationStreak: streak(.congregation), completionStreak: streak(.completion), heartDistribution: heart, last25: Array(all.flatMap(\.cells).filter { $0.status != .future && $0.status != .unrecordedHistory }.suffix(25)), commitment: commitment)
    }
}
