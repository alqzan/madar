import Foundation
import Testing
import MadarCore
@testable import MadarInbox

struct TransportTests {
    private func fixture() -> PendingInbox {
        PendingInbox(directory: FileManager.default.temporaryDirectory.appending(path: "MadarInboxFixture-\(UUID())"))
    }
    private func record(generation: UUID = UUID()) -> InboxRecord {
        .init(expectedGenerationID: generation, command: .init(name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("jamaah")]), source: .widget))
    }
    @Test func test_M0R03_durableImmutablePublicationAndClaimRecovery() throws {
        let inbox = fixture(), record = record()
        let ticket = try inbox.enqueue(record)
        #expect(ticket.commandID == record.command.commandID)
        let pending = inbox.directory.appending(path: "pending/\(ticket.deliveryID.uuidString).jsonl")
        #expect(try Data(contentsOf: pending).last == 10)
        #expect(throws: InboxError.self) { _ = try inbox.enqueue(record) }
        let claimed = try #require(try inbox.claimBatch().first)
        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(try inbox.read(claimed) == record)
        let reopened = PendingInbox(directory: inbox.directory)
        let resumed = try reopened.claimBatch()
        #expect(resumed.map { $0.standardizedFileURL.resolvingSymlinksInPath().path } == [claimed.standardizedFileURL.resolvingSymlinksInPath().path])
        #expect(try reopened.read(#require(resumed.first)) == record)
        #expect(try reopened.unacknowledgedCommandIDs() == [record.command.commandID])
        try reopened.acknowledge(claimed)
        #expect(try reopened.claimBatch().isEmpty)
    }
    @Test func test_M0R03_incompleteTemporaryFilesAreNeverClaimed() throws {
        let inbox = fixture()
        _ = try inbox.enqueue(record())
        try Data("partial".utf8).write(to: inbox.directory.appending(path: "pending/.unpublished.tmp"))
        #expect(try inbox.claimBatch().count == 1)
        #expect(FileManager.default.fileExists(atPath: inbox.directory.appending(path: "pending/.unpublished.tmp").path))
    }
    @Test func test_M0R03_malformedRecordQuarantinesBesideValidRecord() throws {
        let inbox = fixture(), valid = record()
        _ = try inbox.enqueue(valid)
        let malformed = inbox.directory.appending(path: "pending/\(UUID()).jsonl")
        try Data("{}\n{}\n".utf8).write(to: malformed)
        let claimed = try inbox.claimBatch()
        #expect(claimed.count == 2)
        for file in claimed {
            do { #expect(try inbox.read(file) == valid); try inbox.acknowledge(file) }
            catch InboxError.malformedRecord { try inbox.quarantine(file, reason: "malformedRecord") }
        }
        #expect(try inbox.claimBatch().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "quarantine").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
    }
    @Test func test_M0R03_oldGenerationRetainedAsUnresolvedWithoutPayloadDiagnostic() throws {
        let inbox = fixture(), old = record()
        _ = try inbox.enqueue(old)
        let claimed = try #require(try inbox.claimBatch().first)
        try inbox.retainForResolution(claimed, reason: "generationChanged")
        #expect(try inbox.claimBatch().isEmpty)
        #expect(try inbox.unacknowledgedCommandIDs() == [old.command.commandID])
        let diagnostic = try Data(contentsOf: inbox.directory.appending(path: "unresolved/\(old.deliveryID).diagnostic.json"))
        #expect(!String(decoding: diagnostic, as: UTF8.self).contains("jamaah"))
    }
    @Test func test_M0R03_cliAndFoundationTempAliasesClaimTheSameDirectory() throws {
        let inbox = fixture(), accepted = record()
        _ = try inbox.enqueue(accepted)
        let claimed = try #require(try inbox.claimBatch().first)
        let cliPath = inbox.directory.path.hasPrefix("/private/var/") ? String(inbox.directory.path.dropFirst(8)) : inbox.directory.path
        let fromCLI = PendingInbox(directory: URL(fileURLWithPath: cliPath, isDirectory: true))
        let recovered = try #require(try fromCLI.claimBatch().first)
        #expect(recovered.standardizedFileURL.resolvingSymlinksInPath().path == claimed.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(try fromCLI.read(recovered) == accepted)
        try fromCLI.acknowledge(recovered)
        #expect(try inbox.claimBatch().isEmpty)
    }

}
