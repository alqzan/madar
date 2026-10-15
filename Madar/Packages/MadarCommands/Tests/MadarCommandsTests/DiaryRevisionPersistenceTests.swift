import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct DiaryRevisionPersistenceTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    // RD1: written 15 Oct 22:00 (fajr@1, Riyadh) → day 15 Oct, which ends at Fajr on 16 Oct and freezes a day later.
    @Test func editsInPlaceBeforeFreezeAndKeepsTheOriginalAfter() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryRevision-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let written = date("2026-10-15T22:00:00+03:00"), id = UUID()
        #expect(try await bus.execute(.init(commandID: id, name: "diary.appendLine", payload: .object(["text": .string("كتبت مساءً"), "day": .string("today")]), issuedAt: written), now: written).status == .applied)
        let entry = try #require(ModelContext(container).fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.dayKey == "2026-10-15"); #expect(entry.dayPolicy == "fajr@1")
        func edit(_ text: String, of target: UUID, at now: Date, command: UUID = UUID()) async throws -> CommandOutcome {
            try await bus.execute(.init(commandID: command, name: "diary.editEntry", payload: .object(["entryID": .string(target.uuidString), "revisionID": .string(UUID().uuidString), "text": .string(text)]), issuedAt: now), now: now)
        }
        // Before the freeze: corrected in place, and undo restores the text.
        let early = date("2026-10-16T12:00:00+03:00"), fix = UUID()
        #expect(try await edit("كتبت مساءً، بعد العشاء", of: entry.id, at: early, command: fix).status == .applied)
        var rows = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 1); #expect(rows[0].text == "كتبت مساءً، بعد العشاء")
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(fix.uuidString)]), issuedAt: early), now: early.addingTimeInterval(1))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first?.text == "كتبت مساءً")
        // After the freeze: a new row replaces it, the original row is byte-for-byte unchanged.
        let originalRecord = try #require(ModelContext(container).fetch(FetchDescriptor<Entry>()).first).record()
        let late = date("2026-10-17T12:00:00+03:00"), revise = UUID()
        #expect(try await edit("كتبت مساءً عند أهلي", of: entry.id, at: late, command: revise).status == .applied)
        rows = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 2)
        let original = try #require(rows.first { $0.id == entry.id }), head = try #require(rows.first { $0.id != entry.id })
        #expect(try original.record() == originalRecord)
        #expect(head.source == "revision"); #expect(head.sourceID == entry.id.uuidString); #expect(head.dayKey == "2026-10-15"); #expect(head.eventAt == original.eventAt)
        #expect(DiaryRevisionChains(rows.map { .init(id: $0.id, replaces: $0.source == "revision" ? $0.sourceID.flatMap(UUID.init(uuidString:)) : nil) }).heads == [head.id])
        // The replaced row is no longer editable; replay of the same command adds nothing.
        await #expect(throws: (any Error).self) { _ = try await edit("مرة أخرى", of: entry.id, at: late) }
        _ = try await bus.execute(.init(commandID: revise, name: "diary.editEntry", payload: .object(["entryID": .string(entry.id.uuidString), "revisionID": .string(head.id.uuidString), "text": .string("كتبت مساءً عند أهلي")]), issuedAt: late), now: late.addingTimeInterval(1))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 2)
        // Undo tombstones only the new row; the original shows again.
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(revise.uuidString)]), issuedAt: late), now: late.addingTimeInterval(2))
        rows = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(rows.first { $0.id == head.id }?.deletedAt != nil); #expect(rows.first { $0.id == entry.id }?.deletedAt == nil)
        #expect(try rows.first { $0.id == entry.id }?.record() == originalRecord)
    }
}
