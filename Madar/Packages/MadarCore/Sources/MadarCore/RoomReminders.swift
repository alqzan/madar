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

    /// V12 diary kinds (§8 item 8 ids `notes.<dayKey>.<kind>`). Each falls when the anchor prayer's
    /// sanctity ends; the arbiter applies the shared budget and `notes.dailyCap`. The copy never carries diary text.
    public enum DiaryKind: String, Sendable { case niyya, onThisDay, letter }
    public static func diary(_ kind: DiaryKind, day: PrayerDay, time: QadaTime, prayerDays: [PrayerDay], now: Date) -> NotificationCandidate? {
        guard time != .off else { return nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(time == .afterIsha ? day.isha : day.fajr)
        guard due > now, due <= now.addingTimeInterval(48 * 3600) else { return nil }
        return .init(id: "notes.\(day.day).\(kind.rawValue)", room: .notes, dueAt: due, dayKey: day.day.description)
    }

    /// §7.5 «تنبيه ٨٠٪»: once spending in a category reaches 80% of its limit this cycle, one alert, at most once per
    /// (category, cycle). The request id is stable for the pair, so once it has fallen the ledger keeps it from returning;
    /// `categoryCycleKey` holds the arbiter's in-plan cap. It leaves sanctity like every other reminder (RP3).
    /// `scheduledAt` is the time an earlier pass already planned; keeping it stops each refresh from pushing the alert later.
    public static func limit80(categoryID: UUID, cycleID: UUID, spentMinor: Int, limitMinor: Int, dayKey: String, prayerDays: [PrayerDay], now: Date, scheduledAt: Date? = nil) -> NotificationCandidate? {
        guard limitMinor > 0, spentMinor * 5 >= limitMinor * 4 else { return nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(scheduledAt.flatMap { $0 > now ? $0 : nil } ?? now.addingTimeInterval(60))
        return .init(id: "mal.alert80.\(cycleID.uuidString).\(categoryID.uuidString)", room: .mal, dueAt: due, dayKey: dayKey,
                     categoryCycleKey: "\(categoryID.uuidString):\(cycleID.uuidString)")
    }

    /// F07 / mal.cardDue: noon on the configured civil day, through the same sanctity guard.
    /// Zero days is the due-day cash-shortfall alert; the app supplies only confirmed unpaid statements.
    public static func cardDue(cardID: UUID, dueDay: GregorianDay, amountMinor: Int, daysBefore: Int, timeZone: TimeZone,
                               prayerDays: [PrayerDay], now: Date) -> NotificationCandidate? {
        guard amountMinor > 0, [0, 1, 3].contains(daysBefore) else { return nil }
        let reminder = dueDay.adding(days: -daysBefore)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let proposed = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reminder.date(in: timeZone)) else { return nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(proposed)
        guard due > now, due <= now.addingTimeInterval(48 * 3600) else { return nil }
        return .init(id: "mal.\(daysBefore == 0 ? "cardCash" : "cardDue").\(cardID.uuidString).\(dueDay)", room: .mal, dueAt: due, dayKey: reminder.description)
    }

    /// M5-V15: one quiet balance-check reminder per line and interval. An overdue check is brought forward once;
    /// the shared arbiter still applies the daily budget, quiet hours and prayer sanctity window.
    public static func reconciliation(lineID: UUID, since: GregorianDay, everyDays: Int, timeZone: TimeZone,
                                       prayerDays: [PrayerDay], now: Date, scheduledAt: Date? = nil) -> NotificationCandidate? {
        guard (1...365).contains(everyDays) else { return nil }
        let reminderDay = since.adding(days: everyDays)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let proposed = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reminderDay.date(in: timeZone)) else { return nil }
        let retained = scheduledAt.flatMap { $0 > now ? $0 : nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(retained ?? (proposed > now ? proposed : now.addingTimeInterval(60)))
        guard due > now, due <= now.addingTimeInterval(48 * 3600) else { return nil }
        let dayKey = GregorianDay.containing(due, in: timeZone).description
        return .init(id: "mal.reconcile.\(lineID.uuidString).\(since).\(everyDays)", room: .mal, dueAt: due, dayKey: dayKey)
    }

    /// The kind a request stands for in a digest: named, never its content.
    public static func kindLabel(for id: String) -> String? {
        if id.hasPrefix("quran.") { return id.hasSuffix(".late") ? "المراجعة" : "الورد" }
        if id.hasPrefix("qada.") { return "القضاء" }
        if id.hasPrefix("habits.") { return "عادة" }
        if id.hasPrefix("mal.alert80.") { return "حدود الصرف" }
        if id.hasPrefix("mal.card") { return "سداد البطاقة" }
        if id.hasPrefix("mal.reconcile.") { return "مطابقة الرصيد" }
        if id.hasPrefix("notes.") { return id.hasSuffix(".niyya") ? "النيّة" : id.hasSuffix(".letter") ? "رسالة" : "ذكرى" }
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
