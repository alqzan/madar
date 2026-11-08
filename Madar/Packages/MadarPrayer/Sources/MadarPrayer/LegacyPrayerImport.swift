import Foundation
import MadarCore

/// Owner prayer trial (item 19, dev-only): plans the old Madar backup's `prayerLogs` as native rows (§17).
/// Pure: the caller supplies the home place and the stable-identity function, and inserts the rows in one transaction.
/// Only completed prayers are imported. Old backlog, qada, unperformed, and unrecorded states stay out of the live store.
public enum LegacyPrayerImport {
    public struct LogRow: Equatable, Sendable {
        public let id: UUID, dayKey: String, prayer: Prayer, status: PrayerStoredStatus
        public let heart: PrayerHeart?, eventAt: Date, loggedAt: Date?, fridayKind: FridayPrayerKind?
    }
    public struct Plan: Equatable, Sendable {
        public var logs: [LogRow] = []
        /// The first legacy day: history before it was never kept, so tracking starts there.
        public var trackingStart: GregorianDay?
        /// Raw legacy day records, kept whole (khushu stamps, unknown fields) for ImportLink.unmappedJSON.
        public var archives: [(dayKey: String, json: Data)] = []
        public var counts: [String: Int] = [:]
        public static func == (l: Plan, r: Plan) -> Bool {
            l.logs == r.logs && l.trackingStart == r.trackingStart && l.counts == r.counts
                && l.archives.map(\.dayKey) == r.archives.map(\.dayKey) && l.archives.map(\.json) == r.archives.map(\.json)
        }
    }

    static let names: [String: Prayer] = ["الفجر": .fajr, "الظهر": .dhuhr, "العصر": .asr, "المغرب": .maghrib, "العشاء": .isha]
    /// Legacy KHUSHU_META: 1 شارد · 2 حاضر · 3 خاشع.
    public static func heart(legacy: Any?) -> PrayerHeart? {
        guard let value = legacy as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        switch value.doubleValue { case 1: return .distracted; case 2: return .present; case 3: return .khashi; default: return nil }
    }

    public static func plan(backup: Data, home: ActivePlace, options: PrayerCalculationOptions = .init(), uuid: (String) -> UUID) throws -> Plan {
        var result = Plan()
        func count(_ key: String, _ n: Int = 1) { result.counts[key, default: 0] += n }
        guard let root = try JSONSerialization.jsonObject(with: backup) as? [String: Any],
              let days = root["prayerLogs"] as? [[String: Any]] else { return result }
        var byDay: [GregorianDay: [String: Any]] = [:]
        for row in days {
            guard let text = row["date"] as? String, let day = try? GregorianDay(text) else { count("skipped.day"); continue }
            guard byDay[day] == nil else { count("skipped.duplicateDay"); continue }
            byDay[day] = row
        }
        guard let first = byDay.keys.min(), let last = byDay.keys.max() else { return result }
        result.trackingStart = first
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = home.timeZone
        func millis(_ value: Any?) -> Date? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: value.doubleValue / 1000)
        }
        func safeArchive(_ row: [String: Any], day: GregorianDay) -> Data? {
            var safe = row
            let rawStatuses = row["prayers"] as? [String: Any] ?? [:]
            let completed = rawStatuses.filter { name, raw in
                guard names[name] != nil, let text = raw as? String else { return false }
                let status = LegacyPrayerStatusPreview.preview(text, legacyDay: day, trackingStart: first).status
                return status.map { [.jamaah, .alone].contains($0) } ?? false
            }
            safe["prayers"] = completed
            for key in ["khushu", "prayerUpdatedAt"] {
                if let values = row[key] as? [String: Any] {
                    safe[key] = values.filter { completed[$0.key] != nil }
                }
            }
            return try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys])
        }
        var day = first
        while day <= last {
            defer { day = day.adding(days: 1) }
            guard let times = PrayerTimesEngine.calculate(day: day, place: home, options: options) else { count("skipped.noTimes"); continue }
            let row = byDay[day] ?? [:]
            if row.isEmpty { count("day.absentInsideHistory") }
            else if let json = safeArchive(row, day: day) { result.archives.append((day.description, json)) }
            let statuses = (row["prayers"] as? [String: Any]) ?? [:]
            for key in statuses.keys where names[key] == nil { count("archived.unknownPrayer") }
            let hearts = (row["khushu"] as? [String: Any]) ?? [:], stamps = (row["prayerUpdatedAt"] as? [String: Any]) ?? [:]
            let isFriday = calendar.component(.weekday, from: day.date(in: home.timeZone)) == 6
            for (name, prayer) in names.sorted(by: { Prayer.allCases.firstIndex(of: $0.value)! < Prayer.allCases.firstIndex(of: $1.value)! }) {
                let raw = statuses[name] as? String
                let stamp = millis(stamps[name])
                let status: PrayerStoredStatus
                if let raw, raw != "لم" {
                    let preview = LegacyPrayerStatusPreview.preview(raw, legacyDay: day, trackingStart: first)
                    guard let mapped = preview.status else { count("archived.unknownStatus"); continue }
                    status = mapped
                } else {
                    // Never logged in the old app's own history (or explicitly «لم»): history, not a debt.
                    status = .unrecordedHistory; count(raw == nil ? "unlogged.toHistory" : "lam.toHistory")
                }
                guard [.jamaah, .alone].contains(status) else {
                    count(status == .qada ? "prayer.oldQadaSkipped" : "prayer.unperformedSkipped")
                    continue
                }
                let prayed = [.jamaah, .alone].contains(status)
                let heart = prayed ? heart(legacy: hearts[name]) : nil
                if prayed && hearts[name] != nil && heart == nil { count("archived.unknownHeart") }
                // Friday noon: «منفردة» cannot be Jumu'ah, so it is Dhuhr; a recorded congregation was Jumu'ah.
                var friday: FridayPrayerKind?
                if isFriday && prayer == .dhuhr && status != .unrecordedHistory {
                    if status == .alone { friday = .dhuhr; count("friday.dhuhrFromAlone") } else { friday = .jumuah; count("friday.jumuahByOwner") }
                }
                result.logs.append(LogRow(id: uuid("myDream:PrayerLog:\(day):\(prayer.rawValue)"), dayKey: day.description, prayer: prayer,
                    status: status, heart: heart, eventAt: times.time(for: prayer), loggedAt: status == .unrecordedHistory ? nil : stamp, fridayKind: friday))
                count("status." + status.rawValue)
            }
        }
        return result
    }
}
