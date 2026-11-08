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
    static let roomPrefixes = ["quran.", "digest.", "qada.", "habits.", "notes.", "nudge.", "mal.alert80.", "mal.cardDue.", "mal.cardCash.", "mal.billDue.", "mal.reconcile.", "mal.zakat."]
    static func isRoomRequest(_ id: String) -> Bool { roomPrefixes.contains { id.hasPrefix($0) } }

    /// Push habit window starts today (custom, due, unmet, not paused).
    static func candidates(session: AppSession, prayerDays: [PrayerDay], now: Date) async throws -> [NotificationCandidate] {
        var result: [NotificationCandidate] = []
        let service = AppBahwService(session: session, evaluationDate: now), today = service.today
        let place = try PrayerRepository(context: ModelContext(session.container)).place(at: now)
        let civil = GregorianDay.containing(now, in: place.timeZone)
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
        // Each family may read a whole room on the main thread: yield between them so a tap is never held behind all of them.
        result += try diaryCandidates(session: session, prayerDays: prayerDays, now: now); await Task.yield()
        result += limitCandidates(session: session, prayerDays: prayerDays, now: now); await Task.yield()
        result += cardCandidates(session: session, prayerDays: prayerDays, now: now); await Task.yield()
        result += billCandidates(session: session, prayerDays: prayerDays, now: now); await Task.yield()
        result += reconciliationCandidates(session: session, prayerDays: prayerDays, now: now); await Task.yield()
        return result + zakatCandidates(session: session, now: now)
    }

    /// Builds two upcoming amount-free requests from the saved hawl preference. Each has its own
    /// future prayer days so the same sanctity guard can inspect the actual scheduled window.
    /// While the app is locked, only already-published request metadata may be used; ZakatProfile
    /// stays behind the app's biometric boundary.
    static func zakatCandidates(session: AppSession, now: Date) -> [NotificationCandidate] {
        let lead = session.string("mal.zakatReminder")
        guard let leadDays = zakatLeadDays(lead) else { return [] }
        guard session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized else {
            return zakatCandidatesFromLedger(session: session, lead: lead, now: now)
        }
        guard let key = zakatHawlKey(session: session),
              let hawl = MoneyHawl.read(key, at: now, app: session),
              let repository = try? PrayerRepository(context: ModelContext(session.container)) else { return [] }
        let place = repository.place(at: now), options = repository.calculationOptions(at: now)
        return [hawl.anniversary, hawl.followingAnniversary].compactMap { anniversary in
            let reminderDay = anniversary.adding(days: -leadDays)
            let relevantDays = (-1...2).compactMap { offset in
                PrayerTimesEngine.calculate(day: reminderDay.adding(days: offset), place: place, options: options)
            }
            return RoomReminders.zakat(anniversary: anniversary, lead: lead, timeZone: place.timeZone,
                                       prayerDays: relevantDays, now: now)
        }
    }

    /// Reuses only future, live requests that were previously published while authorized.
    /// This lets the arbiter preserve them under the lock without fetching protected money rows.
    private static func zakatCandidatesFromLedger(session: AppSession, lead: String, now: Date) -> [NotificationCandidate] {
        guard zakatLeadDays(lead) != nil,
              let rows = try? ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>()) else { return [] }
        let candidates = rows.compactMap { row -> NotificationCandidate? in
            guard row.deletedAt == nil, row.mergedInto == nil, row.state == "submitted",
                  row.room == "mal", row.kind == "zakat", row.requestClass == "room",
                  row.scheduledFor > now, (try? GregorianDay(row.dayKey)) != nil else { return nil }
            let parts = row.requestID.split(separator: ".").map(String.init)
            guard parts.count == 4, parts[0] == "mal", parts[1] == "zakat", parts[2] == lead,
                  (try? GregorianDay(parts[3])) != nil else { return nil }
            return .init(id: row.requestID, room: .mal, kind: .annualReminder,
                         dueAt: row.scheduledFor, dayKey: row.dayKey)
        }
        return Dictionary(grouping: candidates, by: \.id).compactMap { _, values in
            values.max { $0.dueAt < $1.dueAt }
        }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
    }

    private static func zakatLeadDays(_ lead: String) -> Int? {
        switch lead { case "1day": 1; case "1week": 7; case "1month": 30; default: nil }
    }

    /// Uses only the saved hawl-date field so scheduling continues under the app lock.
    /// It does not calculate balances, and notification copy stays generic.
    private static func zakatHawlKey(session: AppSession) -> String? {
        let profiles = (try? ModelContext(session.container).fetch(FetchDescriptor<ZakatProfile>())) ?? []
        return profiles.filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.id.uuidString < $1.id.uuidString }.first?.hawlStartHijri
    }

    /// The planner needs the future prayer windows too; current-day calculations remain the source
    /// for prayer asks, reconciliation and Live Activities.
    static func planningPrayerDays(session: AppSession, candidates: [NotificationCandidate], current: [PrayerDay], now: Date) -> [PrayerDay] {
        let annual = candidates.filter { $0.kind == .annualReminder && $0.id.hasPrefix("mal.zakat.") }
        guard !annual.isEmpty, let repository = try? PrayerRepository(context: ModelContext(session.container)) else { return current }
        let place = repository.place(at: now), options = repository.calculationOptions(at: now)
        var byDay = Dictionary(uniqueKeysWithValues: current.map { ($0.day, $0) })
        for candidate in annual {
            let civil = GregorianDay.containing(candidate.dueAt, in: place.timeZone)
            for offset in -1...2 {
                if let day = PrayerTimesEngine.calculate(day: civil.adding(days: offset), place: place, options: options) { byDay[day.day] = day }
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    static func cardCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) -> [NotificationCandidate] {
        guard session.string("mal.cardDue") != "off", let reading = MoneyReadingCache.read(session, now, \.cards, { try AppMoneyService(app: session).loadCards(at: now) }) else { return [] }
        let lead = session.string("mal.cardDue") == "1day" ? 1 : 3
        return reading.dues.filter { $0.cardID != nil }.flatMap { due -> [NotificationCandidate] in
            [lead, due.cashAfterMinor < 0 ? 0 : nil].compactMap { before -> NotificationCandidate? in
                guard let before, let card = due.cardID,
                      let candidate = RoomReminders.cardDue(cardID: card, dueDay: due.day, amountMinor: due.amountMinor, daysBefore: before, timeZone: session.activePlace.timeZone, prayerDays: prayerDays, now: now),
                      let key = try? DiaryLineRenderer.today(context: ModelContext(session.container), now: candidate.dueAt).description else { return nil }
                return .init(id: candidate.id, room: .mal, dueAt: candidate.dueAt, dayKey: key)
            }
        }
    }

    /// Bills and subscriptions: a reminder at the lead set in «تذكير سداد البطاقة» and another on the due day, amount-free.
    static func billCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) -> [NotificationCandidate] {
        guard session.string("mal.cardDue") != "off", let reading = MoneyReadingCache.read(session, now, \.obligations, { try AppMoneyService(app: session).loadObligations() }) else { return [] }
        let lead = session.string("mal.cardDue") == "1day" ? 1 : 3
        return (reading.bills + reading.subscriptions).filter { $0.obligationID != nil }.flatMap { due -> [NotificationCandidate] in
            [lead, 0].compactMap { before -> NotificationCandidate? in
                guard let id = due.obligationID,
                      let candidate = RoomReminders.billDue(billID: id, dueDay: due.due, daysBefore: before, timeZone: session.activePlace.timeZone, prayerDays: prayerDays, now: now),
                      let key = try? DiaryLineRenderer.today(context: ModelContext(session.container), now: candidate.dueAt).description else { return nil }
                return .init(id: candidate.id, room: .mal, dueAt: candidate.dueAt, dayKey: key)
            }
        }
    }

    /// M5-V10 «تنبيه ٨٠٪»: one request per category at 80% of its limit this cycle (`mal.alert80`, default on).
    /// The money reading needs the store unlocked; while it is not, no alert is planned rather than a guessed one.
    static func limitCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) -> [NotificationCandidate] {
        guard session.bool("mal.alert80"), let reading = MoneyReadingCache.read(session, now, \.categories, { try AppMoneyService(app: session).loadCategories() }), let cycle = reading.cycleID else { return [] }
        let dayKey = (try? DiaryLineRenderer.today(context: ModelContext(session.container), now: now))?.description ?? GregorianDay.containing(now, in: session.activePlace.timeZone).description
        let planned = (try? ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>()))?.filter { $0.deletedAt == nil && $0.state == "submitted" && $0.requestID.hasPrefix("mal.alert80.") } ?? []
        return reading.shelves.compactMap { shelf in
            let id = "mal.alert80.\(cycle.uuidString).\(shelf.id.uuidString)"
            return RoomReminders.limit80(categoryID: shelf.id, cycleID: cycle, spentMinor: shelf.spentMinor, limitMinor: shelf.limitMinor, dayKey: dayKey, prayerDays: prayerDays, now: now,
                                         scheduledAt: planned.filter { $0.requestID == id }.map(\.scheduledFor).max())
        }
    }

    /// One generic reminder for the oldest account/card/installment due for review; never exposes balances or provider names.
    static func reconciliationCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) -> [NotificationCandidate] {
        let interval = Int(session.number("mal.reconcileEveryDays"))
        guard (1...365).contains(interval), let reading = MoneyReadingCache.read(session, now, \.reconcile, { try AppMoneyService(app: session).loadReconcile(at: now) }) else { return [] }
        let context = ModelContext(session.container)
        let planned = (try? context.fetch(FetchDescriptor<NotificationLedger>()))?.filter {
            $0.deletedAt == nil && $0.state == "submitted" && $0.requestID.hasPrefix("mal.reconcile.")
        } ?? []
        return reading.rows.compactMap { row in
            guard let since = row.since else { return nil }
            let id = "mal.reconcile.\(row.id.uuidString).\(since).\(interval)"
            return RoomReminders.reconciliation(lineID: row.id, since: since, everyDays: interval,
                timeZone: session.activePlace.timeZone, prayerDays: prayerDays, now: now,
                scheduledAt: planned.first { $0.requestID == id }?.scheduledFor)
        }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }.prefix(1).map { $0 }
    }

    /// Reads day keys, booleans and letter triggers only; no diary text is read for scheduling.
    static func diaryCandidates(session: AppSession, prayerDays: [PrayerDay], now: Date) throws -> [NotificationCandidate] {
        guard session.number("notes.dailyCap") > 0 else { return [] }
        let diary = AppDiaryService(app: session, clock: { now })
        let today: GregorianDay
        do { today = try diary.diaryDay() }
        catch let error as CoreError {
            // A polar day has no prayer boundary to anchor the shared day. Keep the
            // room's reminders quiet rather than failing the whole notification refresh.
            if error == .missingPrayerTimes { return [] }
            throw error
        }
        let context = ModelContext(session.container)
        let intentions = Set(try context.fetch(FetchDescriptor<Niyya>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })).map(\.dayKey))
        let letters = try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.openedAt == nil }))
        var result: [NotificationCandidate] = []
        for day in prayerDays where day.day >= today {
            let dayKey = day.day.description
            if session.bool("notes.morningNiyya"), !intentions.contains(day.day.description),
               let candidate = RoomReminders.diary(.niyya, day: day, time: .afterFajr, prayerDays: prayerDays, now: now) { result.append(candidate) }
            // The day's line: one reminder after Isha while nothing is written for that day; it is dropped at delivery if a line arrives first.
            if session.bool("notes.eveningLine"),
               try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.dayKey == dayKey && $0.deletedAt == nil && $0.mergedInto == nil })) == 0,
               let candidate = RoomReminders.diary(.line, day: day, time: .afterIsha, prayerDays: prayerDays, now: now) { result.append(candidate) }
            let letterDue = letters.contains { letter in
                letter.state == DiaryLetterState.eligible.rawValue ? day.day == today
                    : letter.state == DiaryLetterState.sealed.rawValue && letter.triggerKind == DiaryLetterTrigger.date.rawValue && letter.triggerValue == day.day.description
            }
            if letterDue, let candidate = RoomReminders.diary(.letter, day: day, time: .afterFajr, prayerDays: prayerDays, now: now) { result.append(candidate) }
        }
        // «في مثل هذا اليوم» only when today truly has a memory on its date, not an echo or a random page.
        let time = RoomReminders.PrayerReminderTime(rawValue: session.string("notes.onThisDay")) ?? .afterIsha
        if time != .off, let day = prayerDays.first(where: { $0.day == today }),
           [.gregorian, .hijri].contains(diary.memorySelection(facts: try diary.memoryFacts(), today: today).match),
           let candidate = RoomReminders.diary(.onThisDay, day: day, time: time, prayerDays: prayerDays, now: now) { result.append(candidate) }
        return result
    }

    static func content(for candidate: NotificationCandidate, plan: NotificationPlan, session: AppSession, habitNames: [String: String]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent(), id = candidate.id, digits = MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)
        let protected = session.string("core.faceIDLock") == "app"
        content.sound = .default
        content.threadIdentifier = id.split(separator: ".").first.map(String.init).map { $0 + "." + candidate.dayKey } ?? candidate.dayKey
        if id.hasPrefix("quran.") {
            let late = id.hasSuffix(".late")
            content.title = protected ? "مدار" : late ? QuranReminderCopy.lateTitle : QuranReminderCopy.title
            content.body = protected ? "لديك تذكير في مدار" : late ? NudgeWording.body(.quranReview, dayKey: candidate.dayKey) : NudgeWording.body(.quranWird, dayKey: candidate.dayKey)
            content.userInfo = ["dayKey": candidate.dayKey, "room": "quran"]
        } else if id.hasPrefix("digest.") {
            // Under whole-app protection the digest names no room kinds on the lock screen.
            content.title = protected ? "مدار" : "ملخّص تذكيراتك"
            let members = plan.digestMembers[id] ?? [], kinds = protected ? [] : RoomReminders.digestKinds(memberIDs: members)
            content.body = "لديك " + reminderCount(members.count, digits) + (protected ? " في مدار" : kinds.isEmpty ? "" : ": " + kinds.joined(separator: "، "))
            content.userInfo = ["dayKey": candidate.dayKey, "room": "bahw"]
        } else if id.hasPrefix("habits.") {
            let habitID = String(id.split(separator: ".").last ?? "")
            content.title = protected ? "مدار" : habitNames[habitID] ?? "عادتك"
            // Never promise to keep a streak that does not exist: a first step starts one.
            let streak = protected ? 0 : ((try? HabitRepository(context: ModelContext(session.container)).readings(at: Date()))?.first { $0.id.uuidString == habitID }?.summary.streak ?? 0)
            content.body = protected ? "حان وقت عادة" : NudgeWording.body(streak > 0 ? .habitKeepStreak : .habitFirstStep, dayKey: candidate.dayKey)
            content.userInfo = ["dayKey": candidate.dayKey, "room": "habits", "habit": habitID]
        } else if id.hasPrefix("notes.") {
            // §8 item 10 matrix copy; under the whole-app lock the owner's generic line (15 Oct). Never diary text.
            content.title = protected ? "مدار" : "المذكرات"
            content.body = protected ? "لديك رسالة في مدار"
                : id.hasSuffix(".niyya") ? NudgeWording.body(.diaryNiyya, dayKey: candidate.dayKey)
                : id.hasSuffix(".line") ? NudgeWording.body(.diaryLine, dayKey: candidate.dayKey)
                : id.hasSuffix(".letter") ? "وصلتك رسالة من ماضيك" : "عندك ذكرى من هذا اليوم"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "notes"]
        } else if id.hasPrefix("mal.card") {
            // Always amount-free, including core.hideMoneyOutside's default and whole-app protection.
            content.title = protected ? "مدار" : "سداد البطاقة"
            content.body = protected ? "لديك تنبيه في مدار" : id.hasPrefix("mal.cardCash.") ? "راجع سداد بطاقتك اليوم؛ النقد الحالي لا يغطي الالتزامات المعروفة" : "موعد سداد بطاقتك " + (session.string("mal.cardDue") == "1day" ? "غدًا" : "بعد ثلاثة أيام") + "؛ راجع الكشف والنقد المتاح"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "mal"]
        } else if id.hasPrefix("mal.billDue.") {
            content.title = protected ? "مدار" : "موعد فاتورة"
            content.body = protected ? "لديك تنبيه في مدار" : id.hasSuffix(".0") ? "عندك فاتورة أو اشتراك يستحق اليوم" : "عندك فاتورة أو اشتراك يستحق قريبًا"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "mal"]
        } else if id.hasPrefix("mal.alert80.") {
            // RU2: notifications stay amount-free even when amounts are visible inside the app.
            // Owner, 26 Oct: name the category and the 80% line, never an amount.
            let categoryID = String(id.split(separator: ".").last ?? "")
            let category = protected ? nil : (try? AppMoneyService(app: session).loadCategories())?.shelves.first { $0.id.uuidString == categoryID }?.name
            content.title = protected ? "مدار" : "حدود الصرف"
            content.body = protected ? "لديك تنبيه في مدار" : category.map { "بلغت " + digits.string(80) + "٪ من حد «\($0)» لهذه الدورة" } ?? "بلغ أحد تصنيفاتك " + digits.string(80) + "٪ من حدّه لهذه الدورة"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "mal"]
        } else if id.hasPrefix("mal.reconcile.") {
            content.title = protected ? "مدار" : "مطابقة الرصيد"
            content.body = protected ? "حان وقت المراجعة" : "راجع أرصدة حساباتك والتزاماتك؛ دقيقة واحدة تكفي"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "mal"]
        } else if id.hasPrefix("mal.zakat.") {
            content.title = protected ? "مدار" : "الزكاة"
            content.body = protected ? "لديك تذكير في مدار" : "يحين موعد الحساب السنوي الذي اخترته " + zakatWhen(id)
            content.userInfo = ["dayKey": candidate.dayKey, "room": "mal"]
        } else {
            content.title = "مدار"
            content.body = "افتح مدار ليحدّث تذكيراتك"
            content.userInfo = ["dayKey": candidate.dayKey, "room": "bahw"]
        }
        return content
    }

    /// «mal.zakat.<lead>.<day>»: how far off the anniversary is, in words (never a digit beside an amount-free reminder).
    private static func zakatWhen(_ id: String) -> String {
        switch id.split(separator: ".").dropFirst(2).first.map(String.init) { case "1day": "غدًا"; case "1week": "بعد أسبوع"; case "1month": "بعد نحو شهر"; default: "قريبًا" }
    }

    static func ledgerKind(_ id: String) -> String {
        if id.hasPrefix("quran.") { return id.hasSuffix(".late") ? "late" : "wird" }
        if id.hasPrefix("digest.") { return "digest" }
        if id.hasPrefix("qada.") { return "qada" }
        if id.hasPrefix("habits.") { return "habit" }
        if id.hasPrefix("mal.alert80.") { return "alert80" }
        if id.hasPrefix("mal.card") { return id.hasPrefix("mal.cardCash.") ? "cardCash" : "cardDue" }
        if id.hasPrefix("mal.billDue.") { return "billDue" }
        if id.hasPrefix("mal.zakat.") { return "zakat" }
        if id.hasPrefix("mal.reconcile.") { return "reconciliation" }
        if id.hasPrefix("notes.") { return id.hasSuffix(".niyya") ? "niyya" : id.hasSuffix(".line") ? "line" : id.hasSuffix(".letter") ? "letter" : "onThisDay" }
        return "nudge"
    }

    /// Whether a room reminder still matters when it arrives in the foreground; a stale one stays silent.
    static func stillRelevant(_ id: String, session: AppSession, now: Date) throws -> Bool {
        // Decides whether a reminder about to show is still true: always from live rows, never from the planning cache.
        MoneyReadingCache.liveReads += 1; defer { MoneyReadingCache.liveReads -= 1 }
        if id.hasPrefix("quran.") || id.hasPrefix("digest.") {
            let value = try AppQuranService(session: session, clock: { now }).snapshot()
            guard id.hasPrefix("quran.") else { return true }
            return id.hasSuffix(".late") ? (session.bool("quran.lateReminder") && value.pages.contains { $0.isDue && !$0.isFar })
                : (session.string("quran.wirdReminder") != "off" && AppQuranService.needsWird(value))
        }
        if id.hasPrefix("qada.") {
            return false
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
            if id.hasSuffix(".line") {
                guard session.bool("notes.eveningLine") else { return false }
                return try ModelContext(session.container).fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.dayKey == dayKey && $0.deletedAt == nil && $0.mergedInto == nil })) == 0
            }
            return id.hasSuffix(".letter") || session.string("notes.onThisDay") != "off"
        }
        if id.hasPrefix("mal.card") {
            guard session.string("mal.cardDue") != "off", let cardID = id.split(separator: ".").dropFirst(2).first.flatMap({ UUID(uuidString: String($0)) }),
                  let reading = try? AppMoneyService(app: session).loadCards(at: now),
                  let due = reading.dues.first(where: { $0.cardID == cardID && $0.day.description == id.split(separator: ".").last.map(String.init) }) else { return false }
            return due.amountMinor > 0 && (!id.hasPrefix("mal.cardCash.") || due.cashAfterMinor < 0)
        }
        if id.hasPrefix("mal.billDue.") {
            let parts = id.split(separator: ".")
            guard session.string("mal.cardDue") != "off", parts.count == 5, let billID = UUID(uuidString: String(parts[2])),
                  let reading = try? AppMoneyService(app: session).loadObligations() else { return false }
            return (reading.bills + reading.subscriptions).contains { $0.obligationID == billID && $0.due.description == String(parts[3]) }
        }
        if id.hasPrefix("mal.reconcile.") {
            let repository = try PrayerRepository(context: ModelContext(session.container))
            let place = repository.place(at: now), firstDay = repository.prayerDay(at: now), options = repository.calculationOptions(at: now)
            let days = (0..<4).compactMap { PrayerTimesEngine.calculate(day: firstDay.adding(days: $0), place: place, options: options) }
            let candidates = reconciliationCandidates(session: session, prayerDays: days, now: now)
            return candidates.contains { $0.id == id }
        }
        if id.hasPrefix("mal.zakat.") {
            let parts = id.split(separator: ".").map(String.init)
            guard parts.count == 4, let leadDays = zakatLeadDays(parts[2]),
                  session.string("mal.zakatReminder") == parts[2],
                  let anniversary = try? GregorianDay(parts[3]) else { return false }
            guard session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized else {
                let today = GregorianDay.containing(now, in: session.activePlace.timeZone)
                let rows = try ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>())
                return rows.contains { row in
                    row.deletedAt == nil && row.mergedInto == nil && row.state == "submitted"
                        && row.room == "mal" && row.kind == "zakat" && row.requestClass == "room"
                        && row.requestID == id && row.dayKey == today.description
                }
            }
            guard let key = zakatHawlKey(session: session),
                  let hawl = MoneyHawl.read(key, at: now, app: session),
                  [hawl.anniversary, hawl.followingAnniversary].contains(anniversary) else { return false }
            let reminderDay = anniversary.adding(days: -leadDays)
            return GregorianDay.containing(now, in: session.activePlace.timeZone) == reminderDay
        }
        if id.hasPrefix("mal.alert80.") {
            // Reuse the same cycle/category threshold as planning. A raised limit, refund,
            // removal or closed cycle can make an already queued alert obsolete.
            return limitCandidates(session: session, prayerDays: [], now: now).contains { $0.id == id }
        }
        return false // «افتح مدار» while Madar is open says nothing.
    }

    /// Where a tap lands: the room the reminder speaks for.
    static func open(_ id: String, userInfo: [AnyHashable: Any], session: AppSession) {
        if id.hasPrefix("quran.") {
            let sessionKind = id.hasSuffix(".late") ? "review" : "wird"
            session.open(URL(string: "madar://quran/session/\(sessionKind)")!)
        }
        else if id.hasPrefix("qada.") { session.selectedTab = "prayer" }
        else if id.hasPrefix("mal.cardDue.") || id.hasPrefix("mal.cardCash.") {
            let components = id.split(separator: ".")
            if components.count == 4, let cardID = UUID(uuidString: String(components[2])) {
                let tab = id.hasPrefix("mal.cardCash.") ? "cash" : "calendar"
                session.open(URL(string: "madar://mal/card/\(cardID.uuidString)?tab=\(tab)")!)
            } else { session.selectedTab = "money" }
        }
        else if id.hasPrefix("mal.billDue.") { session.selectedTab = "money" }
        else if id.hasPrefix("mal.alert80.") { session.open(URL(string: "madar://mal/categories")!) }
        else if id.hasPrefix("mal.reconcile.") { session.open(URL(string: "madar://mal/reconcile")!) }
        else if id.hasPrefix("mal.zakat.") { session.open(URL(string: "madar://mal/zakat")!) }
        else if id.hasPrefix("notes.") {
            if id.hasSuffix(".letter") {
                session.open(URL(string: "madar://notes/letters")!)
            } else if let rawDay = userInfo["dayKey"] as? String, (try? GregorianDay(rawDay)) != nil {
                session.open(URL(string: "madar://notes/day/\(rawDay)")!)
            } else {
                session.open(URL(string: "madar://notes/today")!)
            }
        }
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

/// The Quran reminders' fixed copy, shared by the notification and its preview in «التذكير والودجات» so the preview never promises other words.
enum QuranReminderCopy {
    static let title = "وردك ينتظرك", body = "دقائق مع القرآن تكفي، تابع من حيث توقفت"
    static let lateTitle = "مراجعة اليوم", lateBody = "أوجه تنتظر مراجعتك قبل أن تبعد عنك"
}

/// Money readings for reminder planning, kept while the money tables, the money settings, the day and the store are unchanged.
/// Owner 7 Nov 2026 («أول ما أفتح التطبيق يعلق»): every refresh rebuilt the whole money home four times on the main thread, about
/// two seconds with real data, after each habit tap, Quran save and return to the app. The key is a cheap fingerprint (row count and newest
/// `updatedAt` of each money table, one row fetched per table), so any write, through a command or not, is seen. Ledger rows stay live,
/// and the foreground «still relevant» checks keep reading live.
@MainActor enum MoneyReadingCache {
    struct Key: Equatable { let container: ObjectIdentifier; let day: String; let unlocked: Bool; let settings: String; let tables: [Double] }
    struct Slots {
        var cards: MoneyCardsReading??; var obligations: MoneyObligationsReading??
        var categories: MoneyCategoriesReading??; var reconcile: MoneyReconcileReading??
    }
    private static var key: Key?
    private static var slots = Slots()
    static var liveReads = 0
    static func read<T>(_ session: AppSession, _ now: Date, _ slot: WritableKeyPath<Slots, T??>, _ load: () throws -> T) -> T? {
        if liveReads > 0 { return try? load() }
        guard let current = try? currentKey(session, now) else { return try? load() }
        if key != current { key = current; slots = Slots() }
        if let cached = slots[keyPath: slot] { return cached }
        // A failed read (busy store, locked data) is not kept: the next refresh tries again.
        guard let value = try? load() else { return nil }
        slots[keyPath: slot] = .some(value)
        return value
    }
    private static func currentKey(_ session: AppSession, _ now: Date) throws -> Key {
        let context = ModelContext(session.container)
        var tables: [Double] = []
        func mark<M: PersistentModel>(_ type: M.Type, _ updated: any KeyPath<M, Date> & Sendable) throws {
            var newest = FetchDescriptor<M>(sortBy: [SortDescriptor(updated, order: .reverse)]); newest.fetchLimit = 1
            tables.append(Double(try context.fetchCount(FetchDescriptor<M>())))
            tables.append(try context.fetch(newest).first?[keyPath: updated].timeIntervalSince1970 ?? 0)
        }
        try mark(Account.self, \.updatedAt); try mark(Card.self, \.updatedAt); try mark(Statement.self, \.updatedAt)
        try mark(CashbackEntry.self, \.updatedAt); try mark(MoneyTransaction.self, \.updatedAt); try mark(Allocation.self, \.updatedAt)
        try mark(Reconciliation.self, \.updatedAt); try mark(BankMessage.self, \.updatedAt); try mark(Cycle.self, \.updatedAt)
        try mark(CyclePolicy.self, \.updatedAt); try mark(Envelope.self, \.updatedAt); try mark(EnvelopePlan.self, \.updatedAt)
        try mark(Obligation.self, \.updatedAt); try mark(InstallmentItem.self, \.updatedAt); try mark(MadarData.Category.self, \.updatedAt)
        try mark(CategoryLimit.self, \.updatedAt); try mark(MerchantRule.self, \.updatedAt); try mark(Trip.self, \.updatedAt)
        let settings = session.values.filter { $0.key.hasPrefix("mal.") || $0.key.hasPrefix("core.") }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        return Key(container: ObjectIdentifier(session.container), day: GregorianDay.containing(now, in: session.activePlace.timeZone).description,
                   unlocked: session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized, settings: settings, tables: tables)
    }
}
