import Foundation
import Testing
@testable import MadarSnapshots

struct SnapshotStoreTests {
    private func temporaryStore() -> SnapshotStore {
        SnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }
    @Test func completeRoundTripAndExpiry() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let instant = Date(timeIntervalSince1970: 1_791_532_800)
        let snapshot = SnapshotEnvelope(name: "FoundationSnapshot", generatedAt: instant, validUntil: instant.addingTimeInterval(60), dayKey: "2026-10-10", tzID: "Asia/Riyadh", privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: "hijri", numerals: "arabicIndic"))
        try store.write(snapshot)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant)?.payload == snapshot.payload)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant.addingTimeInterval(60)) == nil)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant.addingTimeInterval(-1)) == nil)
    }
    @Test func corruptUnknownVersionAndTraversalReturnPlaceholder() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "FoundationSnapshot.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: file)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self) == nil)
        try Data("{truncated".utf8).write(to: file)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self) == nil)
        #expect(throws: SnapshotError.invalidName) { try store.remove("../outside") }
    }
    @Test func concurrentReadersNeverSeePartialJSON() async throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let now = Date(timeIntervalSince1970: 1_791_532_800)
        let envelope = SnapshotEnvelope(name: "FoundationSnapshot", generatedAt: now, validUntil: now.addingTimeInterval(600), dayKey: "2026-10-10", tzID: "Asia/Riyadh", privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: "hijri", numerals: "arabicIndic"))
        try store.write(envelope)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for _ in 0..<100 { try store.write(envelope) } }
            group.addTask { for _ in 0..<100 { #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: now) != nil) } }
            try await group.waitForAll()
        }
    }
}
