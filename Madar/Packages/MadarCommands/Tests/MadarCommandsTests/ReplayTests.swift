import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
@testable import MadarCommands

@Suite(.serialized) @MainActor struct ReplayTests {
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MadarCommandFixture-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: directory)
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory, transactionClock: { $0 })), directory)
    }
    private func prayer(_ status: String = "jamaah", id: UUID = UUID(), now: Date) -> CommandEnvelope {
        .init(commandID: id, name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string(status)]), source: .widget, issuedAt: now)
    }
    @Test func test_M0R04_distinctDuplicateReceiptNeverOverwritesLaterEdit() async throws {
        let (container, bus, _) = try fixture(), now = Date()
        let a = prayer(now: now), b = prayer(now: now)
        #expect(try await bus.execute(a, now: now).status == .applied)
        let firstRow = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        let stamp = firstRow.updatedAt
        #expect(try await bus.execute(b, now: now.addingTimeInterval(1)).status == .duplicate)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 2)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == stamp)
        #expect(try await bus.execute(prayer("alone", now: now.addingTimeInterval(2)), now: now.addingTimeInterval(2)).status == .applied)
        #expect(try await bus.execute(b, now: now.addingTimeInterval(3)).status == .duplicate)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
    }
    @Test func test_M0R05_replayBeforeTombstoneAndIdentityMismatch() async throws {
        let (container, bus, _) = try fixture(), now = Date()
        let a = prayer(now: now)
        let applied = try await bus.execute(a, now: now)
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(a.commandID.uuidString)]), issuedAt: now)
        #expect(try await bus.execute(undo, now: now.addingTimeInterval(1)).status == .applied)
        #expect(try await bus.execute(a, now: now.addingTimeInterval(2)) == applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.deletedAt != nil)
        let mismatch = try await bus.execute(prayer("alone", id: a.commandID, now: now), now: now.addingTimeInterval(3))
        #expect(mismatch.status == .rejected && mismatch.reason == "commandIdentityMismatch")
        let changedName = CommandEnvelope(commandID: a.commandID, name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark")])]), issuedAt: now)
        #expect(try await bus.execute(changedName, now: now).reason == "commandIdentityMismatch")
    }
    @Test func test_M0R06_onDiskExpiredReceiptReplaysAfterReopen() async throws {
        let (container, bus, directory) = try fixture(), now = Date()
        let a = prayer(now: now), b = prayer(now: now)
        _ = try await bus.execute(a, now: now)
        _ = try await bus.execute(b, now: now)
        _ = try await bus.execute(prayer("alone", now: now.addingTimeInterval(1)), now: now.addingTimeInterval(1))
        let reopened = try MadarContainerFactory.makeLocal(at: directory)
        let second = CommandBus(adapter: DurableCommandAdapter(container: reopened, lockDirectory: directory, transactionClock: { $0 }))
        #expect(try await second.execute(b, now: now.addingTimeInterval(8 * 86400)).status == .duplicate)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
    }
}
