import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarMoney
@testable import Madar

/// M4-F01: Siri/Shortcuts requests that need the app run through the app's own command path,
/// wait behind the diary lock, and never write twice for one request (§9, §14, §16, RA2).
@MainActor final class CaptureIntentIntegrationTests: XCTestCase {
    private func session() throws -> (AppSession, ModelContainer) {
        let root = FileManager.default.temporaryDirectory.appending(path: "CaptureIntent-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), today = GregorianDay.containing(.now, in: TimeZone(identifier: "Asia/Riyadh")!)
        _ = try SettingsStore(context: context).stage(["salah.trackingStart": .object(["dayKey": .string(today.adding(days: -7).description), "edits": .number(0)])])
        try context.save()
        return (try AppSession(container: container, groupDirectory: root), container)
    }

    func testCaptureWaitsForTheDiaryLockAndWritesOnce() async throws {
        let (app, container) = try session()
        let id = UUID()
        let held = await app.handleIntentRequest(.capture(text: "اتصلت بخالتي", id: id))
        XCTAssertFalse(held, "A diary line waits while the diary is locked")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)
        app.authorizeProtectedData()
        let applied = await app.handleIntentRequest(.capture(text: "اتصلت بخالتي", id: id))
        XCTAssertTrue(applied)
        let again = await app.handleIntentRequest(.capture(text: "اتصلت بخالتي", id: id))
        XCTAssertTrue(again)
        let lines = try AppDiaryService(app: app, clock: { .now }).home().todayPage.lines.filter { $0.kind == "normal" }.map(\.text)
        XCTAssertEqual(lines, ["اتصلت بخالتي"], "Unclassified text is a diary line, written once per request")
        XCTAssertEqual(app.selectedTab, "notes")
        _ = await app.handleIntentRequest(.diaryLine(text: "فكرة: كتاب عن الجيران", day: "today", id: UUID()))
        XCTAssertTrue(try AppDiaryService(app: app, clock: { .now }).home().todayPage.lines.contains { $0.text == "فكرة: كتاب عن الجيران" })
    }

    func testCaptureRequestsSurviveStoreMaintenance() async throws {
        let (app, container) = try session()
        app.authorizeProtectedData()
        let handoff = MadarIntentHandoff.shared
        await handoff.attach { [weak app] request in await app?.handleIntentRequest(request) ?? false }
        try await app.quiesceWriters()

        let lineID = UUID()
        let lineHeld = await handoff.submit(.diaryLine(text: "اتصلت بخالتي", day: "today", id: lineID))
        XCTAssertFalse(lineHeld, "A diary write rejected by maintenance must remain held.")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)

