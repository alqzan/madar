import XCTest
import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarInbox
@testable import Madar

@MainActor final class PrayerActivityIntegrationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-09T04:40:00+03:00")!
    private func fixture() throws -> (AppSession, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarActivity-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (try AppSession(container: container, groupDirectory: root), root)
    }
    func testDefaultOffAndSettingsRepublishDisableExternalStarts() async throws {
        let (app, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try app.publishNotificationBudget(at: now)
        XCTAssertThrowsError(try app.notificationBudget.reservePrayerActivity(id: "off", now: now)) { XCTAssertEqual($0 as? NotificationBudgetError, .disabled) }
        try await app.applySettingsAndWait(["salah.liveActivity": .bool(true)])
        try app.publishNotificationBudget(at: now)
        _ = try app.notificationBudget.reservePrayerActivity(id: "on", now: now)
        try await app.applySettingsAndWait(["notif.thisDeviceReminders": .bool(false)])
        try app.publishNotificationBudget(at: now)
        XCTAssertThrowsError(try app.notificationBudget.reservePrayerActivity(id: "device.off", now: now)) { XCTAssertEqual($0 as? NotificationBudgetError, .disabled) }
        XCTAssertEqual(try app.notificationBudget.reservations().count, 1, "Disabling does not refund a submitted start without OS cancellation")
    }
    func testStarterReservesBeforeOSCallAndRefundsExplicitFailure() async throws {
        let (app, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await app.applySettingsAndWait(["salah.liveActivity": .bool(true)])
        try app.publishNotificationBudget(at: now)
        enum Simulated: Error { case rejected }
        do {
            try await PrayerActivityStarter.start(budget: app.notificationBudget, now: now) { reserved in
                XCTAssertEqual(try app.notificationBudget.reservations(), [reserved.reservation])
                XCTAssertEqual(reserved.reservation.scheduledAt, self.now.addingTimeInterval(21*60))
                throw Simulated.rejected
            }
            XCTFail("The OS rejection must propagate")
        } catch Simulated.rejected { }
        XCTAssertTrue(try app.notificationBudget.reservations().isEmpty)
        var calls = 0
        try await PrayerActivityStarter.start(budget: app.notificationBudget, now: now) { _ in calls += 1 }
        do {
            try await PrayerActivityStarter.start(budget: app.notificationBudget, now: now) { _ in calls += 1 }
            XCTFail("Repeated start should be deduplicated")
        } catch NotificationBudgetError.duplicate { }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try ModelContext(app.container).fetchCount(FetchDescriptor<PrayerLog>()), 0)
    }
    func testExistingDeviceLedgerSeedsSharedBudgetWithoutPrayerAsks() async throws {
        let (app, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(app.container)
        for id in ["quran.one", "quran.two", "quran.three", "activity.old", "activity.old", "prayer.ask"] {
            let row = NotificationLedger(); row.requestID = id; row.dayKey = "2026-10-09"
            row.scheduledFor = now.addingTimeInterval(6*3600); row.state = "submitted"
            row.requestClass = id == "prayer.ask" ? "prayer" : "room"
            context.insert(row)
        }
        try context.save()
        try await app.applySettingsAndWait(["salah.liveActivity": .bool(true)])
        try app.publishNotificationBudget(at: now)
        XCTAssertEqual(try app.notificationBudget.reservations().count, 4)
        XCTAssertThrowsError(try app.notificationBudget.reservePrayerActivity(id: "external", now: now)) { XCTAssertEqual($0 as? NotificationBudgetError, .full) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotificationLedger>()), 6)
    }
    func testMinuteFormatterUsesTwoFieldsAndConfiguredDigits() {
        let end = now.addingTimeInterval(74*60)
        let timer = SystemFormatStyle.Timer(countingDownIn: now..<end, maxFieldCount: 2, maxPrecision: .seconds(60))
        let arabic = String(timer.locale(Locale(identifier: "ar_SA@numbers=arab")).format(now).characters)
        let western = String(timer.locale(Locale(identifier: "ar_SA@numbers=latn")).format(now).characters)
        XCTAssertEqual(arabic, "ساعة و١٤ دقيقة")
        XCTAssertEqual(western, "ساعة و14 دقيقة")
        let fiveMinutes = now.addingTimeInterval(69*60)
        XCTAssertEqual(String(timer.locale(Locale(identifier: "ar_SA@numbers=arab")).format(fiveMinutes).characters), "٥ دقائق")
    }
}
