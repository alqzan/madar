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

    /// «لديك ٣ تذكيرات: الورد، القضاء، عادة» — fixed when scheduled, kinds only (§8 item 8).
    public static func digestBody(memberIDs: [String], digits: (Int) -> String) -> String {
        var labels: [String] = []
        for label in memberIDs.compactMap(kindLabel(for:)) where !labels.contains(label) { labels.append(label) }
        let count = memberIDs.count
        let total: String
        switch count {
        case 1: total = "تذكير واحد"
        case 2: total = "تذكيران"
        case 3...10: total = digits(count) + " تذكيرات"
        default: total = digits(count) + " تذكيرًا"
        }
        return labels.isEmpty ? "لديك " + total : "لديك " + total + ": " + labels.joined(separator: "، ")
    }
}
