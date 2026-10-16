import Foundation
import SwiftData
import UserNotifications
import MadarCore
import MadarCommands
import MadarData
import MadarPrayer

/// F02: built-room reminders beside Quran's, all sharing one arbiter, budget and sanctity guard (§8 item 8).
/// M3-V12 adds the diary kinds (morning intention, «في مثل هذا اليوم», a letter whose day came) with fixed copy
/// that never carries diary text, so they stand outside the lock cleanup of `madar.notes.` requests (owner, 15 Oct).
@MainActor enum RoomNotificationContent {
    static let roomPrefixes = ["quran.", "digest.", "qada.", "habits.", "notes.", "nudge."]
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
        return result + (try diaryCandidates(session: session, prayerDays: prayerDays, now: now))
    }

    /// Reads day keys, booleans and letter triggers only; no diary text is read for scheduling.
    static func diaryCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) throws -> [NotificationCandidate] {
        guard session.number("notes.dailyCap") > 0 else { return [] }
        let diary = AppDiaryService(app: session, clock: { now }), today = try diary.diaryDay(), context = ModelContext(session.container)
        let intentions = Set(try context.fetch(FetchDescriptor<Niyya>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })).map(\.dayKey))
        let letters = try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.openedAt == nil }))
        var result: [NotificationCandidate] = []
        for day in prayerDays where day.day >= today {
            if session.bool("notes.morningNiyya"), !intentions.contains(day.day.description),
               let candidate = RoomReminders.diary(.niyya, day: day, time: .afterFajr, prayerDays: prayerDays, now: now) { result.append(candidate) }
            let letterDue = letters.contains { letter in
                letter.state == DiaryLetterState.eligible.rawValue ? day.day == today
                    : letter.state == DiaryLetterState.sealed.rawValue && letter.triggerKind == DiaryLetterTrigger.date.rawValue && letter.triggerValue == day.day.description
            }
            if letterDue, let candidate = RoomReminders.diary(.letter, day: day, time: .afterFajr, prayerDays: prayerDays, now: now) { result.append(candidate) }
        }
        // «في مثل هذا اليوم» only when today truly has a memory on its date, not an echo or a random page.
        let time = RoomReminders.QadaTime(rawValue: session.string("notes.onThisDay")) ?? .afterIsha
        if time != .off, let day = prayerDays.first(where: { $0.day == today }),
           [.gregorian, .hijri].contains(diary.memorySelection(facts: try diary.memoryFacts(), today: today).match),
           let candidate = RoomReminders.diary(.onThisDay, day: day, time: time, prayerDays: prayerDays, now: now) { result.append(candidate) }
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
        } else if id.hasPrefix("notes.") {
            // §8 item 10 matrix copy; under the whole-app lock the owner's generic line (15 Oct). Never diary text.
            content.title = protected ? "مدار" : "المذكرات"
            content.body = protected ? "لديك رسالة في مدار"
                : id.hasSuffix(".niyya") ? "ما نيّتك لهذا اليوم؟ سطر واحد يكفي"
                : id.hasSuffix(".letter") ? "وصلتك رسالة من ماضيك" : "عندك ذكرى من هذا اليوم"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "notes"]
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
        if id.hasPrefix("notes.") { return id.hasSuffix(".niyya") ? "niyya" : id.hasSuffix(".letter") ? "letter" : "onThisDay" }
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
        if id.hasPrefix("notes.") {
            guard session.number("notes.dailyCap") > 0 else { return false }
            let dayKey = id.split(separator: ".").dropFirst().first.map(String.init) ?? ""
            if id.hasSuffix(".niyya") {
                guard session.bool("notes.morningNiyya") else { return false }
                return try ModelContext(session.container).fetchCount(FetchDescriptor<Niyya>(predicate: #Predicate { $0.dayKey == dayKey && $0.deletedAt == nil })) == 0
            }
            return id.hasSuffix(".letter") || session.string("notes.onThisDay") != "off"
        }
        return false // «افتح مدار» while Madar is open says nothing.
    }

    /// Where a tap lands: the room the reminder speaks for.
    static func open(_ id: String, userInfo: [AnyHashable: Any], session: AppSession) {
        if id.hasPrefix("quran.") { session.selectedTab = "quran" }
        else if id.hasPrefix("qada.") { session.selectedTab = "prayer" }
        else if id.hasPrefix("notes.") { session.open(URL(string: id.hasSuffix(".onThisDay") ? "madar://notes" : "madar://notes/today")!) }
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
