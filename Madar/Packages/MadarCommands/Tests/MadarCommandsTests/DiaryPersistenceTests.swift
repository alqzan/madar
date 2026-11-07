import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct DiaryPersistenceTests {
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryCommands-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), root)
    }
    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @Test func appendReplayUndoAndStoredDaySurviveBoundaryChange() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = instant("2026-10-10T02:00:00+03:00")
        let command = CommandEnvelope(name: "diary.appendLine", payload: .object(["text": .string("سطر عند الليل"), "day": .string("today")]), issuedAt: now)
        let applied = try await bus.execute(command, now: now)
        #expect(applied.status == .applied)
        _ = try await bus.execute(command, now: now.addingTimeInterval(1))
        let context = ModelContext(container), rows = try context.fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 1); #expect(rows[0].dayKey == "2026-10-09"); #expect(rows[0].dayPolicy == "fajr@1")
        #expect(rows[0].tzID == "Asia/Riyadh")
        _ = try await bus.execute(.init(name: "settings.set", payload: .object(["settings": .object(["core.dayStart": .string("midnight")])]), issuedAt: now), now: now.addingTimeInterval(2))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first?.dayKey == "2026-10-09")
        let token = try #require(applied.undoToken)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(token.uuidString)]), issuedAt: now), now: now.addingTimeInterval(3))
        let deleted = try #require(ModelContext(container).fetch(FetchDescriptor<Entry>()).first)
        #expect(deleted.deletedAt != nil); #expect(deleted.text == "سطر عند الليل")
    }
    @Test func automaticDiaryLinesKeepTheirStoredEventTimeZone() throws {
        let (container, _, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), day = try GregorianDay("2026-03-20"), eventAt = instant("2026-03-20T00:30:00Z")
        let prayer = PrayerLog(); prayer.dayKey = day.description; prayer.prayer = "fajr"; prayer.status = "jamaah"
        prayer.eventAt = eventAt; prayer.tzID = "Europe/London"; context.insert(prayer)
        let session = HifzSession(); session.dayKey = day.description; session.kind = "hifz"; session.endedAt = eventAt
        session.tzID = "Europe/London"; context.insert(session)
        let reading = ReadingSession(); reading.dayKey = day.description; reading.end = eventAt; reading.activeSeconds = 120
        reading.tzID = "Europe/London"; context.insert(reading)
        let earlier = day.adding(days: -1)
        let earlierPrayer = PrayerLog(); earlierPrayer.dayKey = earlier.description; earlierPrayer.prayer = "isha"; earlierPrayer.status = "alone"
        earlierPrayer.eventAt = eventAt.addingTimeInterval(-86_400); earlierPrayer.tzID = "Europe/Paris"; context.insert(earlierPrayer)
        try context.save()

        let lines = try DiaryLineRenderer.live(day: day, context: context)
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.tzID == "Europe/London" })
        let batch = try DiaryLineRenderer.live(days: [day.description, earlier.description], context: context)
        #expect(batch[day.description] == lines)
        #expect(batch[earlier.description]?.map(\.tzID) == ["Europe/Paris"])
    }
    /// OR-11: N3 shows what was read and the day's habits. Al-Fatiha is ayahs 1–7 on page 1; Al-Baqara 1 is ayah 8.
    @Test func quranLinesNameTheAmountAndHabitsWriteTheirDay() throws {
        let (container, _, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), day = try GregorianDay("2026-03-20"), at = instant("2026-03-20T09:00:00Z")
        let review = HifzSession(); review.dayKey = day.description; review.kind = "review"; review.fromAyah = 1; review.toAyah = 7; review.endedAt = at; context.insert(review)
        let hifz = HifzSession(); hifz.dayKey = day.description; hifz.kind = "hifz"; hifz.fromAyah = 8; hifz.toAyah = 12; hifz.endedAt = at.addingTimeInterval(60); context.insert(hifz)
        let walk = Habit(); walk.name = "المشي"; context.insert(walk)
        let read = Habit(); read.name = "القراءة"; context.insert(read)
        let linked = Habit(); linked.name = "الفجر جماعة"; linked.linkedSource = "salah.fajr"; context.insert(linked)
        func event(_ habit: Habit, _ delta: Int, _ unit: String?, _ minutes: Double) { let e = HabitEvent(); e.habitID = habit.id; e.dayKey = day.description; e.periodKey = day.description; e.delta = delta; e.unit = unit; e.eventAt = at.addingTimeInterval(minutes * 60); context.insert(e) }
        event(walk, 1, nil, 5); event(read, 20, "minutes", 6); event(read, 10, "minutes", 7); event(linked, 1, nil, 8)
        try context.save()
        let lines = try DiaryLineRenderer.live(day: day, context: context)
        #expect(lines.filter { $0.kind == "quran" }.map(\.text) == ["راجعت وجهًا واحدًا من الفاتحة", "حفظت ٥ آيات من البقرة"])
        #expect(Set(lines.filter { $0.kind == "habits" }.map(\.text)) == ["المشي", "القراءة، ٣٠ دقيقة"])
    }
    @Test func yesterdayIsLateAndMarginIsOneFactWithTwoDayReferences() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = instant("2026-10-15T12:00:00+03:00")
        _ = try await bus.execute(.init(name: "diary.appendLine", payload: .object(["text": .string("عن أمس"), "day": .string("yesterday")]), issuedAt: now), now: now)
        let margin = try await bus.execute(.init(name: "diary.addMargin", payload: .object(["text": .string("رد اليوم"), "targetDayKey": .string("2025-10-15")]), issuedAt: now), now: now)
        #expect(margin.status == .applied)
        let context = ModelContext(container), entries = try context.fetch(FetchDescriptor<Entry>()), margins = try context.fetch(FetchDescriptor<MarginNote>())
        #expect(entries.count == 1); #expect(entries[0].dayKey == "2026-10-14"); #expect(entries[0].ink == "late")
        #expect(margins.count == 1); #expect(margins[0].targetDayKey == "2025-10-15"); #expect(margins[0].writtenDayKey == "2026-10-15")
    }
    @Test func validationRejectsFutureMarginEmptyOversizeAndExternalWrites() async throws {
        let (_, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = instant("2026-10-15T12:00:00+03:00")
        for text in [" ", String(repeating: "ا", count: 2001)] {
            let result = try await bus.execute(.init(name: "diary.appendLine", payload: .object(["text": .string(text), "day": .string("today")]), issuedAt: now), now: now)
            #expect(result.status == .rejected)
        }
        let external = try await bus.execute(.init(name: "diary.appendLine", payload: .object(["text": .string("خاص"), "day": .string("today")]), source: .widget, issuedAt: now), now: now)
        #expect(external.status == .needsApp)
    }
    @Test func sourceCorrectionFreezesClosedDayBeforeChangingThePrayer() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = instant("2026-10-15T12:00:00+03:00"), context = ModelContext(container)
        let page = DayPage(); page.dayKey = "2026-10-14"; context.insert(page)
        let prayer = PrayerLog(); prayer.dayKey = page.dayKey; prayer.prayer = "fajr"; prayer.status = "jamaah"; context.insert(prayer)
        let settings = try SettingsStore(context: context)
        _ = try settings.stage(["salah.trackingStart": .object(["dayKey": .string("2026-10-01"), "edits": .number(0)])])
        try context.save()
        let result = try await bus.execute(.init(name: "prayer.log", payload: .object(["dayKey": .string("2026-10-14"), "prayer": .string("fajr"), "status": .string("alone")]), issuedAt: now), now: now)
        #expect(result.status == .applied)
        let fresh = ModelContext(container), frozen = try #require(fresh.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.diaryAutoLines.2026-10-14" })
        let lines = try JSONDecoder().decode([DiaryAutoLine].self, from: frozen.valueJSON)
        #expect(lines.map(\.text) == ["صلّيت الفجر جماعة"])
        #expect(try fresh.fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
    }
}
