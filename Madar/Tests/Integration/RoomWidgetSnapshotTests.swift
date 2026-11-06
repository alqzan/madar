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
        // The schema default locks the whole app, which keeps personal rows out of widgets; this test reads them unlocked.
        try await app.applySettingsAndWait(["core.faceIDLock":.string("none")])
        var rule=HabitRule(effectiveFrom:AppBahwService(session:app).today);rule.measure = .count;rule.target=2;rule.unit="كوب"
        let encoded=try JSONDecoder().decode(MadarCore.JSONValue.self,from:JSONEncoder().encode(rule))
        try await app.executeDiaryCommand("habit.save",payload:["id":.string(id.uuidString),"name":.string("الماء"),"rule":encoded])
        for _ in 0..<2{try await app.executeDiaryCommand("habit.complete",payload:["id":.string(id.uuidString)])}
        let now=app.prayerNow(),envelope=try XCTUnwrap(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:now))
        XCTAssertEqual(envelope.payload.rows.count,1);XCTAssertEqual(envelope.payload.rows.first?.value,"٢ من كوبين");XCTAssertEqual(envelope.payload.rows.first?.done,true)
        XCTAssertNil(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:now.addingTimeInterval(4000)))
        for room in BuiltRoomWidget.allCases where room != .mihbara{XCTAssertNotNil(app.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:now))}
        XCTAssertNotNil(app.snapshotStore.read(BuiltRoomWidget.mihbara.rawValue,as:MihbaraSnapshot.self,now:now))
        let year=try XCTUnwrap(app.snapshotStore.read("year",as:RoomWidgetSnapshot.self,now:now))
        XCTAssertTrue(year.payload.rows.allSatisfy{$0.detail.contains(where:{$0.isNumber})})
        let upcoming=try XCTUnwrap(app.snapshotStore.read("upcoming",as:RoomWidgetSnapshot.self,now:now))
        // A season can fall on today (اليوم) or tomorrow (غدًا), so the value is a number or one of those words, never empty.
        XCTAssertFalse(upcoming.payload.rows.isEmpty);XCTAssertTrue(upcoming.payload.rows.allSatisfy{$0.value.contains(where:{$0.isNumber}) || ["اليوم","غدًا","يومان"].contains($0.value)})
        let habits=try XCTUnwrap(app.snapshotStore.read("habits",as:RoomWidgetSnapshot.self,now:now)).payload
        XCTAssertEqual(habits.heading,"أتممت عادتك","one due habit, finished: say so instead of a bare count")
        XCTAssertEqual(habits.periods.first{$0.id=="daily"}?.value,"تمّت");XCTAssertEqual(habits.periods.first{$0.id=="daily"}?.detail,"تمّ")
        XCTAssertEqual(habits.periods.first{$0.id=="weekly"}?.value,"لا شيء مستحق");XCTAssertEqual(habits.periods.first{$0.id=="weekly"}?.detail,"")
        let daily = try XCTUnwrap(habits.periods.first { $0.id == "daily" })
        XCTAssertEqual(daily.completedCount, 1); XCTAssertEqual(daily.targetCount, 1)
        XCTAssertEqual(habits.periods.first { $0.id == "weekly" }?.targetCount, 0)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(daily)) as? [String: Any])
        legacyJSON.removeValue(forKey: "completedCount"); legacyJSON.removeValue(forKey: "targetCount")
        let legacy = try JSONDecoder().decode(RoomWidgetSnapshot.Row.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssertNil(legacy.completedCount); XCTAssertNil(legacy.targetCount); XCTAssertEqual(legacy.value, "تمّت")

    }
    /// Expected strings come from Arabic number agreement (singular, dual, 3 to 10, 11 and up), not from the code's own output.
    func testWidgetCopyAgreesWithItsNumbersInArabic() {
        let d=MadarNumberFormatter(style:.hindi)
        XCTAssertEqual(WidgetCopy.habitProgress(value:0,target:1,measure:.once,unit:nil,digits:d),"لم تتم بعد")
        XCTAssertEqual(WidgetCopy.habitProgress(value:1,target:1,measure:.once,unit:nil,digits:d),"تمّت")
        XCTAssertEqual(WidgetCopy.habitProgress(value:1,target:3,measure:.count,unit:nil,digits:d),"١ من ٣ مرات")
        XCTAssertEqual(WidgetCopy.habitProgress(value:1,target:2,measure:.count,unit:nil,digits:d),"١ من مرتين")
        XCTAssertEqual(WidgetCopy.habitProgress(value:200,target:8000,measure:.count,unit:"steps",digits:d),"٢٠٠ من ٨٠٠٠ خطوة")
        XCTAssertEqual(WidgetCopy.habitProgress(value:5,target:30,measure:.duration,unit:"minutes",digits:d),"٥ من ٣٠ دقيقة")
        XCTAssertEqual(WidgetCopy.habitProgress(value:0,target:8,measure:.count,unit:"كوب",digits:d),"الهدف: ٨ أكواب")
        XCTAssertEqual(WidgetCopy.habitProgress(value:1,target:2,measure:.count,unit:"كوب",digits:d),"١ من كوبين")
        XCTAssertEqual(WidgetCopy.habitProgress(value:3,target:15,measure:.count,unit:"كوب",digits:d),"٣ من ١٥ كوبًا")
        XCTAssertEqual(WidgetCopy.periodProgress(met:0,total:1,digits:d),"عادة واحدة تنتظرك")
        XCTAssertEqual(WidgetCopy.periodProgress(met:0,total:2,digits:d),"عادتان تنتظرانك")
        XCTAssertEqual(WidgetCopy.periodProgress(met:0,total:3,digits:d),"٣ عادات تنتظرك")
        XCTAssertEqual(WidgetCopy.periodProgress(met:0,total:11,digits:d),"١١ عادة تنتظرك")
        XCTAssertEqual(WidgetCopy.periodProgress(met:2,total:5,digits:d),"تمّت ٢ من ٥")
        XCTAssertEqual(WidgetCopy.periodProgress(met:5,total:5,digits:d),"تمّت كلها")
        XCTAssertEqual(WidgetCopy.habitsHeading(met:0,total:3,digits:d),"٣ عادات تنتظرك")
        XCTAssertEqual([0,1,2,3,11].map{WidgetCopy.daysLeft($0,digits:d,dayCount:{$0>10 ? "يومًا" : "أيام"})},["اليوم","غدًا","يومان","٣ أيام","١١ يومًا"])
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
    func testActiveTripMethodOwnsWidgetDayAndExpiry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetTripMethod-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = ISO8601DateFormatter().date(from: "2026-03-20T04:08:00Z")!
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        try await app.applySettingsAndWait(["core.dayStart": .string("fajr"), "salah.method": .string("mwl"),
                                            "salah.tripMethod": .string("egyptian"), "salah.highLatitudeRule": .string("twilightAngle")])
        let context = ModelContext(container), trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = ISO8601DateFormatter().date(from: "2026-03-20T04:00:00Z")
        context.insert(trip); try context.save()

        try app.publishRoomWidgetSnapshots(at: instant)
        let snapshot = try XCTUnwrap(app.snapshotStore.read("habits", as: RoomWidgetSnapshot.self, now: instant))
        XCTAssertEqual(snapshot.dayKey, "2026-03-20", "Egyptian trip Fajr is before 04:08; MWL home Fajr is after it")
        XCTAssertEqual(snapshot.tzID, "Europe/London")
        let place = try ActivePlace(latitude: 51.5074, longitude: -0.1278, timeZoneID: "Europe/London")
        let options = try PrayerCalculationOptions(method: .egyptian, highLatitudeRule: .twilightAngle)
        let nextFajr = try XCTUnwrap(PrayerTimesEngine.calculate(day: GregorianDay("2026-03-21"), place: place, options: options)?.fajr)
        XCTAssertEqual(snapshot.validUntil, min(instant.addingTimeInterval(3600), nextFajr))
    }
    func testProtectedPayloadsOmitPersonalRowsAndDiaryWritingNeverContainsDiaryText() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetPrivate-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container)
        let entry=Entry();entry.dayKey=AppBahwService(session:app).today.description;entry.text="SECRET-ENTRY-NEVER-WIDGET";context.insert(entry)
        let letter=Letter();letter.text="SECRET-SEALED-LETTER";context.insert(letter);try context.save()
        let payloads=app.roomWidgetPayloads(locked:true)
        XCTAssertEqual(payloads[.habits]?.rows,[]);XCTAssertEqual(payloads[.upcoming]?.rows,[])
        XCTAssertEqual(payloads[.habits]?.upcomingHabits,[])
        XCTAssertTrue(payloads[.habits]?.locked == true)
        let diary=try XCTUnwrap(payloads[.diaryWrite]),data=try JSONEncoder().encode(diary),text=try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertFalse(text.contains("SECRET"));XCTAssertTrue(diary.rows.isEmpty)
        XCTAssertFalse(diary.datePrimary.isEmpty);XCTAssertFalse(diary.dateSecondary.isEmpty)
        let mihbara=app.mihbaraWidgetSnapshot(locked:true)
        XCTAssertNil(mihbara.currentBook);XCTAssertNil(mihbara.hadithToday);XCTAssertEqual(mihbara.shelfCount,0);XCTAssertNil(mihbara.lastNotebookLine)
    }
    func testHabitReadFailureDoesNotPublishAnEmptyHabitState() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"RoomWidgetHabitReadFailure-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root)
        let payload=try XCTUnwrap(app.roomWidgetPayloads(locked:false,at:app.prayerNow(),readHabitReadings:{throw CocoaError(.fileReadUnknown)})[.habits])
        XCTAssertEqual(payload.heading,"تعذّر تحديث العادات")
        XCTAssertEqual(payload.emptyTitle,"افتح مدار لإعادة المحاولة")
        XCTAssertTrue(payload.rows.isEmpty)
        XCTAssertTrue(payload.periods.isEmpty)
        XCTAssertFalse(payload.locked)
    }
    func testUpcomingHabitWidgetUsesFixedRecurringDatesAndLastCompletion() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetHabitComing-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container)
        try await app.applySettingsAndWait(["core.faceIDLock":.string("none"),"core.dayStart":.string("midnight")])
        let today=try GregorianDay("2026-10-31"),zone=TimeZone(identifier:"Asia/Riyadh")!,now=ISO8601DateFormatter().date(from:"2026-10-31T12:00:00+03:00")!
        var nextOrder=0
        func addHabit(_ name:String,_ frequency:String,weekdays:[String]?=nil,monthDays:[Int]?=nil,yearMonth:Int?=nil,yearDay:Int?=nil,lastDay:String,lastPeriod:String) throws {
            let id=UUID(),habit=Habit();habit.id=id;habit.name=name;habit.order=nextOrder;nextOrder+=1;habit.startDate=today.adding(days:-365).date(in:zone);context.insert(habit)
            let policy=HabitPolicy();policy.habitID=id;policy.effectiveFrom=today.adding(days:-365).description;policy.frequency=frequency;policy.measure="once";policy.target=1;policy.weekdays=weekdays;policy.monthDays=monthDays;policy.monthCalendar="gregorian";policy.yearMonth=yearMonth;policy.yearDay=yearDay;context.insert(policy)
            let event=HabitEvent();event.habitID=id;event.dayKey=lastDay;event.periodKey=lastPeriod;event.delta=1;event.eventAt=try GregorianDay(lastDay).date(in:zone).addingTimeInterval(12*3600);event.tzID="Asia/Riyadh";event.dayPolicy="midnight@1";context.insert(event)
        }
        try addHabit("مشوار الأربعاء","weekly",weekdays:["wed"],lastDay:"2026-10-28",lastPeriod:"2026-10-24")
        try addHabit("ورد الشهر","monthly",monthDays:[15],lastDay:"2026-10-29",lastPeriod:"g:2026-10")
        try addHabit("مراجعة السنة","yearly",yearMonth:12,yearDay:15,lastDay:"2026-10-29",lastPeriod:"g:2026")
        try context.save()

        let snapshot=try XCTUnwrap(app.roomWidgetPayloads(locked:false,at:now)[.habits])
        let rows=try XCTUnwrap(snapshot.upcomingHabits)
        XCTAssertEqual(rows.map(\.title),["مشوار الأربعاء","ورد الشهر","مراجعة السنة"])
        XCTAssertEqual(rows.map(\.value),["بعد ٤ أيام","بعد ١٥ يومًا","بعد ٤٥ يومًا"])
        XCTAssertEqual(rows.map(\.detail),["آخر مرة قبل ٣ أيام","آخر مرة قبل يومين","آخر مرة قبل يومين"])
        XCTAssertEqual(rows.map(\.route).count,3)
    }
    func testUpcomingHabitWidgetOmitsRecurrencesWithoutANamedDate() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetHabitComingEmpty-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container)
        try await app.applySettingsAndWait(["core.faceIDLock":.string("none"),"core.dayStart":.string("midnight")])
        let today=try GregorianDay("2026-10-31"),zone=TimeZone(identifier:"Asia/Riyadh")!
        for (index,frequency) in ["daily","weekly","monthly"].enumerated() {
            let habit=Habit();habit.id=UUID();habit.name="عادة \(index)";habit.startDate=today.adding(days:-30).date(in:zone);context.insert(habit)
            let policy=HabitPolicy();policy.habitID=habit.id;policy.effectiveFrom=today.adding(days:-30).description;policy.frequency=frequency;policy.measure="once";policy.target=1;policy.monthCalendar="gregorian";context.insert(policy)
        }
        try context.save()
        let snapshot=try XCTUnwrap(app.roomWidgetPayloads(locked:false,at:ISO8601DateFormatter().date(from:"2026-10-31T12:00:00+03:00")!)[.habits])
        XCTAssertTrue(snapshot.upcomingHabits?.isEmpty == true)
    }
    func testMihbaraSnapshotUsesOnlyEligibleBooksAndNotebookLines() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetMihbara-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container),now=app.prayerNow()
        app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.faceIDLock":.string("none")])
        let book=Book();book.id=UUID();book.title="على رف القراءة";book.author="مؤلف";book.kind="paper";book.shelf="reading";book.currentPage=14;book.pages=240;book.updatedAt=now;context.insert(book)
        let privateNote=NotebookNote();privateNote.text="SECRET-PRIVATE-NOTE";privateNote.isPrivate=true;privateNote.link="general";privateNote.updatedAt=now.addingTimeInterval(2);context.insert(privateNote)
        let diaryNote=NotebookNote();diaryNote.text="SECRET-DIARY-LINE";diaryNote.isPrivate=false;diaryNote.link="fromDiary";diaryNote.targetID=UUID();diaryNote.updatedAt=now.addingTimeInterval(3);context.insert(diaryNote)
        let publicNote=NotebookNote();publicNote.text=String(repeating:"م",count:100);publicNote.isPrivate=false;publicNote.link="idea";publicNote.updatedAt=now.addingTimeInterval(4);context.insert(publicNote)
        try context.save()
        // FB-39: the notebook has no entry point, so its text never reaches the widget, even with the opt-in.
        XCTAssertNil(app.mihbaraWidgetSnapshot(locked:false,at:now).lastNotebookLine)
        try await app.applySettingsAndWait(["notes.widgetContent":.bool(true)])
        try app.publishRoomWidgetSnapshots(at:now)

        let envelope=try XCTUnwrap(app.snapshotStore.read(BuiltRoomWidget.mihbara.rawValue,as:MihbaraSnapshot.self,now:now))
        XCTAssertEqual(envelope.payload.currentBook?.id,book.id);XCTAssertEqual(envelope.payload.currentBook?.currentPage,14);XCTAssertEqual(envelope.payload.currentBook?.pages,240)
        XCTAssertEqual(envelope.payload.shelfCount,1);XCTAssertNil(envelope.payload.lastNotebookLine);XCTAssertNil(envelope.payload.hadithToday)
        let encoded=try JSONEncoder().encode(envelope.payload),json=String(decoding:encoded,as:UTF8.self)
        XCTAssertFalse(json.contains("SECRET-PRIVATE-NOTE"));XCTAssertFalse(json.contains("SECRET-DIARY-LINE"));XCTAssertFalse(json.contains("مممم"))
        XCTAssertEqual(envelope.privacy.notesLocked,false)
        let locked=app.mihbaraWidgetSnapshot(locked:true,at:now)
        XCTAssertNil(locked.currentBook);XCTAssertNil(locked.hadithToday);XCTAssertEqual(locked.shelfCount,0);XCTAssertNil(locked.lastNotebookLine)
    }
    /// RD7 (owner, 16 Oct): diary text reaches the widget payload only with the opt-in, and never under the app lock.
    func testDiaryContentRowsNeedTheOptInAndNeverCrossTheLock() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetDiary-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),app=try AppSession(container:container,groupDirectory:root),context=ModelContext(container)
        let today=AppBahwService(session:app).today
        let entry=Entry();entry.dayKey=today.description;entry.text="سطر اصطناعي للودجة\nسطر ثانٍ لا يظهر";entry.eventAt=app.prayerNow();context.insert(entry)
        let niyya=Niyya();niyya.dayKey=today.description;niyya.text="نيّة اصطناعية";context.insert(niyya)
        let letter=Letter();letter.text="SECRET-SEALED-LETTER";context.insert(letter);try context.save()
        XCTAssertEqual(app.schema.settings.first{$0.key=="notes.widgetContent"}?.defaultValue,.bool(false))
        XCTAssertEqual(app.roomWidgetPayloads(locked:false)[.diaryWrite]?.rows,[],"Off by default: no diary text")
        try await app.applySettingsAndWait(["notes.widgetContent":.bool(true)])
        let rows=try XCTUnwrap(app.roomWidgetPayloads(locked:false)[.diaryWrite]).rows
        XCTAssertEqual(rows.first{$0.id=="intention"}?.value,"نيّة اصطناعية")
        XCTAssertEqual(rows.first{$0.id=="lastLine"}?.value,"سطر اصطناعي للودجة")
        XCTAssertFalse(rows.first{$0.id=="lastLine"}?.secondDate.isEmpty ?? true,"Both calendars")
        let text=try XCTUnwrap(String(data:JSONEncoder().encode(rows),encoding:.utf8))
        XCTAssertFalse(text.contains("SECRET"));XCTAssertFalse(text.contains("سطر ثانٍ"))
        XCTAssertEqual(app.roomWidgetPayloads(locked:true)[.diaryWrite]?.rows,[],"The whole-app lock wins over the opt-in")
    }
    func testDefaultWidgetRoutesAndExistingPrayerAliasReachBuiltRooms() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("RoomWidgetRoutes-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let app=try AppSession(container:MadarContainerFactory.makeLocal(at:root),groupDirectory:root)
        for url in ["madar://salah","madar://prayer"]{app.open(URL(string:url)!);XCTAssertEqual(app.selectedTab,"prayer");XCTAssertNil(app.errorMessage)}
        for room in BuiltRoomWidget.allCases{app.open(URL(string:room.route)!);XCTAssertNil(app.errorMessage)}
        app.open(URL(string: BuiltRoomWidget.money.route)!)
        XCTAssertEqual(app.selectedTab, "money"); XCTAssertFalse(app.moneyOpen)
        app.open(URL(string: BuiltRoomWidget.mihbara.route)!)
        XCTAssertEqual(app.selectedTab, "mihbara"); XCTAssertFalse(app.mihbaraOpen)
        app.open(URL(string:BuiltRoomWidget.diaryWrite.route)!)
        XCTAssertEqual(app.selectedTab,"notes");XCTAssertEqual(app.diaryRoute?.path,["write"])
        app.open(URL(string:"madar://prayer?unexpected=1")!);XCTAssertNotNil(app.errorMessage)
    }
}
