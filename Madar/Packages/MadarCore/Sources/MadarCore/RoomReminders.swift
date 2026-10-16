import Foundation

/// Room reminder candidates and fixed copy for the built rooms (§8 item 8, §7.2 qada, §7.1 habits).
/// Pure: the app supplies room state; the arbiter then applies sanctity, quiet, budget and digest.
public enum RoomReminders {
    public enum QadaTime: String, Sendable { case afterFajr, afterIsha, off }

    /// One qada reminder per prayer day while something is owed, at the end of the chosen prayer's
    /// sanctity window. Its own `qada.` prefix keeps it apart from the prayer asks under `salah.`.
    public static func qada(days: [PrayerDay], time: QadaTime, owed: Int, now: Date) -> [NotificationCandidate] {
        guard time != .off, owed > 0 else { return [] }
        return days.compactMap { day in
            let proposed = time == .afterIsha ? day.isha : day.fajr
            let due = SanctityGuard(prayerDays: days).clamp(proposed)
            guard due > now, due <= now.addingTimeInterval(48 * 3600) else { return nil }
            return .init(id: "qada.\(day.day)", room: .salah, dueAt: due, dayKey: day.day.description)
        }
    }

    /// §7.1: a gentle habit reminder falls at the start of its window; without a window there is none.
    public static func habit(id: UUID, windowStart: Date?, dayKey: String, prayerDays: [PrayerDay], now: Date) -> NotificationCandidate? {
        guard let windowStart else { return nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(windowStart)
        guard due > now, due <= now.addingTimeInterval(48 * 3600) else { return nil }
        return .init(id: "habits.\(dayKey).\(id.uuidString)", room: .habits, dueAt: due, dayKey: dayKey)
    }

    /// The kind a request stands for in a digest: named, never its content.
    public static func kindLabel(for id: String) -> String? {
        if id.hasPrefix("quran.") { return id.hasSuffix(".late") ? "المراجعة" : "الورد" }
        if id.hasPrefix("qada.") { return "القضاء" }
        if id.hasPrefix("habits.") { return "عادة" }
        return nil
    }

    /// The kinds a digest names, once each in arrival order — never their content (§8 item 8).
    /// The count phrase is the app's catalog plural (RU3), so the engine returns kinds only.
    public static func digestKinds(memberIDs: [String]) -> [String] {
        var labels: [String] = []
        for label in memberIDs.compactMap(kindLabel(for:)) where !labels.contains(label) { labels.append(label) }
        return labels
    }
}
