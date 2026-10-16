import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarSnapshots
import MadarPrayer
@testable import Madar

@MainActor final class RoomWidgetSnapshotTests:XCTestCase {
    func testSnapshotsUseActualQuantitiesAndExpireWithoutReadingTheStoreOutsideApp() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidget-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let app=try AppSession(container:MadarContainerFactory.makeLocal(at:root),groupDirectory:root),id=UUID()
        var rule=HabitRule(effectiveFrom:AppBahwService(session:app).today);rule.measure = .count;rule.target=2;rule.unit="كوب"
        let encoded=try JSONDecoder().decode(MadarCore.JSONValue.self,from:JSONEncoder().encode(rule))
        try await app.executeDiaryCommand("habit.save",payload:["id":.string(id.uuidString),"name":.string("الماء"),"rule":encoded])
        for _ in 0..<2{try await app.executeDiaryCommand("habit.complete",payload:["id":.string(id.uuidString)])}
        let now=app.prayerNow(),envelope=try XCTUnwrap(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:now))
        XCTAssertEqual(envelope.payload.rows.count,1);XCTAssertEqual(envelope.payload.rows.first?.value,"٢ من ٢ كوب");XCTAssertEqual(envelope.payload.rows.first?.done,true)
        XCTAssertNil(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:now.addingTimeInterval(4000)))
        for room in BuiltRoomWidget.allCases{XCTAssertNotNil(app.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:now))}
        let year=try XCTUnwrap(app.snapshotStore.read("year",as:RoomWidgetSnapshot.self,now:now))
        XCTAssertTrue(year.payload.rows.allSatisfy{$0.detail.contains(where:{$0.isNumber})})
        let upcoming=try XCTUnwrap(app.snapshotStore.read("upcoming",as:RoomWidgetSnapshot.self,now:now))
        XCTAssertFalse(upcoming.payload.rows.isEmpty);XCTAssertTrue(upcoming.payload.rows.allSatisfy{$0.value.contains(where:{$0.isNumber})})

    }
    func testAdjustedFajrOwnsWidgetDayAndExpiry() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("WidgetFajr-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let app=try AppSession(container:MadarContainerFactory.makeLocal(at:root),groupDirectory:root)
        try await app.applySettingsAndWait(["salah.offsets":.object(["fajr":.number(20),"dhuhr":.number(0),"asr":.number(0),"maghrib":.number(0),"isha":.number(0)])])
        let civil=try GregorianDay("2026-10-15"),base=try XCTUnwrap(PrayerTimesEngine.calculate(day:civil,place:.riyadh)),instant=base.fajr.addingTimeInterval(600)
        let service=AppBahwService(session:app,evaluationDate:instant)
        XCTAssertEqual(service.today,civil.adding(days:-1))
        try app.publishRoomWidgetSnapshots(at:instant)
        let snapshot=try XCTUnwrap(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:instant))
        XCTAssertEqual(snapshot.dayKey,civil.adding(days:-1).description)
        XCTAssertEqual(snapshot.validUntil.timeIntervalSince1970,base.fajr.addingTimeInterval(1200).timeIntervalSince1970,accuracy:1)
    }
    func testProtectedPayloadsOmitPersonalRowsAndDiaryWritingNeverContainsDiaryText() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetPrivate-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container)
        let entry=Entry();entry.dayKey=AppBahwService(session:app).today.description;entry.text="SECRET-ENTRY-NEVER-WIDGET";context.insert(entry)
        let letter=Letter();letter.text="SECRET-SEALED-LETTER";context.insert(letter);try context.save()
        let payloads=app.roomWidgetPayloads(locked:true)
        XCTAssertEqual(payloads[.habits]?.rows,[]);XCTAssertEqual(payloads[.upcoming]?.rows,[])
        XCTAssertTrue(payloads[.habits]?.locked == true)
        let diary=try XCTUnwrap(payloads[.diaryWrite]),data=try JSONEncoder().encode(diary),text=try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertFalse(text.contains("SECRET"));XCTAssertTrue(diary.rows.isEmpty)
        XCTAssertFalse(diary.datePrimary.isEmpty);XCTAssertFalse(diary.dateSecondary.isEmpty)
    }
    func testDefaultWidgetRoutesAndExistingPrayerAliasReachBuiltRooms() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetRoutes-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let app=try AppSession(container:MadarContainerFactory.makeLocal(at:root),groupDirectory:root)
        for url in ["madar://salah","madar://prayer"]{app.open(URL(string:url)!);XCTAssertEqual(app.selectedTab,"prayer");XCTAssertNil(app.errorMessage)}
        for room in BuiltRoomWidget.allCases{app.open(URL(string:room.route)!);XCTAssertNil(app.errorMessage)}
        XCTAssertEqual(app.selectedTab,"notes");XCTAssertEqual(app.diaryRoute?.path,["write"])
        app.open(URL(string:"madar://prayer?unexpected=1")!);XCTAssertNotNil(app.errorMessage)
    }
}
