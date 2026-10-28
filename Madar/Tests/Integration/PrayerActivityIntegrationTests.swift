import XCTest
import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarInbox
import MadarPrayer
@testable import Madar

@MainActor final class PrayerActivityIntegrationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-09T06:00:00+03:00")!
    private func fixture() throws -> (AppSession, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarActivity-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (try AppSession(container: container, groupDirectory: root), root)
    }
    func testPrayerNotificationScheduleReturnsToHomeAfterTripEnds() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-19T10:00:00Z"))
        let (app, _) = try fixture()
        let context = ModelContext(app.container)
        let settings = try SettingsStore(context: context)
        try settings.prepare(.string("mwl"), for: "salah.method", now: now)
        try settings.prepare(.string("egyptian"), for: "salah.tripMethod", now: now)
        try settings.prepare(.string("twilightAngle"), for: "salah.highLatitudeRule", now: now)
        let tripEnd = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-20T08:00:00Z"))
        let trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = now.addingTimeInterval(-2 * 60 * 60); trip.end = tripEnd
        context.insert(trip)
        try context.save()

        let repository = try PrayerRepository(context: ModelContext(app.container))
        let activePlace = repository.place(at: now)
        let options = repository.calculationOptions(at: now)
        let firstDay = repository.prayerDay(at: now)
        let days = (0..<4).compactMap { offset in
            PrayerTimesEngine.calculate(day: firstDay.adding(days: offset), place: activePlace, options: options)
        }
        let slots = try PrayerNotificationSchedule.slots(repository: repository, days: days, now: now)
        let dhuhr = try XCTUnwrap(slots.first { $0.reference.day.description == "2026-03-20" && $0.prayer == .dhuhr })
        XCTAssertGreaterThan(dhuhr.occurrence.time, tripEnd)
        XCTAssertNil(dhuhr.occurrence.tripID)
        XCTAssertEqual(dhuhr.occurrence.place.timeZoneID, repository.home.timeZoneID)

        let tripEstimate = try XCTUnwrap(PrayerTimesEngine.calculate(day: dhuhr.reference.day, place: activePlace, options: options))
        XCTAssertGreaterThan(abs(tripEstimate.dhuhr.timeIntervalSince(dhuhr.occurrence.time)), 60 * 60)
        let windows = PrayerNotificationSchedule.sanctityWindows(for: slots)
        let dhuhrWindow = try XCTUnwrap(windows.first { $0.prayer == .dhuhr && $0.start == dhuhr.occurrence.time })
        XCTAssertEqual(dhuhrWindow.end, dhuhrWindow.start.addingTimeInterval(60 * 60), "Friday Dhuhr keeps its 60-minute sanctity window")
        let candidate = try XCTUnwrap(PrayerNotificationSchedule.candidates(for: slots, sanctityWindows: windows,
                                                                            askAfterAdhanMinutes: 30)
            .first { $0.id == "salah.2026-03-20.dhuhr" })
        XCTAssertEqual(candidate.dueAt, dhuhrWindow.end)
    }
    func testDefaultOffAndSettingsRepublishDisableExternalStarts() async throws {
        let (app, _) = try fixture()
        let today = GregorianDay.containing(Date(), in: ActivePlace.riyadh.timeZone)
        let prayerDay = try XCTUnwrap(PrayerTimesEngine.calculate(day: today, place: .riyadh, options: .init()))
        let now = prayerDay.fajr.addingTimeInterval(31 * 60)
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
        let (app, _) = try fixture()
        try await app.applySettingsAndWait(["salah.liveActivity": .bool(true)])
        try app.publishNotificationBudget(at: now)
        enum Simulated: Error { case rejected }
        do {
            try await PrayerActivityStarter.start(budget: app.notificationBudget, now: now) { reserved in
                XCTAssertEqual(try app.notificationBudget.reservations(), [reserved.reservation])
                XCTAssertEqual(reserved.reservation.scheduledAt, self.now)
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
        let (app, _) = try fixture()
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

    func testContextActivityPlanContainsOnlyGenericEligibleLetterFacts() throws {
        let plans = MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: now, trip: nil, iftarAt: nil)
        XCTAssertEqual(plans.map(\.kind), [.letter])
        XCTAssertEqual(plans.first?.activityKey, "notes.letter")
        let attributes = MadarContextActivityAttributes(activityKey: plans[0].activityKey, kind: plans[0].kind,
                                                        startedAt: now, numerals: "hindi")
        let encoder = JSONEncoder()
        let encodedAttributes = String(data: try encoder.encode(attributes), encoding: .utf8) ?? ""
        let encodedState = String(data: try encoder.encode(plans[0].state), encoding: .utf8) ?? ""
        let encoded = encodedAttributes + encodedState
        XCTAssertFalse(encoded.contains("محتوى الرسالة الخاص"))
        XCTAssertFalse(encoded.contains("text"))
    }

    func testDueLetterRefreshesOnAuthorizedForegroundEntry() async throws {
        let (app, _) = try fixture()
        app.authorizeProtectedData()
        let dueDay = try AppDiaryService(app: app).currentDay()
        app.redactProtectedData()

        let context = ModelContext(app.container)
        let letter = Letter()
        letter.text = "رسالة خاصة"
        letter.createdAt = Date().addingTimeInterval(-24 * 60 * 60)
        letter.updatedAt = letter.createdAt
        letter.writerID = "test"
        letter.triggerKind = "date"
        letter.triggerValue = dueDay.description
        context.insert(letter)
        try context.save()

        // A locked app must not refresh or read the protected letter state.
        await app.refreshEligibleDiaryLettersForNotificationLifecycle()
        XCTAssertEqual(try ModelContext(app.container).fetch(FetchDescriptor<Letter>()).first?.state, "sealed")

        app.authorizeProtectedData()
        await app.refreshEligibleDiaryLettersForNotificationLifecycle()
        let refreshed = try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<Letter>()).first)
        XCTAssertEqual(refreshed.state, "eligible")
        XCTAssertNotNil(refreshed.eligibleAt)
    }

    func testContextActivityPlannerLimitsIftarToActiveCountdownWindow() {
        let inside = now.addingTimeInterval(8 * 60 * 60)
        let outside = now.addingTimeInterval(8 * 60 * 60 + 1)
        XCTAssertEqual(MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: nil, iftarAt: inside).map(\.kind), [.iftar])
        XCTAssertTrue(MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: nil, iftarAt: outside).isEmpty)
        XCTAssertTrue(MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: nil, iftarAt: now).isEmpty)
    }

    func testStaleIftarCopyNeverClaimsTheMealTimeHasArrived() {
        XCTAssertEqual(MadarContextActivityAttributes.Kind.iftar.staleTitle, "افتح مدار لتحديث وقت الإفطار")
        XCTAssertEqual(MadarContextActivityAttributes.Kind.iftar.compactStaleTitle, "حدّث")
        XCTAssertFalse(MadarContextActivityAttributes.Kind.iftar.staleTitle.contains("حان وقت الإفطار"))
    }

    func testContextActivityPlannerUsesOnlyAnActiveTripsCityAndTimeZone() {
        let trip = MadarContextTripFact(city: "لندن", timeZoneID: "Europe/London", startsAt: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(2 * 60 * 60))
        let plans = MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: trip, iftarAt: nil)
        XCTAssertEqual(plans, [.init(kind: .travel, activityKey: "salah.travel", eventAt: trip.startsAt,
                                     city: "لندن", timeZoneID: "Europe/London", staleAt: trip.endsAt)])

        let futureTrip = MadarContextTripFact(city: "لندن", timeZoneID: "Europe/London", startsAt: now.addingTimeInterval(60), endsAt: nil)
        let expiredTrip = MadarContextTripFact(city: "لندن", timeZoneID: "Europe/London", startsAt: now.addingTimeInterval(-3600), endsAt: now)
        XCTAssertTrue(MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: futureTrip, iftarAt: nil).isEmpty)
        XCTAssertTrue(MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: nil, trip: expiredTrip, iftarAt: nil).isEmpty)
    }
}
