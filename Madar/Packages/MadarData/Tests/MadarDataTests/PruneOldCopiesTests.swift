import Foundation
import Testing
@testable import MadarData

@MainActor struct PruneOldCopiesTests {
    private func make(_ root: URL, _ path: String, age days: Double) throws {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data([1]).write(to: url.appendingPathComponent("x"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)], ofItemAtPath: url.path)
    }
    private func exists(_ root: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }

    @Test func keepsActivePreviousAndNewestSafetyCopyAndDeletesOlder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Prune-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let active = UUID(), previous = UUID(), old1 = UUID(), old2 = UUID(), fresh = UUID()
        for (id, age) in [(active, 1.0), (previous, 5.0), (old1, 40.0), (old2, 90.0), (fresh, 0.1)] { try make(root, "Generations/\(id)", age: age) }
        try make(root, "Generations/not-a-uuid", age: 99)
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        for (id, age) in [(s1, 10.0), (s2, 30.0), (s3, 60.0)] { try make(root, "MigrationSafety/\(id)", age: age) }
        let pointer = ManagedPointer(version: 1, generationID: active, previousGenerationID: previous, accountHash: nil, cloudKitContainerIdentifier: nil)
        let removed = ManagedDataStore.pruneOldCopies(root: root, pointer: pointer, journalPending: false)
        #expect(Set(removed) == ["Generations/\(old1)", "Generations/\(old2)", "MigrationSafety/\(s2)", "MigrationSafety/\(s3)"])
        #expect(exists(root, "Generations/\(active)") && exists(root, "Generations/\(previous)"))
        #expect(exists(root, "Generations/\(fresh)"), "a folder touched in the last 24 hours is never removed")
        #expect(exists(root, "Generations/not-a-uuid"), "only UUID-named folders are touched")
        #expect(exists(root, "MigrationSafety/\(s1)"))
    }

    @Test func nothingIsDeletedWhileARestoreJournalIsPending() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PruneJournal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = UUID(); try make(root, "Generations/\(old)", age: 90)
        let pointer = ManagedPointer(version: 1, generationID: UUID(), previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil)
        #expect(ManagedDataStore.pruneOldCopies(root: root, pointer: pointer, journalPending: true).isEmpty)
        #expect(exists(root, "Generations/\(old)"))
    }
}