        let prayerHeld = await handoff.submit(.capture(text: "صلّيت الفجر جماعة", id: UUID()))
        XCTAssertFalse(prayerHeld, "A prayer write rejected by maintenance must remain held.")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()), 0)

        app.resumeWriters()
        for _ in 0..<100 {
            let entries = try ModelContext(container).fetch(FetchDescriptor<Entry>())
            let prayers = try ModelContext(container).fetch(FetchDescriptor<PrayerLog>())
            if entries.contains(where: { $0.text == "اتصلت بخالتي" }) && prayers.contains(where: { $0.prayer == "fajr" && $0.status == "jamaah" }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Entry>()).filter { $0.text == "اتصلت بخالتي" }.count, 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).filter { $0.prayer == "fajr" && $0.status == "jamaah" }.count, 1)
    }

    func testFailedMihbaraIdeaCaptureIsReportedAsFinalFailure() async throws {
        let (app, _) = try session()
        app.authorizeProtectedData()
        app.failFirstNotebookSave = true
        let request = MadarIntentRequest.capture(text: "فكرة: حديقة صغيرة", id: UUID())
        let completed = await app.handleIntentRequest(request)
        XCTAssertTrue(completed, "A permanent command failure is reported; it is not retained as a locked request.")
        XCTAssertEqual(MadarIntentHandoff.shared.takeFailure(request), "لم تُحفظ الفكرة في دفتر المحبرة. أعد المحاولة.")
    }
    func testConcurrentIntentSubmissionWaitsUntilItsRequestIsHandled() async throws {
        let handoff = MadarIntentHandoff()
        let first = MadarIntentRequest.capture(text: "مصروف أول", id: UUID())
        let second = MadarIntentRequest.diaryLine(text: "سطر ثان", day: "today", id: UUID())
        var handled: [MadarIntentRequest] = []
        await handoff.attach { request in
            if request == first { try? await Task.sleep(for: .milliseconds(100)) }
            handled.append(request)
            return true
        }
        let firstSubmission = Task { await handoff.submit(first) }
        try await Task.sleep(for: .milliseconds(10))
        let secondApplied = await handoff.submit(second)
        let firstApplied = await firstSubmission.value
        XCTAssertTrue(firstApplied)
        XCTAssertTrue(secondApplied, "A request handled by the active flush must not be reported as merely queued.")
        XCTAssertEqual(handled, [first, second])
    }
    func testYesterdayDiaryIntentOpensThePageItWrites() async throws {
        let (app, container) = try session()
        app.authorizeProtectedData()
        let today = try DiaryLineRenderer.today(context: ModelContext(container), now: app.prayerNow())
        let yesterday = today.adding(days: -1)
        let applied = await app.handleIntentRequest(.diaryLine(text: "سطر عن الأمس", day: "yesterday", id: UUID()))
        XCTAssertTrue(applied)
        XCTAssertEqual(app.diaryRoute?.path, ["day", yesterday.description])
        let saved = try ModelContext(container).fetch(FetchDescriptor<Entry>()).first { $0.text == "سطر عن الأمس" }
        XCTAssertEqual(saved?.dayKey, yesterday.description)
    }

    func testMihbaraIdeaCaptureWritesOnePrivateNoteAndOpensItsRoom() async throws {
        let (app,container)=try session(),id=UUID()
        app.authorizeProtectedData()
        let applied=await app.handleIntentRequest(.capture(text:"فكرة: خطة قراءة جديدة",id:id))
        XCTAssertTrue(applied)
        XCTAssertEqual(app.selectedTab,"mihbara");XCTAssertFalse(app.mihbaraOpen);XCTAssertNotNil(app.undoToken)
        let rows=try ModelContext(container).fetch(FetchDescriptor<NotebookNote>()),note=try XCTUnwrap(rows.first{$0.id==id})
        XCTAssertTrue(note.isPrivate);XCTAssertEqual(note.link,"general");XCTAssertEqual(note.text,"خطة قراءة جديدة")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()),0)
        let replayed=await app.handleIntentRequest(.capture(text:"فكرة: خطة قراءة جديدة",id:id))
        XCTAssertTrue(replayed)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<NotebookNote>()),1)
    }

    func testMoneyCaptureOpensConfirmationWithoutWritingOrRequiringDiaryUnlock() async throws {
        let (app, container) = try session(), id = UUID(), secondID = UUID()
        let applied = await app.handleIntentRequest(.capture(text: "قهوة ١٨", id: id)); XCTAssertTrue(applied)
        XCTAssertEqual(app.moneyExpenseSeed?.amount, "١٨"); XCTAssertEqual(app.moneyExpenseSeed?.merchant, "قهوة"); XCTAssertEqual(app.moneyExpenseSeed?.id, id)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)
        let secondApplied = await app.handleIntentRequest(.capture(text: "مصروف: شاي ٧", id: secondID))
        XCTAssertTrue(secondApplied)
        let secondReplay = await app.handleIntentRequest(.capture(text: "مصروف: شاي ٧", id: secondID))
        XCTAssertTrue(secondReplay, "A replayed request with the same id is handled without duplicating the queued expense.")
        XCTAssertEqual(app.moneyExpenseSeed?.id, id, "A later Capture request must not replace the open expense draft.")
        let requestedMethod = "card:" + UUID().uuidString
        app.open(URL(string: "madar://mal/add?amount=1800&merchant=coffee&method=" + requestedMethod)!)
        XCTAssertEqual(app.moneyExpenseSeed?.id, id, "A later add link must not replace the open expense draft.")
        app.moneyExpenseSeed = nil
        app.presentNextMoneyExpenseSeed()
        XCTAssertEqual(app.moneyExpenseSeed?.id, secondID, "Queued Capture requests are presented first in FIFO order.")
        XCTAssertEqual(app.moneyExpenseSeed?.amount, "٧"); XCTAssertEqual(app.moneyExpenseSeed?.merchant, "شاي")
        app.moneyExpenseSeed = nil
        app.presentNextMoneyExpenseSeed()
        XCTAssertEqual(MoneyAmountInput.minor(app.moneyExpenseSeed?.amount ?? "", exponent: 2), 1800)
        XCTAssertEqual(app.moneyExpenseSeed?.method, requestedMethod)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MoneyTransaction>()), 0, "A public link can prefill but never write")
    }
    func testPrayerReportLogsAndAMissingStateOpensTheLogSheet() async throws {
        let (app, container) = try session()
        // Fajr of the current prayer day has always begun, whatever the hour the test runs.
        _ = await app.handleIntentRequest(.capture(text: "صلّيت الفجر جماعة", id: UUID()))
        var log: PrayerLog?
        for _ in 0..<100 where log == nil {
            log = try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first { $0.prayer == "fajr" && $0.deletedAt == nil }
            if log == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertEqual(log?.status, "jamaah")
        XCTAssertEqual(app.selectedTab, "prayer")
        _ = await app.handleIntentRequest(.capture(text: "صليت المغرب", id: UUID()))
        XCTAssertEqual(app.prayerLogRequest, .maghrib, "The state was not said, so the log sheet asks")
        _ = await app.handleIntentRequest(.capture(text: "   ", id: UUID()))
        XCTAssertNotNil(app.errorMessage)
    }

    func testCaptureDialogDoesNotSayPrayerWasAddedBeforeItsStateIsChosen() {
        let incomplete = CaptureRouter.route("صليت المغرب")
        XCTAssertEqual(CaptureIntentResponse.make(route: incomplete, handled: true), .choosePrayerStatus)
        XCTAssertEqual(CaptureIntentResponse.make(route: incomplete, handled: false), .heldPrayer)

        let complete = CaptureRouter.route("صليت الفجر جماعة")
        XCTAssertEqual(CaptureIntentResponse.make(route: complete, handled: true), .prayerRequestSent)
    }

    func testHabitShortcutsListOnlyCustomHabitsAndHideUnderAppLock() async throws {
        let (app, _) = try session()
        app.authorizeProtectedData()
        let water = UUID(), reading = UUID(), today = GregorianDay.containing(app.prayerNow(), in: app.activePlace.timeZone)
        func rule(_ measure: HabitMeasure, unit: String?, target: Int) throws -> MadarCore.JSONValue {
            var r = HabitRule(effectiveFrom: today); r.measure = measure; r.unit = unit; r.target = target
            return try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(r))
        }
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight")])
        try await app.executeDiaryCommand("habit.save", payload: ["id": .string(water.uuidString), "name": .string("ماء"), "rule": try rule(.count, unit: nil, target: 8)])
        try await app.executeDiaryCommand("habit.save", payload: ["id": .string(reading.uuidString), "name": .string("قراءة"), "rule": try rule(.duration, unit: "minutes", target: 30)])
        let until = Date().addingTimeInterval(3600)
        let payload = app.habitShortcutPayload(locked: false, at: app.prayerNow(), periodsValidUntil: until)
        XCTAssertEqual(Set(payload.items.map(\.title)), ["ماء", "قراءة"])
        XCTAssertEqual(payload.items.first { $0.id == water }?.step, 1)
        XCTAssertEqual(payload.items.first { $0.id == reading }?.step, 15, "Same step as the in-app button")
        XCTAssertEqual(payload.items.first { $0.id == water }?.periodKey, today.description)
        XCTAssertEqual(payload.periodsValidUntil, until)
        XCTAssertTrue(app.habitShortcutPayload(locked: true, at: app.prayerNow(), periodsValidUntil: until).items.isEmpty)
    }
}
