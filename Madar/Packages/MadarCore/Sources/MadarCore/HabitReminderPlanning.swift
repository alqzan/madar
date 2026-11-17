import Foundation

/// Owner, 17 Nov 2026 (ideas 4 and 9): push habit reminders that arrive together are one notification, and a push habit with
/// no window of its own is reminded at the time its user usually logs it. Pure; the app supplies the rows and
/// every result still passes through `SanctityGuard` (inside `RoomReminders.habit`) and the arbiter.
extension RoomReminders {
    /// Reminders closer than this to the first of their cluster become one.
    public static let habitGroupSpan: TimeInterval = 15 * 60
    /// A learned time needs at least this many logged times and reads the newest `learnedTimeSample`.
    public static let learnedTimeMinimumEvents = 3
    public static let learnedTimeSample = 14
    private static let togetherMarker = ".together."

    /// Median minute of the day (0..<1440, in `timeZone`) of the newest `learnedTimeSample` logged times; the mean of the
    /// two middle values (rounded down) for an even count. Nil below `learnedTimeMinimumEvents`.
    public static func learnedHabitMinute(eventTimes: [Date], timeZone: TimeZone) -> Int? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let minutes = eventTimes.sorted(by: >).prefix(learnedTimeSample).map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }.sorted()
        guard minutes.count >= learnedTimeMinimumEvents else { return nil }
        let middle = minutes.count / 2
        return minutes.count % 2 == 1 ? minutes[middle] : (minutes[middle - 1] + minutes[middle]) / 2
    }

    /// The instant of `minute` on the civil `day` in `timeZone`.
    public static func habitLearnedStart(minute: Int, on day: GregorianDay, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var parts = day.components; parts.hour = minute / 60; parts.minute = minute % 60
        return calendar.date(from: parts)
    }

    /// A single-habit reminder id `habits.<day>.<uuid>`; the final alert (`.final.`) and groups are not.
    private static func isPlainHabitReminder(_ id: String) -> Bool {
        let parts = id.split(separator: ".")
        return parts.count == 3 && parts[0] == "habits" && UUID(uuidString: String(parts[2])) != nil
    }

    /// Plain habit reminders of one day whose due times fall within `habitGroupSpan` of the cluster's first become ONE
    /// candidate `habits.<day>.together.<uuid>+<uuid>…`, due at the latest member (every window has opened by then).
    public static func groupHabitReminders(_ candidates: [NotificationCandidate]) -> [NotificationCandidate] {
        let plain = candidates.filter { $0.room == .habits && isPlainHabitReminder($0.id) }
        var consumed = Set<String>(), merged: [NotificationCandidate] = []
        for day in Set(plain.map(\.dayKey)).sorted() {
            let ordered = plain.filter { $0.dayKey == day }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
            var index = 0
            while index < ordered.count {
                var cluster = [ordered[index]]; index += 1
                while index < ordered.count, ordered[index].dueAt.timeIntervalSince(cluster[0].dueAt) <= habitGroupSpan { cluster.append(ordered[index]); index += 1 }
                guard cluster.count >= 2 else { continue }
                let ids = cluster.compactMap { $0.id.split(separator: ".").last.map(String.init) }.sorted()
                cluster.forEach { consumed.insert($0.id) }
                merged.append(.init(id: "habits.\(day)\(togetherMarker)" + ids.joined(separator: "+"), room: .habits, dueAt: cluster.map(\.dueAt).max()!, dayKey: day))
            }
        }
        return candidates.filter { !consumed.contains($0.id) } + merged
    }

    /// The habits a grouped reminder stands for, or nil for any other id.
    public static func groupedHabitIDs(_ id: String) -> [UUID]? {
        guard id.hasPrefix("habits."), let range = id.range(of: togetherMarker) else { return nil }
        let ids = id[range.upperBound...].split(separator: "+").compactMap { UUID(uuidString: String($0)) }
        return ids.count >= 2 ? ids : nil
    }
}
