import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiaryTravelIntegrationTests:XCTestCase {
    // §10: a write inside [trip.start, trip.end) is stamped in the trip zone; at or after end it is home again.
    // The diary never creates or edits the Trip; it only reads it.
    func testTripZoneStampsWritesAndDiaryReadsTheSharedTrip() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryTravel-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root)
        app.authorizeProtectedData();try await app.applySettingsAndWait(["core.dayStart":.string("midnight")])
        // Arrive one minute after Tokyo midnight so the stored arrival day is today's Tokyo day whatever the wall clock.
        let tokyo=TimeZone(identifier:"Asia/Tokyo")!,context=ModelContext(container),start=GregorianDay.containing(Date(),in:tokyo).date(in:tokyo).addingTimeInterval(60)
        let trip=Trip();trip.city="طوكيو";trip.lat=35.6762;trip.lon=139.6503;trip.tzID="Asia/Tokyo";trip.mode="manual";trip.start=start;context.insert(trip);try context.save()
        let service=AppDiaryService(app:app,clock:{Date()})
        try await app.executeDiaryCommand("diary.appendLine",payload:["text":.string("كتبت من طوكيو"),"day":.string("today")])
        let page=try XCTUnwrap(try service.travel(try service.currentDay()))
        XCTAssertEqual(page.city,"طوكيو");XCTAssertEqual(page.number,1);XCTAssertTrue(page.current);XCTAssertFalse(page.returned)
        XCTAssertEqual(page.homeName,"الرياض");XCTAssertEqual(Double(page.kilometres),8_650,accuracy:150)
        let fresh=ModelContext(container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<Entry>()).first{$0.text=="كتبت من طوكيو"}?.tzID,"Asia/Tokyo")
        let row=try XCTUnwrap(try fresh.fetch(FetchDescriptor<Trip>()).first);row.end=Date().addingTimeInterval(-1);try fresh.save()
        try await app.executeDiaryCommand("diary.appendLine",payload:["text":.string("رجعت"),"day":.string("today")])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first{$0.text=="رجعت"}?.tzID,"Asia/Riyadh")
        XCTAssertEqual(try service.travelStamps().map(\.city),["طوكيو"]);XCTAssertNotNil(try service.travelStamps().first?.departure)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Trip>()),1)
    }

    func testDiaryDayUsesTheActiveTripMethodAtFajr() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryTripMethod-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-20T04:08:00+00:00"))
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        try settings.prepare(.string("fajr"), for: "core.dayStart", now: instant)
        try settings.prepare(.string("mwl"), for: "salah.method", now: instant)
        try settings.prepare(.string("egyptian"), for: "salah.tripMethod", now: instant)
        try settings.prepare(.string("twilightAngle"), for: "salah.highLatitudeRule", now: instant)
        let trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = instant.addingTimeInterval(-3600)
        context.insert(trip); try context.save()

        let app = try AppSession(container: container, groupDirectory: root)
        let service = AppDiaryService(app: app, clock: { instant })
        let expected = try GregorianDay("2026-03-20")
        XCTAssertEqual(try service.diaryDay(), expected)
        XCTAssertEqual(AppBahwService(session: app, evaluationDate: instant).today, expected)
    }

    func testOpenTripCalendarIncludesArrivalDayInDestinationDayBoundary() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryTravelDays-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let instant=ISO8601DateFormatter().date(from:"2026-10-15T20:30:00Z")!,arrival=try GregorianDay("2026-10-16")
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        let settings=try SettingsStore(context:context);try settings.prepare(.string("fajr"),for:"core.dayStart",now:instant)
        let trip=Trip();trip.city="طوكيو";trip.lat=35.6762;trip.lon=139.6503;trip.tzID="Asia/Tokyo";trip.mode="manual";trip.start=instant
        context.insert(trip);try context.save()
        let app=try AppSession(container:container,groupDirectory:root);app.authorizeProtectedData()
        let service=AppDiaryService(app:app,clock:{instant})

        XCTAssertEqual(try service.currentDay(),arrival)
        XCTAssertEqual(try service.travelDays(),[arrival])
    }

    func testDiaryEntryKeepsItsTripTimeZoneInTheDayReadModel() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryTripClock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = Date()
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        try settings.prepare(.string("midnight"), for: "core.dayStart", now: instant)
        let trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = instant.addingTimeInterval(-60 * 60); trip.end = instant.addingTimeInterval(60 * 60)
        context.insert(trip); try context.save()

        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppDiaryService(app: app)
        try await app.executeDiaryCommand("diary.appendLine", payload: ["text": .string("سطر وقت الرحلة"), "day": .string("today")])
        let day = try service.currentDay()
        let line = try XCTUnwrap(try service.day(day).lines.first { $0.text == "سطر وقت الرحلة" })
        XCTAssertEqual(line.tzID, "Europe/London")
        let travelClock = service.time(line.at, zone: line.tzID)
        XCTAssertNotEqual(travelClock, service.time(line.at, zone: "Asia/Riyadh"))
        let lobby = AppBahwService(session: app, evaluationDate: app.prayerNow())
        let diary = try XCTUnwrap(lobby.diary())
        XCTAssertEqual(diary.lastTZID, "Europe/London")
        XCTAssertEqual(lobby.time(try XCTUnwrap(diary.last), zone: diary.lastTZID), travelClock)
    }
}
