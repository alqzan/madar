import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarSnapshots
@testable import Madar

@MainActor final class WidgetMakerSnapshotTests: XCTestCase {
    func testSnapshotPublicationSharesHabitReadAndPreservesFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SharedWidgetHabits-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppSession(container: MadarContainerFactory.makeLocal(at: root), groupDirectory: root)
        var first = WidgetMakerDraft(); first.name = "أولى"; first.items = ["habitsToday"]
        var second = WidgetMakerDraft(); second.name = "ثانية"; second.items = ["habitsToday"]
        try await app.saveWidget(first); try await app.saveWidget(second)
        var calls = 0
        try app.publishSnapshotNow(readHabitReadings: { calls += 1; return [] })
        XCTAssertEqual(calls, 1, "A publication with multiple widgets must read habits only once")
        let at = app.prayerNow()
        let catalog = try XCTUnwrap(app.snapshotStore.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: at))
        XCTAssertEqual(catalog.payload.configs.count, 2)
        calls = 0
        try app.publishSnapshotNow(readHabitReadings: { calls += 1; throw CocoaError(.fileReadUnknown) })
        XCTAssertEqual(calls, 1, "A failed read is shared only for the current publication")
        let habits = try XCTUnwrap(app.snapshotStore.read("habits", as: RoomWidgetSnapshot.self, now: app.prayerNow()))
        XCTAssertEqual(habits.payload.heading, "تعذّر تحديث العادات")
        XCTAssertTrue(habits.payload.rows.isEmpty)
    }
    func testIndividualHabitIdentitySurvivesTheWidgetJSON() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetHabitIdentity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight")])
        let context = ModelContext(container), today = AppBahwService(session: app).today
        let habit = Habit(); habit.name = "الماء"; habit.startDate = today.date(in: app.activePlace.timeZone); context.insert(habit)
        let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = today.description; policy.measure = "count"; policy.target = 8; policy.unit = "كوب"; context.insert(policy)
        try context.save()
        var draft = WidgetMakerDraft(); draft.name = "مائي"; draft.items = ["habit:" + habit.id.uuidString]
        try await app.saveWidget(draft)
        let value = try XCTUnwrap(app.snapshotStore.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: app.prayerNow()))
        let row = try XCTUnwrap(value.payload.configs.first?.rows.first)
        XCTAssertEqual(row.title, "الماء"); XCTAssertEqual(row.glyph, "drop")
        XCTAssertEqual(row.habitID, habit.id)
    }
    func testCatalogHasMetadataOnlyAndValuesRespectPrivacyAndExpiry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetMakerSnapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        let now = app.prayerNow(), today = AppBahwService(session: app).today, context = ModelContext(container)
        let entry = Entry(); entry.dayKey = today.description; entry.text = "VISIBLE-ONLY-WITH-OPT-IN"; entry.eventAt = now; context.insert(entry)
        let letter = Letter(); letter.text = "SECRET-SEALED-LETTER"; context.insert(letter)
        let account = Account(); account.balanceMinor = 500037; account.balanceAt = now.addingTimeInterval(-86400); context.insert(account)
        try context.save()
        var draft = WidgetMakerDraft(); draft.name = "ودجة تجريبية"; draft.items = ["moneyNow", "diaryLine", "hijriClock"]
        try await app.saveWidget(draft)
        let metadata = try XCTUnwrap(app.snapshotStore.read(WidgetCatalogSnapshot.name, as: WidgetCatalogSnapshot.self, now: app.prayerNow()))
        XCTAssertEqual(metadata.payload.configs.count, 1); XCTAssertTrue(metadata.payload.configs.allSatisfy { $0.rows.isEmpty })
        let hidden = try XCTUnwrap(app.snapshotStore.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: app.prayerNow()))
        let rows = try XCTUnwrap(hidden.payload.configs.first?.rows)
        XCTAssertEqual(rows.first { $0.id == "moneyNow" }?.value, "•••")
        let json = String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self)
        XCTAssertFalse(json.contains("VISIBLE-ONLY")); XCTAssertFalse(json.contains("SECRET-SEALED"))
        XCTAssertNil(app.snapshotStore.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: app.prayerNow().addingTimeInterval(4000)))
        XCTAssertNotNil(app.snapshotStore.read(WidgetCatalogSnapshot.name, as: WidgetCatalogSnapshot.self, now: app.prayerNow().addingTimeInterval(4000)), "The system picker may still name a saved preset after its facts expire.")
        try await app.applySettingsAndWait(["notes.widgetContent": .bool(true)])
        let optedIn = try XCTUnwrap(app.snapshotStore.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: app.prayerNow()))
        XCTAssertEqual(optedIn.payload.configs.first?.rows.first { $0.id == "diaryLine" }?.value, "VISIBLE-ONLY-WITH-OPT-IN")
    }
    func testFamilyCapacitiesComeFromTheOutsideSurfacesTable() {
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "small"), 2)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "medium"), 3)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "large"), 5)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "extraLargePortrait"), 7)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "accessoryCircular"), 1)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "accessoryRectangular"), 2)
        XCTAssertEqual(WidgetMakerStyle.capacity(for: "accessoryInline"), 1)
    }
    func testHabitWidgetNowScopeHidesLaterAndTomorrowButKeepsFullDayCount() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "HabitWidgetScope-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppSession(container: MadarContainerFactory.makeLocal(at: root), groupDirectory: root)
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight")])
        let today = AppBahwService(session: app).today, at = today.date(in: app.activePlace.timeZone).addingTimeInterval(20 * 3600)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        var anytime: UUID?
        for (index, name) in ["وقتها الآن", "في آخر اليوم", "بلا نافذة", "عادة الغد"].enumerated() {
            let id = UUID(); if index == 2 { anytime = id }
            var rule = HabitRule(effectiveFrom: today)
            if index < 2 { rule.windowStart = index == 0 ? 19 * 60 : 22 * 60; rule.windowEnd = index == 0 ? 21 * 60 : 23 * 60 }
            if index == 3 { rule.frequency = .weekly; rule.weekdays = [calendar.component(.weekday, from: today.adding(days: 1).date(in: calendar.timeZone))] }
            let encoded = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))
            try await app.executeDiaryCommand("habit.save", payload: ["id": .string(id.uuidString), "name": .string(name), "rule": encoded])
        }
        try await app.executeDiaryCommand("habit.complete", payload: ["id": .string(try XCTUnwrap(anytime).uuidString)])
        let full = try XCTUnwrap(app.roomWidgetPayloads(locked: false, at: at)[.habits])
        XCTAssertEqual(Set(full.rows.map(\.title)), ["وقتها الآن", "في آخر اليوم", "بلا نافذة"])
        try await app.applySettingsAndWait(["bahw.widgetScope": .string("todayOnly")])
        let current = try XCTUnwrap(app.roomWidgetPayloads(locked: false, at: at)[.habits])
        XCTAssertEqual(Set(current.rows.map(\.title)), ["وقتها الآن", "بلا نافذة"])
        var draft = WidgetMakerDraft(); draft.items = ["habitsToday"]
        let composed = try XCTUnwrap(app.widgetMakerRows(draft, at: at).first)
        XCTAssertEqual(try XCTUnwrap(composed.share), 1.0 / 3.0, accuracy: 0.000001)
        XCTAssertEqual(current.heading, full.heading)
        XCTAssertEqual(current.periods, full.periods)
    }

}
