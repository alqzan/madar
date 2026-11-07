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
        let (app, _, now, day) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight"), "mal.cardDue": .string("3days")])
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
        XCTAssertTrue(content.body.contains("بعد ثلاثة أيام"), "the card reminder says when, in words")
        RoomNotificationContent.open(candidate.id, userInfo: content.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "money"); XCTAssertFalse(app.moneyOpen)
        XCTAssertEqual(app.moneyRoute?.path, ["card", card.id.uuidString])
        XCTAssertEqual(app.moneyRoute?.parameters["tab"], "calendar")
        statement.dueDate = day.day.date(in: day.place.timeZone); statement.updatedAt = .now; try c.save() // real writes stamp updatedAt
        let cash = try XCTUnwrap(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).first)
        XCTAssertTrue(cash.id.hasPrefix("mal.cardCash."))
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(cash.id, session: app, now: now))
        RoomNotificationContent.open(cash.id, userInfo: ["dayKey": cash.dayKey], session: app)
        XCTAssertEqual(app.moneyRoute?.path, ["card", card.id.uuidString])
        XCTAssertEqual(app.moneyRoute?.parameters["tab"], "cash")
        let payment = MoneyTransaction(); payment.kind = "cardPayment"; payment.cardID = card.id; payment.fromAccountID = account.id; payment.eventAt = now; payment.dayKey = day.day.description; payment.amountMinor = 50_000; payment.homeAmountMinor = 50_000; c.insert(payment); try c.save()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(cash.id, session: app, now: now))
        XCTAssertTrue(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).isEmpty)
        _ = try SettingsStore(context: c).stage(["mal.cardDue": .string("off"), "core.faceIDLock": .string("app")]); try c.save(); try app.reload()
        XCTAssertTrue(RoomNotificationContent.cardCandidates(session: app, prayerDays: [day], now: now).isEmpty)
        XCTAssertEqual(RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:]).body, "لديك تنبيه في مدار")
    }

    func testPrayerAndDiaryNotificationBodiesOpenTheirSpecificDestinations() throws {
        let (app, _, _, prayerDay) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight")])
        let day = prayerDay.day.description

        RoomNotificationContent.open("quran.\(day).late", userInfo: ["dayKey": day], session: app)
        XCTAssertEqual(app.quranRoute?.path, ["session", "review"])

        RoomNotificationContent.open("qada.\(day)", userInfo: ["dayKey": day], session: app)
        XCTAssertEqual(app.prayerRoute?.path, ["qada"])
        XCTAssertEqual(app.selectedTab, "prayer")

        app.prayerRoute = nil
        RoomNotificationContent.open("notes.\(day).niyya", userInfo: ["dayKey": day, "room": "notes"], session: app)
        XCTAssertEqual(app.diaryRoute?.path, ["day", day])
        XCTAssertEqual(app.selectedTab, "notes")

        app.diaryRoute = nil
        RoomNotificationContent.open("notes.\(day).onThisDay", userInfo: ["dayKey": day, "room": "notes"], session: app)
        XCTAssertEqual(app.diaryRoute?.path, ["day", day])

        app.diaryRoute = nil
        RoomNotificationContent.open("notes.\(day).letter", userInfo: ["dayKey": day, "room": "notes"], session: app)
        XCTAssertEqual(app.diaryRoute?.path, ["letters"])
    }

    func testMoneyNotificationsOpenTheDestinationNamedByTheReminder() throws {
        let (app, _, _, day) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight")])
        RoomNotificationContent.open("mal.alert80.\(UUID().uuidString)", userInfo: ["dayKey": day.day.description], session: app)
        XCTAssertEqual(app.moneyRoute?.path, ["categories"])
        app.moneyRoute = nil
        RoomNotificationContent.open("mal.reconcile.\(day.day.description)", userInfo: ["dayKey": day.day.description], session: app)
        XCTAssertEqual(app.moneyRoute?.path, ["reconcile"])
        app.moneyRoute = nil
        RoomNotificationContent.open("mal.zakat.\(day.day.description)", userInfo: ["dayKey": day.day.description], session: app)
        XCTAssertEqual(app.moneyRoute?.path, ["zakat"])
    }

    func testLimitAlertStaysAmountFreeWhenMoneyIsVisibleInsideTheApp() throws {
        let (app, _, _, day) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight"),
                                            "core.hideMoneyUntilTouch": .bool(false)])
        app.authorizeProtectedData()
        let context = ModelContext(app.container), now = Date(), zone = ActivePlace.riyadh.timeZone
        let cycle = Cycle(); cycle.start = now.addingTimeInterval(-20 * 86_400); cycle.expectedEnd = now.addingTimeInterval(10 * 86_400); context.insert(cycle)
        let category = MadarData.Category(); category.name = "مطاعم"; context.insert(category)
        let limit = CategoryLimit(); limit.categoryID = category.id; limit.mode = "fixed"; limit.limitMinor = 100_000; context.insert(limit)
        let account = Account(); context.insert(account)
        let transaction = MoneyTransaction(); transaction.kind = "expense"; transaction.categoryID = category.id
        transaction.cycleID = cycle.id; transaction.fromAccountID = account.id; transaction.eventAt = now
        transaction.dayKey = GregorianDay.containing(now, in: zone).description; transaction.tzID = zone.identifier
        transaction.dayPolicy = "midnight@1"; transaction.method = "cash"; transaction.source = "manual"
        transaction.reviewState = "ok"; transaction.amountMinor = 90_000; transaction.homeAmountMinor = 90_000; context.insert(transaction)
        let allocation = Allocation(); allocation.transactionID = transaction.id; allocation.cycleID = cycle.id
        allocation.target = "daily"; allocation.amountMinor = -90_000; allocation.kind = "spend"
        allocation.idempotencyKey = UUID().uuidString; context.insert(allocation)
        try context.save(); try app.reload()

        let shelf = try XCTUnwrap(AppMoneyService(app: app).loadCategories().shelves.first { $0.id == category.id })
        XCTAssertEqual(shelf.spentMinor, 90_000); XCTAssertEqual(shelf.percentUsed, 90)
        let candidate = try XCTUnwrap(RoomNotificationContent.limitCandidates(session: app, prayerDays: [], now: now).first)
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: now,
                                            timeZone: zone, policy: .init(staleNudgeEnabled: false))

        for hideMoney in [false, true] {
            _ = try SettingsStore(context: context).stage(["core.hideMoneyUntilTouch": .bool(hideMoney)])
            try context.save(); try app.reload()
            let body = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:]).body
            // OR-25 (owner, 26 Oct): name the category and the 80% line; the only digits are that line, never an amount.
            XCTAssertEqual(body, "بلغت ٨٠٪ من حد «مطاعم» لهذه الدورة")
            XCTAssertNil(body.replacingOccurrences(of: "٨٠٪", with: "").rangeOfCharacter(from: .decimalDigits))
            XCTAssertFalse(body.contains("باقي"))
        }
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now))
        XCTAssertFalse(try RoomNotificationContent.stillRelevant("mal.alert80.\(UUID().uuidString).\(category.id.uuidString)", session: app, now: now), "An earlier cycle must not alert in this cycle")

        limit.limitMinor = 200_000; limit.updatedAt = .now; try context.save(); try app.reload()
        XCTAssertTrue(RoomNotificationContent.limitCandidates(session: app, prayerDays: [], now: now).isEmpty)
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "Raising the limit makes the queued 90/100 alert obsolete")

        limit.limitMinor = 100_000; allocation.amountMinor = -79_999; try context.save(); try app.reload()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "Below 80% is not relevant")
        allocation.amountMinor = -80_000; try context.save(); try app.reload()
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "Exactly 80% remains relevant")

        transaction.deletedAt = now; try context.save(); try app.reload()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "A removed expense cannot keep a stale alert alive")
        transaction.deletedAt = nil; limit.mode = "none"; try context.save(); try app.reload()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now), "Turning off the limit removes the alert")
        limit.mode = "fixed"
        _ = try SettingsStore(context: context).stage(["mal.alert80": .bool(false)])
        try context.save(); try app.reload()
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(candidate.id, session: app, now: now))
    }

    func testReconciliationReminderUsesSharedBudgetAndGenericCopy() throws {
        let (app, _, now, day) = try fixture(["core.faceIDLock": .string("app"), "core.dayStart": .string("midnight"), "mal.reconcileEveryDays": .number(90)])
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
        let (app, _, now, day) = try fixture(["core.faceIDLock": .string("app"), "core.dayStart": .string("midnight"), "mal.zakatReminder": .string("1week")])
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
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), store = try SettingsStore(context: context)
        _ = try store.stage(settings); try context.save()
        let now = ISO8601DateFormatter().date(from: "2026-10-15T02:00:00+03:00")!
        let day = try XCTUnwrap(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-15"), place: .riyadh))
        return (try AppSession(container: container, groupDirectory: root), root, now, day)
    }

    func testQadaOffAndNothingOwedScheduleNothing() async throws {
        let (off, _, now, day) = try fixture(["salah.qadaReminder": .string("off")])
        let offCandidates = try await RoomNotificationContent.candidates(session: off, prayerDays: [day], now: now)
        XCTAssertFalse(offCandidates.contains { $0.id.hasPrefix("qada.") })
        let (fresh, _, _, _) = try fixture(["salah.qadaReminder": .string("afterFajr")])
        // A fresh store owes nothing (RP1: an unlogged prayer never becomes qada).
        let freshCandidates = try await RoomNotificationContent.candidates(session: fresh, prayerDays: [day], now: now)
        XCTAssertFalse(freshCandidates.contains { $0.id.hasPrefix("qada.") })
    }

    func testHabitReminderUsesTheActiveTripCivilDay() async throws {
        let (app, _, _, _) = try fixture(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight")])
        let now = ISO8601DateFormatter().date(from: "2026-10-15T20:00:00Z")!
        let context = ModelContext(app.container), trip = Trip()
        trip.city = "طوكيو"; trip.lat = 35.6762; trip.lon = 139.6503; trip.tzID = "Asia/Tokyo"
        trip.mode = "manual"; trip.start = now.addingTimeInterval(-3600)
        context.insert(trip)
        let habit = Habit(); habit.name = "مشي"; habit.reminder = "push"; habit.startDate = now.addingTimeInterval(-30 * 86_400); context.insert(habit)
        let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = "2026-10-01"; policy.frequency = "daily"
        policy.measure = "once"; policy.target = 1; policy.windowStartMin = 8 * 60; policy.windowEndMin = 10 * 60
        context.insert(policy); try context.save(); try app.reload()
        let place = try ActivePlace(latitude: trip.lat, longitude: trip.lon, timeZoneID: trip.tzID)
        let days = (0..<3).compactMap { PrayerTimesEngine.calculate(day: try! GregorianDay("2026-10-16").adding(days: $0), place: place) }

        let tripCandidates = try await RoomNotificationContent.candidates(session: app, prayerDays: days, now: now)
        let candidate = try XCTUnwrap(tripCandidates.first { $0.id == "habits.2026-10-16.\(habit.id.uuidString)" })
        XCTAssertEqual(candidate.dayKey, "2026-10-16")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
        XCTAssertEqual(calendar.component(.hour, from: candidate.dueAt), 8)
        XCTAssertEqual(calendar.component(.day, from: candidate.dueAt), 16)
    }

    func testQuranReminderCopyIsGenericOnlyUnderWholeAppLock() throws {
        for lock in ["none", "app"] {
            let (app, _, now, day) = try fixture(["core.faceIDLock": .string(lock)])
            let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: now,
                                                timeZone: day.place.timeZone, policy: .init(staleNudgeEnabled: false))
            for (suffix, title, body) in [("wird", QuranReminderCopy.title, NudgeWording.body(.quranWird, dayKey: "2026-10-15")),
                                          ("late", QuranReminderCopy.lateTitle, NudgeWording.body(.quranReview, dayKey: "2026-10-15"))] {
                let candidate = NotificationCandidate(id: "quran.2026-10-15.\(suffix)", room: .quran,
                                                      dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-15")
                let content = RoomNotificationContent.content(for: candidate, plan: plan, session: app, habitNames: [:])
                if lock == "app" {
                    XCTAssertEqual(content.title, "مدار")
                    XCTAssertEqual(content.body, "لديك تذكير في مدار")
                } else {
                    XCTAssertEqual(content.title, title)
                    XCTAssertEqual(content.body, body)
                }
            }
        }
    }

    func testWholeAppLockPurgesEveryRoomNotificationButKeepsPrayerPrompts() {
        let identifiers = ["quran.2026-10-15.late", "digest.2026-10-15", "qada.2026-10-15",
                           "habits.2026-10-15.id", "notes.2026-10-15.niyya", "nudge.2026-10-15",
                           "mal.alert80.id.category", "mal.cardDue.id", "mal.cardCash.id",
                           "mal.reconcile.id", "mal.zakat.id", "salah.2026-10-15.fajr"]
        XCTAssertEqual(Set(AppPrivacyService.protectedRoomNotificationIdentifiers(in: identifiers)),
                       Set(identifiers.dropLast()), "Whole-app lock removes sensitive room notices while prayer prompts stay available.")
    }

    func testProtectedAppShowsGenericCopyAndTapsOpenTheRoom() throws {
        let (app, _, _, day) = try fixture(["core.faceIDLock": .string("app")])
        let habit = UUID()
        let qada = NotificationCandidate(id: "qada.2026-10-15", room: .salah, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let reminder = NotificationCandidate(id: "habits.2026-10-15.\(habit.uuidString)", room: .habits, dueAt: day.asr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: day.fajr, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        let q = RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:])
        let h = RoomNotificationContent.content(for: reminder, plan: plan, session: app, habitNames: [habit.uuidString: "المشي"])
        XCTAssertFalse(q.body.contains("قضاء")); XCTAssertEqual(q.title, "مدار"); XCTAssertFalse(h.title.contains("المشي"))
        let digest = RoomNotificationContent.content(for: NotificationCandidate(id: "digest.2026-10-15", room: .habits, dueAt: day.asr, dayKey: "2026-10-15"), plan: plan, session: app, habitNames: [:])
        XCTAssertEqual(digest.title, "مدار"); XCTAssertTrue(digest.body.hasSuffix("في مدار"), digest.body)
        RoomNotificationContent.open(reminder.id, userInfo: h.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "foundation"); XCTAssertTrue(app.habitsOpen); XCTAssertEqual(app.habitRouteID, habit)
        RoomNotificationContent.open(qada.id, userInfo: q.userInfo, session: app)
        XCTAssertEqual(app.selectedTab, "prayer")
    }

    func testQadaCopyNeverCarriesTheDebtCount() throws {
        let (app, _, _, day) = try fixture(["core.faceIDLock": .string("none")])
        let qada = NotificationCandidate(id: "qada.2026-10-15", room: .salah, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-15")
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: day.fajr, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        XCTAssertTrue(RoomNotificationContent.qadaLines.contains(RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:]).body))
        // OR-06: fifteen lines that change from day to day, none with a digit.
        XCTAssertEqual(RoomNotificationContent.qadaLines.count, 15)
        XCTAssertGreaterThan(Set((10...24).map { RoomNotificationContent.qadaLine("2026-10-\($0)") }).count, 5)
        XCTAssertTrue(RoomNotificationContent.qadaLines.allSatisfy { $0.rangeOfCharacter(from: .decimalDigits) == nil })
        let body = RoomNotificationContent.content(for: qada, plan: plan, session: app, habitNames: [:]).body
        XCTAssertNil(body.rangeOfCharacter(from: .decimalDigits), "RU2: no prayer-debt count outside the app")
    }

    func testHabitAndZakatCopySayWhenAndNeverPromiseAMissingStreak() throws {
        let (app, _, _, day) = try fixture(["core.faceIDLock": .string("none")])
        let plan = NotificationArbiter.plan(candidates: [], prayerDays: [day], now: day.fajr, timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        let habit = NotificationCandidate(id: "habits.2026-10-15.\(UUID().uuidString)", room: .habits, dueAt: day.asr.addingTimeInterval(1800), dayKey: "2026-10-15")
        // No streak exists: the line is a first-step one for that day and never one that promises to keep a streak.
        XCTAssertEqual(RoomNotificationContent.content(for: habit, plan: plan, session: app, habitNames: [:]).body, NudgeWording.body(.habitFirstStep, dayKey: "2026-10-15"))
        XCTAssertFalse(NudgeWording.variants(.habitKeepStreak).contains(RoomNotificationContent.content(for: habit, plan: plan, session: app, habitNames: [:]).body))
        for (lead, words) in [("1day", "غدًا"), ("1week", "بعد أسبوع"), ("1month", "بعد نحو شهر")] {
            let zakat = NotificationCandidate(id: "mal.zakat.\(lead).2026-11-20", room: .mal, kind: .annualReminder, dueAt: day.asr.addingTimeInterval(1800), dayKey: "2026-10-15")
            let body = RoomNotificationContent.content(for: zakat, plan: plan, session: app, habitNames: [:]).body
            XCTAssertEqual(body, "يحين موعد الحساب السنوي الذي اخترته " + words)
            XCTAssertNil(body.rangeOfCharacter(from: .decimalDigits))
        }
    }

    func testDigestCountUsesTheCatalogPlural() {
        let digits = MadarNumberFormatter(style: .hindi)
        XCTAssertEqual([1, 2, 3, 11, 100].map { RoomNotificationContent.reminderCount($0, digits) },
                       ["تذكير واحد", "تذكيران", "٣ تذكيرات", "١١ تذكيرًا", "١٠٠ تذكير"])
    }

    /// M3-V12: the three diary kinds schedule from day keys and triggers; no title, body or userInfo ever carries diary text,
    /// with or without the whole-app lock (§8 item 10, RU2, owner 15 Oct).
    func testDiaryRemindersScheduleWithoutEverCarryingDiaryText() async throws {
        for lock in ["none", "app"] {
            let (app, _, now, day) = try fixture(["core.dayStart": .string("midnight"), "core.faceIDLock": .string(lock)])
            let context = ModelContext(app.container), secret = "زعفرانيّة"
            let entry = Entry(); entry.dayKey = "2025-10-15"; entry.text = "كتبت " + secret; entry.eventAt = now.addingTimeInterval(-365 * 86400); context.insert(entry)
            let letter = Letter(); letter.text = secret; letter.triggerKind = "date"; letter.triggerValue = "2026-10-15"; context.insert(letter)
            try context.save(); try app.reload()
            let candidates = try await RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now).filter { $0.id.hasPrefix("notes.") }
            XCTAssertEqual(Set(candidates.map(\.id)), ["notes.2026-10-15.niyya", "notes.2026-10-15.letter", "notes.2026-10-15.onThisDay", "notes.2026-10-15.line"], lock)
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
                               ["عندك ذكرى من هذا اليوم", NudgeWording.body(.diaryNiyya, dayKey: "2026-10-15"), "وصلتك رسالة من ماضيك", NudgeWording.body(.diaryLine, dayKey: "2026-10-15")].sorted())
            }
        }
    }

    func testTheEveningLineReminderWaitsForNothingWrittenAndStopsWhenALineArrives() async throws {
        let (app, _, now, day) = try fixture(["core.dayStart": .string("midnight")])
        let before = try await RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now)
        let line = try XCTUnwrap(before.first { $0.id == "notes.2026-10-15.line" }, "nothing is written for today")
        XCTAssertEqual(line.dueAt, day.isha.addingTimeInterval(1800), "after Isha's sanctity window ends")
        XCTAssertTrue(try RoomNotificationContent.stillRelevant(line.id, session: app, now: now))
        let context = ModelContext(app.container)
        let entry = Entry(); entry.dayKey = "2026-10-15"; entry.text = "سطر"; entry.eventAt = now; context.insert(entry)
        try context.save(); try app.reload()
        let after = try await RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now)
        XCTAssertFalse(after.contains { $0.id == "notes.2026-10-15.line" }, "a line was written")
        XCTAssertFalse(try RoomNotificationContent.stillRelevant(line.id, session: app, now: now), "a pending reminder is dropped once the day has a line")
    }

    func testDiaryCapZeroAndOffSettingsScheduleNoDiaryReminder() async throws {
        let (app, _, now, day) = try fixture(["core.dayStart": .string("midnight"), "notes.dailyCap": .number(0)])
        let capped = try await RoomNotificationContent.candidates(session: app, prayerDays: [day], now: now)
        XCTAssertFalse(capped.contains { $0.id.hasPrefix("notes.") })
        let (quiet, _, _, _) = try fixture(["core.dayStart": .string("midnight"), "notes.morningNiyya": .bool(false), "notes.eveningLine": .bool(false), "notes.onThisDay": .string("off")])
        let quietCandidates = try await RoomNotificationContent.candidates(session: quiet, prayerDays: [day], now: now)
        XCTAssertFalse(quietCandidates.contains { $0.id.hasPrefix("notes.") }, "no letter, no intention, no memory")
    }
}
