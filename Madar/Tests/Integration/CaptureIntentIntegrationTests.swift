import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
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
        let held = await app.handleIntentRequest(.capture(text: "قهوة ١٨", id: id))
        XCTAssertFalse(held, "A diary line waits while the diary is locked")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)
        app.authorizeProtectedData()
        let applied = await app.handleIntentRequest(.capture(text: "قهوة ١٨", id: id))
        XCTAssertTrue(applied)
        let again = await app.handleIntentRequest(.capture(text: "قهوة ١٨", id: id))
        XCTAssertTrue(again)
        let lines = try AppDiaryService(app: app, clock: { .now }).home().todayPage.lines.filter { $0.kind == "normal" }.map(\.text)
        XCTAssertEqual(lines, ["قهوة ١٨"], "Before M5 money text is a line on today's page, written once per request")
        XCTAssertEqual(app.selectedTab, "notes")
        _ = await app.handleIntentRequest(.diaryLine(text: "فكرة: كتاب عن الجيران", day: "today", id: UUID()))
        XCTAssertTrue(try AppDiaryService(app: app, clock: { .now }).home().todayPage.lines.contains { $0.text == "فكرة: كتاب عن الجيران" })
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
