import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

/// M4-F02: built rooms share the arbiter; app protection hides content (§8 item 10); a tap opens the room it speaks for.
@MainActor final class RoomNotificationsIntegrationTests: XCTestCase {
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
        let (app, root, _, day) = try fixture([:]); defer { try? FileManager.default.removeItem(at: root) }
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
}
