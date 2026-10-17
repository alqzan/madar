import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct BookCommandBusTests {
    @Test func durableReplayAppOnlyAndTombstoneUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookBus-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, identity = UUID(), commandID = UUID()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let p: MadarCore.JSONValue = .object(["id":.string(identity.uuidString),"title":.string("كتاب"),"author":.string(""),"pages":.number(250),"shelf":.string("reading")])
        let denied = try await bus.execute(.init(name: "book.savePaper", payload: p, source: .shortcut, issuedAt: now), now: now)
        #expect(denied.status == .needsApp)
        let command = CommandEnvelope(commandID: commandID, name: "book.savePaper", payload: p, issuedAt: now)
        let first = try await bus.execute(command, now: now), second = try await bus.execute(command, now: now)
        #expect(first == second); #expect(first.status == .applied); #expect(first.undoToken != nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Book>()) == 1)
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken":.string(commandID.uuidString)]), issuedAt: now), now: now)
        #expect(undo.status == .applied)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        #expect(row.id == identity); #expect(row.deletedAt != nil); #expect(row.deletionBarrierAt != nil)
    }
}
