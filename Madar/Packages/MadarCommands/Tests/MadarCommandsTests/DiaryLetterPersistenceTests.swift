import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct DiaryLetterPersistenceTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryLetter-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), root)
    }
    private func run(_ bus: CommandBus, _ name: String, _ payload: [String: MadarCore.JSONValue], at now: Date, id: UUID = UUID()) async throws -> CommandOutcome {
        try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
    }
    private func letter(_ container: ModelContainer, _ id: UUID) throws -> Letter { try #require(ModelContext(container).fetch(FetchDescriptor<Letter>()).first { $0.id == id }) }
    // N04 acceptance: a date letter is not due before its day and opens once; a stored project letter whose project is
    // gone becomes orphaned and never opens by itself; rescheduling waits for the new date. (Projects can no longer be
    // made in the app; the project rows here are seeded straight into the store, as an older store would hold them.)
    @Test func dateLetterOpensOnceAndProjectLetterOrphans() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let written = date("2026-10-15T20:00:00+03:00"), dated = UUID(), project = UUID(), onProject = UUID()
        #expect(try await run(bus, "diary.sealLetter", ["id": .string(dated.uuidString), "text": .string("إلى نفسي بعد شهر"), "trigger": .string("date"), "value": .string("2026-11-15")], at: written).status == .applied)
        await #expect(throws: (any Error).self) { _ = try await run(bus, "diary.sealLetter", ["id": .string(UUID().uuidString), "text": .string("أمس"), "trigger": .string("date"), "value": .string("2026-10-14")], at: written) }
        do { let seed = ModelContext(container), row = Project(); row.id = project; row.name = "البيت"; row.createdAt = written; row.updatedAt = written; seed.insert(row); try seed.save() }
        #expect(try await run(bus, "diary.sealLetter", ["id": .string(onProject.uuidString), "text": .string("حين ينتهي البيت"), "trigger": .string("projectFinished"), "targetID": .string(project.uuidString)], at: written).status == .applied)
        // Before the day: sealed, and opening is refused.
        let before = date("2026-11-14T12:00:00+03:00")
        _ = try await run(bus, "diary.refreshLetters", [:], at: before)
        #expect(try letter(container, dated).state == "sealed")
        await #expect(throws: (any Error).self) { _ = try await run(bus, "diary.openLetter", ["id": .string(dated.uuidString)], at: before) }
        // Deleting the target project orphans its letter; it is not opened.
        do { let gone = ModelContext(container); let row = try #require(gone.fetch(FetchDescriptor<Project>()).first { $0.id == project }); row.deletedAt = before; row.updatedAt = before; try gone.save() }
        _ = try await run(bus, "diary.refreshLetters", [:], at: before.addingTimeInterval(60))
        #expect(try letter(container, onProject).state == "orphaned"); #expect(try letter(container, onProject).openedAt == nil)
        // On the day: eligible, opens once, a second opening keeps the first time.
        let due = date("2026-11-15T12:00:00+03:00"), later = date("2026-11-20T12:00:00+03:00")
        _ = try await run(bus, "diary.refreshLetters", [:], at: due)
        #expect(try letter(container, dated).state == "eligible")
        _ = try await run(bus, "diary.openLetter", ["id": .string(dated.uuidString)], at: due.addingTimeInterval(60))
        let opened = try letter(container, dated).openedAt
        _ = try await run(bus, "diary.openLetter", ["id": .string(dated.uuidString)], at: later)
        _ = try await run(bus, "diary.refreshLetters", [:], at: later)
        #expect(try letter(container, dated).state == "opened"); #expect(try letter(container, dated).openedAt == opened)
        // «اختر موعدًا»: the orphan waits for a date again.
        #expect(try await run(bus, "diary.rescheduleLetter", ["id": .string(onProject.uuidString), "dayKey": .string("2026-12-01")], at: later).status == .applied)
        _ = try await run(bus, "diary.refreshLetters", [:], at: later.addingTimeInterval(60))
        #expect(try letter(container, onProject).state == "sealed")
    }
    // 11 Nov 2026: the project commands are gone; an old queued one is refused and touches nothing.
    @Test func oldProjectCommandsAreRefusedAndChangeNothing() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-15T20:00:00+03:00"), project = UUID()
        for name in ["diary.saveProject", "diary.finishProject", "diary.deleteProject", "diary.linkEntry"] {
            let outcome = try? await run(bus, name, ["id": .string(project.uuidString), "name": .string("البيت"), "intention": .string("")], at: now)
            #expect(outcome?.status != .applied)
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<Project>()).isEmpty)
    }
}
