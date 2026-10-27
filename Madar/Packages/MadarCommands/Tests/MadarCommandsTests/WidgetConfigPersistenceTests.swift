import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarInbox
@testable import MadarCommands

@MainActor struct WidgetConfigPersistenceTests {
    @Test func savedWidgetReplayEditDeleteAndUndoPreserveOtherRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetMaker-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let now = Date(timeIntervalSince1970: 1792000000), id = UUID(), creation = UUID(), edit = UUID(), deletion = UUID()
        let context = ModelContext(container), entry = Entry(); entry.text = "سطر يبقى كما هو"; context.insert(entry); try context.save()
        let style = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(WidgetMakerStyle()))
        let base: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string("صباحي"), "familyID": .string("medium"), "items": .array([.string("prayerNext"), .string("habitsToday")]), "style": style]
        func run(_ name: String, _ payload: [String: MadarCore.JSONValue], _ token: UUID = UUID(), _ second: Double = 0) async throws -> CommandOutcome {
            try await bus.execute(.init(commandID: token, name: name, payload: .object(payload), issuedAt: now.addingTimeInterval(second)), now: now.addingTimeInterval(second))
        }
        func widgets() throws -> [WidgetConfig] { try ModelContext(container).fetch(FetchDescriptor<WidgetConfig>()) }
        #expect(try await run("widget.save", base, creation).status == .applied)
        _ = try await run("widget.save", base, creation)
        #expect(try widgets().count == 1)
        #expect(try widgets().first?.items == ["prayerNext", "habitsToday"])
        let originalStyle = try #require(widgets().first?.styleJSON)
        var otherStyle = WidgetMakerStyle(); otherStyle.font = "modern"; otherStyle.color = "blue"
        let changedStyle = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(otherStyle))
        #expect(try await run("widget.save", base.merging(["name": .string("مسائي"), "familyID": .string("large"), "style": changedStyle, "items": .array([.string("habitsToday"), .string("prayerNext")])]) { $1 }, edit, 1).status == .applied)
        #expect(try widgets().first?.name == "مسائي")
        _ = try await run("system.undo", ["undoToken": .string(edit.uuidString)], UUID(), 2)
        #expect(try widgets().first?.name == "صباحي")
        #expect(try widgets().first?.familyID == "medium")
        #expect(try widgets().first?.styleJSON == originalStyle)
        #expect(try widgets().first?.items == ["prayerNext", "habitsToday"])
        _ = try await run("widget.delete", ["id": .string(id.uuidString)], deletion, 3)
        #expect(try widgets().first?.deletedAt != nil)
        _ = try await run("system.undo", ["undoToken": .string(deletion.uuidString)], UUID(), 4)
        #expect(try widgets().first?.deletedAt == nil)
        #expect(try widgets().first?.restoredAt != nil)
        #expect(try widgets().first?.familyID == "medium")
        #expect(try widgets().first?.styleJSON == originalStyle)
        #expect(try widgets().first?.items == ["prayerNext", "habitsToday"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first?.text == "سطر يبقى كما هو")
        _ = try await run("widget.save", base.merging(["name": .string("بعد التعديل")]) { $1 }, UUID(), 5)
        await #expect(throws: (any Error).self) { try await run("system.undo", ["undoToken": .string(creation.uuidString)], UUID(), 6) }
        #expect(try widgets().first?.name == "بعد التعديل")
    }
    @Test func invalidConfigIsRejectedBeforeWriting() async throws {
        let style = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(WidgetMakerStyle()))
        let valid: [String: MadarCore.JSONValue] = ["id": .string(UUID().uuidString), "name": .string("ودجتي"), "familyID": .string("medium"), "items": .array([.string("prayerNext")]), "style": style]
        #expect(DiaryEditorCommand.parse("widget.save", valid) != nil)
        for patch: [String: MadarCore.JSONValue] in [["items": .array([])], ["name": .string(" ")], ["items": .array([.string("unknown")])], ["items": .array([.string("prayerNext"), .string("prayerNext")])], ["familyID": .string("huge")]] {
            #expect(DiaryEditorCommand.parse("widget.save", valid.merging(patch) { $1 }) == nil)
        }
        #expect(CommandBus.appOnlyCommandNames.contains("widget.save"))
        #expect(CommandBus.appOnlyCommandNames.contains("widget.delete"))
    }
    @Test func delayedWidgetAndShortcutCompletionKeepTheTapDayWithinAWeeklyPeriod() async throws {
        for source in [CommandSource.widget, .siri] {
            let root = FileManager.default.temporaryDirectory.appending(path: "WidgetDay-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let container = try MadarContainerFactory.makeLocal(at: root)
            let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }), bus = CommandBus(adapter: adapter)
            let pressed = ISO8601DateFormatter().date(from: "2026-10-14T20:00:00+03:00")!, drained = ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!
            let id = UUID(); var rule = HabitRule(effectiveFrom: try GregorianDay("2026-10-14")); rule.frequency = .weekly; rule.measure = .count; rule.target = 3
            let encoded = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))
            _ = try await bus.execute(.init(name: "habit.save", payload: .object(["id": .string(id.uuidString), "name": .string("صلة"), "rule": encoded]), issuedAt: pressed), now: pressed)
            let period = try #require(HabitRepository(context: ModelContext(container)).readings(at: pressed).first?.summary.current?.key)
            let inbox = PendingInbox(directory: root.appending(path: "PendingInbox")), generation = UUID()
            try inbox.publishGeneration(.init(generationID: generation, acceptsUnstampedDeliveries: false))
            try HabitInboxCommandWriter.complete(inbox: inbox, habitID: id, delta: 1, periodKey: period, source: source, issuedAt: pressed, day: try GregorianDay("2026-10-14"))
            let drainer = InboxDrainer(inbox: inbox, bus: bus, generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {})
            try await drainer.drain(now: drained); try await drainer.drain(now: drained)
            let events = try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter { $0.delta > 0 }
            #expect(events.count == 1)
            #expect(events.first?.dayKey == "2026-10-14")
            #expect(events.first?.periodKey == period)
        }
    }

}
