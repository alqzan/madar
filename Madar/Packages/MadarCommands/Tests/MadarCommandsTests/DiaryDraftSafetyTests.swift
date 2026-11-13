import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// T02 (AGENT_TASKS.md): three ways diary text used to be lost. Expected values come from the task card, not from the code.
@MainActor struct DiaryDraftSafetyTests {
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiarySafety-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), root)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func saveAndCommit(_ bus: CommandBus, id: UUID, now: Date) async throws {
        let payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "text": .string("نص لا يضيع"), "day": .string("today"), "writingDayKey": .string("2026-10-15")]
        _ = try await bus.execute(.init(name: "diary.saveDraft", payload: .object(payload), issuedAt: now), now: now)
        _ = try await bus.execute(.init(commandID: id, name: "diary.commitDraft", payload: .object(["id": .string(id.uuidString)]), issuedAt: now), now: now)
    }
    // Case 1: send then undo brings the same text back into the field (the draft is alive again).
    @Test func undoingASentLineRevivesItsDraft() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), now = date("2026-10-15T12:00:00+03:00")
        try await saveAndCommit(bus, id: id, now: now)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SessionDraft>()).first?.deletedAt != nil)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(id.uuidString)]), issuedAt: now), now: now.addingTimeInterval(2))
        let draft = try #require(ModelContext(container).fetch(FetchDescriptor<SessionDraft>()).first)
        #expect(draft.deletedAt == nil)
        #expect(try JSONDecoder().decode(String.self, from: draft.provisionalJSON) == "نص لا يضيع")
    }
    // Case 2: the Quran clean-up command leaves a diary draft untouched.
    @Test func quranDiscardUnreadableDraftsKeepsDiaryDrafts() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), now = date("2026-10-15T12:00:00+03:00")
        let payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "text": .string("مسودة مذكرات"), "day": .string("today"), "writingDayKey": .string("2026-10-15")]
        _ = try await bus.execute(.init(name: "diary.saveDraft", payload: .object(payload), issuedAt: now), now: now)
        _ = try await bus.execute(.init(name: "quran.discardUnreadableDrafts", payload: .object([:]), issuedAt: now), now: now.addingTimeInterval(1))
        #expect(try ModelContext(container).fetch(FetchDescriptor<SessionDraft>()).first?.deletedAt == nil)
    }
    // Case 3: "what remains after a send" (hand calculation: sent "ab", current "ab cd" -> "cd").
    @Test func remainderKeepsWordsTypedDuringSend() {
        #expect(DiaryDraftRemainder.remaining(current: "ab", sent: "ab") == "")
        #expect(DiaryDraftRemainder.remaining(current: "ab cd", sent: "ab") == "cd")
        #expect(DiaryDraftRemainder.remaining(current: "xy", sent: "ab") == "xy")
        #expect(DiaryDraftRemainder.remaining(current: "", sent: "ab") == "")
    }
    @Test func twoSecondsUsesTheDual() {
        #expect(DiaryDurationFormat.elapsed(2) == "ثانيتان")
    }
}
