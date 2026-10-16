import Foundation
import SwiftData
import UserNotifications
import MadarCore
import MadarCommands
import MadarPrayer

/// F02: built-room reminders beside Quran's, all sharing one arbiter, budget and sanctity guard (§8 item 8).
/// Diary kinds (morning intention, «في مثل هذا اليوم», letters) arrive with M3-V12 under the diary lock rules.
@MainActor enum RoomNotificationContent {
    static let roomPrefixes = ["quran.", "digest.", "qada.", "habits.", "nudge."]
    static func isRoomRequest(_ id: String) -> Bool { roomPrefixes.contains { id.hasPrefix($0) } }

    /// Qada while something is owed, and each push habit's window start today (custom, due, unmet, not paused).
    static func candidates(session: AppSession, prayerDays: [PrayerDay], now: Date) throws -> [NotificationCandidate] {
        var result = RoomReminders.qada(days: prayerDays, time: RoomReminders.QadaTime(rawValue: session.string("salah.qadaReminder")) ?? .afterFajr,
                                        owed: try session.prayerSnapshot(at: now).statistics.owed, now: now)
        let service = AppBahwService(session: session, evaluationDate: now), today = service.today
        let place = session.activePlace, civil = GregorianDay.containing(now, in: place.timeZone)
        for reading in try HabitRepository(context: ModelContext(session.container)).readings(at: now) {
            guard reading.reminder == "push", reading.source == nil, !reading.archived, !reading.paused,
                  let current = reading.summary.current, current.target > 0, !current.met, current.dueDays.contains(today) else { continue }
            let start = [civil, civil.adding(days: 1)].lazy.compactMap { day in
                HabitEngine.window(rule: current.rule, civilDay: day, place: place, prayer: prayerDays.first { $0.day == day })?.start
            }.first { $0 > now }
            if let candidate = RoomReminders.habit(id: reading.id, windowStart: start, dayKey: today.description, prayerDays: prayerDays, now: now) {
                result.append(candidate)
            }
        }
        return result
    }

    /// Fixed copy chosen at scheduling time. Whole-app protection keeps every body generic (§8 item 10); RU2: never a prayer-debt count.
    static func content(for candidate: NotificationCandidate, plan: NotificationPlan, session: AppSession, habitNames: [String: String]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent(), id = candidate.id, digits = MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)
        let protected = session.string("core.faceIDLock") == "app"
        content.sound = .default
        content.threadIdentifier = id.split(separator: ".").first.map(String.init).map { $0 + "." + candidate.dayKey } ?? candidate.dayKey
        if id.hasPrefix("quran.") {
            let late = id.hasSuffix(".late")
            content.title = late ? "القرآن، المراجعة" : "القرآن، وردك"
            content.body = late ? "راجع المستحق قبل أن يبعد" : "تابع وردك من الموضع الذي توقفت عنده"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "quran"]
        } else if id.hasPrefix("digest.") {
            content.title = "ملخّص تذكيراتك"
            let members = plan.digestMembers[id] ?? [], kinds = RoomReminders.digestKinds(memberIDs: members)
            content.body = "لديك " + reminderCount(members.count, digits) + (kinds.isEmpty ? "" : ": " + kinds.joined(separator: "، "))
            content.userInfo = ["dayKey": candidate.dayKey, "room": "bahw"]
        } else if id.hasPrefix("qada.") {
            content.title = "القضاء"
            content.body = protected ? "لديك تذكير في مدار" : "حان وقت القضاء. «مَنْ نَسِيَ صَلَاةً فَلْيُصَلِّ إِذَا ذَكَرَهَا»"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "salah"]
        } else if id.hasPrefix("habits.") {
            let habitID = String(id.split(separator: ".").last ?? "")
            content.title = protected ? "مدار" : habitNames[habitID] ?? "عادتك"
            content.body = protected ? "حان وقت عادة" : "بدأ وقتها، وأقلّ القليل يحفظ سلسلتك"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "habits", "habit": habitID]
        } else {
            content.title = "مدار"
            content.body = "افتح مدار ليحدّث تذكيراتك"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "bahw"]
        }
        return content
    }

    static func ledgerKind(_ id: String) -> String {
        if id.hasPrefix("quran.") { return id.hasSuffix(".late") ? "late" : "wird" }
        if id.hasPrefix("digest.") { return "digest" }
        if id.hasPrefix("qada.") { return "qada" }
        if id.hasPrefix("habits.") { return "habit" }
        return "nudge"
    }

    /// Whether a room reminder still matters when it arrives in the foreground; a stale one stays silent.
    static func stillRelevant(_ id: String, session: AppSession, now: Date) throws -> Bool {
        if id.hasPrefix("quran.") || id.hasPrefix("digest.") {
            let value = try AppQuranService(session: session, clock: { now }).snapshot()
            guard id.hasPrefix("quran.") else { return true }
            return id.hasSuffix(".late") ? (session.bool("quran.lateReminder") && value.pages.contains { $0.isDue && !$0.isFar })
                : (session.string("quran.wirdReminder") != "off" && AppQuranService.needsWird(value))
        }
        if id.hasPrefix("qada.") {
            guard session.string("salah.qadaReminder") != "off" else { return false }
            return try session.prayerSnapshot(at: now).statistics.owed > 0
        }
        if id.hasPrefix("habits."), let habitID = UUID(uuidString: String(id.split(separator: ".").last ?? "")) {
            let reading = try HabitRepository(context: ModelContext(session.container)).readings(at: now).first { $0.id == habitID }
            return reading.map { $0.reminder == "push" && !$0.paused && $0.summary.current?.met == false } ?? false
        }
        return false // «افتح مدار» while Madar is open says nothing.
    }

    /// Where a tap lands: the room the reminder speaks for.
    static func open(_ id: String, userInfo: [AnyHashable: Any], session: AppSession) {
        if id.hasPrefix("quran.") { session.selectedTab = "quran" }
        else if id.hasPrefix("qada.") { session.selectedTab = "prayer" }
        else if id.hasPrefix("habits.") {
            session.habitRouteID = (userInfo["habit"] as? String).flatMap(UUID.init(uuidString:))
            session.selectedTab = "foundation"; session.habitsOpen = true
        } else { session.selectedTab = "foundation" }
    }

    /// RU3: the Arabic plural comes from the catalog, the digits from core.numerals.
    static func reminderCount(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        // Interpolation wraps the digits in bidi isolates; a notification body is plain Arabic text, so drop them.
        return String(localized: "notif.reminders", defaultValue: "\(count) \(formatted)", table: "Prayer", locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }
}
