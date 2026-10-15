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
}
