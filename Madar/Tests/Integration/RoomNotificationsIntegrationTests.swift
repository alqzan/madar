import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

/// M4-F02: built rooms share the arbiter; app protection hides content (§8 item 10); a tap opens the room it speaks for.
@MainActor final class RoomNotificationsIntegrationTests: XCTestCase {
    private final class LockedNotificationLockService: MadarLockService {
        func redactProtectedData() async throws {}
        func authorizeAccess(to feature: MadarProtectedFeature) async throws {}
        func privacyScopeDidChange(to scope: MadarLockScope) async throws {}
        func persistedPrivacyScope() throws -> MadarLockScope { .app }
    }
    private final class LockedNotificationAuthenticator: MadarDeviceAuthenticator {
        private(set) var calls = 0
        func verify() async throws -> Bool { calls += 1; return true }
        func invalidate() {}
    }

    func testCardRemindersAreAmountFreeAndStopAfterPaymentOrOff() throws {
        let (app, root, now, day) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight"), "mal.cardDue": .string("3days")]); defer { try? FileManager.default.removeItem(at: root) }
        app.authorizeProtectedData()
        let c = ModelContext(app.container), account = Account(); account.balanceMinor = 10_000; account.balanceAt = now; c.insert(account)
        let card = Card(); card.name = "بطاقة سرية"; card.accountID = account.id; c.insert(card)
        let statement = Statement(); statement.cardID = card.id; statement.closeDate = now.addingTimeInterval(-86400); statement.statementMinor = 50_000; statement.dueDate = day.day.adding(days: 3).date(in: day.place.timeZone); c.insert(statement); try c.save(); try app.reload()
        let candidates = RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now)
        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertTrue(candidate.id.hasPrefix("mal.cardDue.")); XCTAssertTrue(RoomNotificationContent.isRoomRequest(candidate.id))
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: now, timeZone: day.place.timeZone, policy: .init(staleNudgeEnabled: false))
        let content = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:])
        XCTAssertNil(content.body.rangeOfCharacter(from: .decimalDigits))
        XCTAssertFalse(content.body.contains(card.name))
        RoomNotificationContent.open(candidate.id, userInfo: content.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "money"); XCTAssertFalse(app.moneyOpen)
        statement.dueDate = day.day.date(in: day.place.timeZone); try c.save()
        let cash = try XCTUnwrap(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).first)
        XCTAssertTrue(cash.id.hasPrefix("mal.cardCash."))
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(cash.id, session: app, now: now))
        let payment = MoneyTransaction(); payment.kind = "cardPayment"; payment.cardID = card.id; payment.fromAccountID = account.id; payment.eventAt = now; payment.dayKey = day.day.description; payment.amountMinor = 50_000; payment.homeAmountMinor = 50_000; c.insert(payment); try c.save()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(cash.id, session: app, now: now))
        XCTAssertTrue(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).isEmpty)
        _ = try SettingsStore(context: c).stage(["mal.cardDue": .string("off"), "core.faceIDLock": .string("app")]); try c.save(); try app.reload()
        XCTAssertTrue(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).isEmpty)
        XCTAssertEqual(RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:]).body, "لديك تنبيه في مدار")
    }

    func testReconciliationReminderUsesSharedBudgetAndGenericCopy() throws {
        let (app, root, now, day) = try fixture(["core.faceIDLock": .string("app"), "core.dayStart": .string("midnight"), "mal.reconcileEveryDays": .number(90)])
        defer { try? FileManager.default.removeItem(at: root) }
        app.authorizeProtectedData()
        let context = ModelContext(app.container), account = Account()
        account.name = "synthetic private account"; account.currency = "SAR"; account.balanceMinor = 1_234_567
        account.balanceAt = now.addingTimeInterval(-100 * 86_400); context.insert(account); try context.save(); try app.reload()

        let candidates = RoomNotificationContent.reconciliationCandidates(session: app, prayerDays: [day], now: now)
        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertTrue(candidate.id.hasPrefix("mal.reconcile.")); XCTAssertTrue(RoomNotificationContent.isRoomRequest(candidate.id))
        XCTAssertEqual(RoomNotificationContent.ledgerKind(candidate.id), "reconciliation")
        let plan = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: now, timeZone: day.place.timeZone,
                                            policy: .init(dailyBudget: 1, staleNudgeEnabled: false))
        XCTAssertEqual(plan.scheduled.map(\.id), [candidate.id], "It uses the existing per-device reminder budget and prayer guard")
        let content = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:])
        let shown = content.title + content.body
        XCTAssertEqual(content.body, "حان وقت المراجعة")
        XCTAssertNil(shown.rangeOfCharacter(from: .decimalDigits))
        XCTAssertFalse(shown.contains("synthetic private account"))
        XCTAssertEqual(content.userInfo["room"] as? String, "mal")
        XCTAssertEqual(content.userInfo["dayKey"] as? String, candidate.dayKey)
        RoomNotificationContent.open(candidate.id, userInfo: content.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "money")
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now))

        let last = Reconciliation(); last.accountID = account.id; last.at = now; last.expectedMinor = account.balanceMinor
        last.observedMinor = account.balanceMinor; last.deltaMinor = 0; context.insert(last); try context.save(); try app.reload()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "A saved reconciliation makes the old request stale")
    }

    func testZakatReminderSchedulesAmountFreeWhileAppLockedAndStopsWhenOff() throws {
        let (app, root, now, day) = try fixture(["core.faceIDLock": .string("app"), "core.dayStart": .string("midnight"), "mal.zakatReminder": .string("1week")])
        defer { try? FileManager.default.removeItem(at: root) }
        app.authorizeProtectedData()
        let context = ModelContext(app.container), profile = ZakatProfile()
        profile.hawlStartHijri = "h:1448-05-01"
        context.insert(profile); try context.save(); try app.reload()
        let candidates = RoomNotificationContent.zakatCandidates(session: app, now: now)
        XCTAssertEqual(candidates.count, 2, "Both upcoming anniversaries are prepared while authorized")
        let hawl = try XCTUnwrap(MoneyHawl.read("h:1448-05-01", at: now, app: app))
        XCTAssertEqual(Set(candidates.map(\.id)), Set([hawl.anniversary, hawl.followingAnniversary].map { "mal.zakat.1week.\($0)" }))
        for candidate in candidates {
            let row = NotificationLedger()
            row.dayKey = candidate.dayKey; row.requestID = candidate.id; row.room = "mal"
            row.kind = "zakat"; row.requestClass = "room"; row.scheduledFor = candidate.dueAt; row.state = "submitted"
            context.insert(row)
        }
        try context.save(); try app.reload()
        let authenticator = LockedNotificationAuthenticator()
        let lock = MadarLockController(scope: .app, service: LockedNotificationLockService(), authenticator: { authenticator })
        app.lockController = lock
        XCTAssertFalse(lock.canPresent(.app), "The app-scope biometric gate starts locked")
        app.redactProtectedData()
        XCTAssertFalse(app.protectedDataAuthorized, "Background scheduling must not depend on unlocking the app")
        XCTAssertThrowsError(try AppMoneyService(app: app).loadZakat(at: now), "Protected Zakat data remains unavailable while locked")

        let restored = RoomNotificationContent.zakatCandidates(session: app, now: now)
        XCTAssertEqual(Set(restored.map(\.id)), Set(candidates.map(\.id)), "The locked scheduler restores already-published requests from ledger metadata")
        XCTAssertEqual(restored.map(\.dueAt), candidates.map(\.dueAt))
        XCTAssertTrue(candidates.allSatisfy { $0.kind == .annualReminder && RoomNotificationContent.isRoomRequest($0.id) })
        XCTAssertEqual(Set(candidates.map { RoomNotificationContent.ledgerKind($0.id) }), ["zakat"])

        let planningDays = RoomNotificationContent.planningPrayerDays(session: app, candidates: restored, current: [day], now: now)
        let plan = NotificationArbiter.plan(candidates: restored, prayerDays: planningDays, now: now, timeZone: day.place.timeZone,
            policy: .init(dailyBudget: 4, staleNudgeEnabled: false, dayBoundary: .midnight))
        XCTAssertEqual(Set(plan.scheduled.map(\.id)), Set(restored.map(\.id)))
        for candidate in restored {
            let content = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:])
            let shown = content.title + content.body
            XCTAssertEqual(content.title, "مدار")
            XCTAssertEqual(content.body, "لديك تذكير في مدار")
            XCTAssertNil(shown.rangeOfCharacter(from: .decimalDigits), "A zakat reminder never reveals a balance or amount")
            XCTAssertFalse(content.body.contains("هول"))
            XCTAssertEqual(content.userInfo["room"] as? String, "mal")
            RoomNotificationContent.open(candidate.id, userInfo: content.userInfo, session: app)
            XCTAssertEqual(app.selectedTab, "money")
        }

        let first = try XCTUnwrap(restored.first)
        let reminderDay = GregorianDay.containing(first.dueAt, in: day.place.timeZone)
        let reminderMorning = reminderDay.date(in: day.place.timeZone).addingTimeInterval(10 * 3600)
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(first.id, session: app, now: reminderMorning))
        XCTAssertFalse(lock.canPresent(.app), "Notification planning must not unlock protected room content")
        XCTAssertEqual(authenticator.calls, 0, "Scheduling does not ask for Face ID")
        _ = try SettingsStore(context: context).stage(["mal.zakatReminder": .string("off")]); try context.save(); try app.reload()
        XCTAssertTrue(RoomNotificationContent.zakatCandidates(session: app, now: now).isEmpty)
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(first.id, session: app, now: reminderMorning))
    }
    private func fixture(_ settings: [String: MadarData.JSONValue]) throws -> (AppSession, URL, Date, PrayerDay) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarRoomNotifications-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), store = try SettingsStore(context: context)
        _ = try store.stage(settings); try context.save()
        let now = ISO8601DateFormatter().date(from: "2026-10-15T02:00:00+03:00")!
        let day = try XCTUnwrap(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-15"), place: .riyadh))
        return (try AppSession(container: container, groupDirectory: root), root, now, day)
    }

    func testQadaOffAndNothingOwedScheduleNothing() throws {
        let (off, root, now, day) = try fixture(["salah.qadaReminder": .string("off")]); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(try RoomNotificationContent.candidates(session: off, prayerDays: [day], now: now).contains { $0.id.hasPrefix("qada.") })
        let (fresh, root2, _, _) = try fixture(["salah.qadaReminder": .string("afterFajr")]); defer { try? FileManager.default.removeItem(at: root2) }
        // A fresh store owes nothing (RP1: an unlogged prayer never becomes qada).
        XCTAssertFalse(try RoomNotificationContent.candidates(session: fresh, prayerDays: [day], now: now).contains { $0.id.hasPrefix("qada.") })
    }

    func testProtectedAppShowsGenericCopyAndTapsOpenTheRoom() throws {
        let (app, root, _, day) = try fixture(["core.faceIDLock": .string("app")]); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID()
        let qada = NotificationCandidate(id: "qada.2026-10-15", room: .salah, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let reminder = NotificationCandidate(id: "habits.2026-10-15.\(habit.uuidString)", room: .habits, dueAt: day.asr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: day.fajr, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        let q = RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:])
        let h = RoomNotificationContent.content(for: reminder, plan: plan, session: app, habitNames: [habit.uuidString: "المشي"])
        XCTAssertFalse(q.body.contains("قضاء")); XCTAssertFalse(h.title.contains("المشي"))
        RoomNotificationContent.open(reminder.id, userInfo: h.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "foundation"); XCTAssertTrue(app.habitsOpen); XCTAssertEqual(app.habitRouteID, habit)
        RoomNotificationContent.open(qada.id, userInfo: q.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "prayer")
    }

    func testQadaCopyNeverCarriesTheDebtCount() throws {
        let (app, root, _, day) = try fixture(["core.faceIDLock": .string("none")]); defer { try? FileManager.default.removeItem(at: root) }
        let qada = NotificationCandidate(id: "qada.2026-10-15", room: .salah, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: day.fajr, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        XCTAssertTrue(RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:]).body.hasPrefix("حان وقت القضاء."))
        let body = RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:]).body
        XCTAssertNil(body.rangeOfCharacter(from: .decimalDigits), "RU2: no prayer-debt count outside the app")
    }

    func testDigestCountUsesTheCatalogPlural() {
        let digits = MadarNumberFormatter(style: .hindi)
        XCTAssertEqual([1, 2, 3, 11, 100].map { RoomNotificationContent.reminderCount($0, digits) },
                       ["تذكير واحد", "تذكيران", "٣ تذكيرات", "١١ تذكيرًا", "١٠٠ تذكير"])
    }

    /// M3-V12: the three diary kinds schedule from day keys and triggers; no title, body or userInfo ever carries diary text,
    /// with or without the whole-app lock (§8 item 10, RU2, owner 15 Oct).
    func testDiaryRemindersScheduleWithoutEverCarryingDiaryText() throws {
        for lock in ["none", "app"] {
            let (app, root, now, day) = try fixture(["core.dayStart": .string("midnight"), "core.faceIDLock": .string(lock)]); defer { try? FileManager.default.removeItem(at: root) }
            let context = ModelContext(app.container), secret = "زعفرانيّة"
            let entry = Entry(); entry.dayKey = "2025-10-15"; entry.text = "كتبت " + secret; entry.eventAt = now.addingTimeInterval(-365 * 86400); context.insert(entry)
            let letter = Letter(); letter.text = secret; letter.triggerKind = "date"; letter.triggerValue = "2026-10-15"; context.insert(letter)
            try context.save(); try app.reload()
            let candidates = try RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now).filter { $0.id.hasPrefix("notes.") }
            XCTAssertEqual(Set(candidates.map(\.id)), ["notes.2026-10-15.niyya", "notes.2026-10-15.letter", "notes.2026-10-15.onThisDay"], lock)
            XCTAssertEqual(candidates.first { $0.id.hasSuffix(".niyya") }?.dueAt, day.fajr.addingTimeInterval(1800))
            XCTAssertEqual(candidates.first { $0.id.hasSuffix(".onThisDay") }?.dueAt, day.isha.addingTimeInterval(1800))
            let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: now, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
            for candidate in candidates {
                let content = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:])
                let shown = content.title + content.body + content.userInfo.values.map { "\($0)" }.joined()
                XCTAssertFalse(shown.contains(secret), "\(lock) \(candidate.id)")
                if lock == "app" { XCTAssertEqual(content.body, "لديك رسالة في مدار") }
            }
            if lock == "none" {
                XCTAssertEqual(candidates.map { RoomNotificationContent.content(for: $0, plan: plan, session: app, habitNames: [:]).body }.sorted(),
                               ["عندك ذكرى من هذا اليوم", "ما نيّتك لهذا اليوم؟ سطر واحد يكفي", "وصلتك رسالة من ماضيك"].sorted())
            }
        }
    }

    func testDiaryCapZeroAndOffSettingsScheduleNoDiaryReminder() throws {
        let (app, root, now, day) = try fixture(["core.dayStart": .string("midnight"), "notes.dailyCap": .number(0)]); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(try RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now).contains { $0.id.hasPrefix("notes.") })
        let (quiet, root2, _, _) = try fixture(["core.dayStart": .string("midnight"), "notes.morningNiyya": .bool(false), "notes.onThisDay": .string("off")]); defer { try? FileManager.default.removeItem(at: root2) }
        XCTAssertFalse(try RoomNotificationContent.candidates(session: quiet, prayerDays: [day], now: now).contains { $0.id.hasPrefix("notes.") }, "no letter, no intention, no memory")
    }
}
