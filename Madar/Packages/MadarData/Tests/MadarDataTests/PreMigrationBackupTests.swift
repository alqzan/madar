import Foundation
import Testing
@testable import MadarData

/// B1-14: a flat store that SwiftData is about to migrate in place is copied aside first; the live app's managed generations
/// already keep the source untouched, so this covers the one in-place path (adopting a flat pre-managed store).
@Suite(.serialized) struct PreMigrationBackupTests {
    private func fixture(version: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: root.appendingPathComponent("Madar.store"))
        try Data("wal".utf8).write(to: root.appendingPathComponent("Madar.store-wal"))
        try Data("shm".utf8).write(to: root.appendingPathComponent("Madar.store-shm"))
        try DurableFiles.encode(version, to: root.appendingPathComponent("SchemaVersion.json"))
        return root
    }
    @Test func anOlderStoreIsCopiedWithAllThreeFilesAndOnlyTheTwoNewestCopiesStay() throws {
        let root = try fixture(version: MadarSchema.version - 1); defer { try? FileManager.default.removeItem(at: root) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for step in 0..<3 { try MadarContainerFactory.backupBeforeMigration(at: root, now: base.addingTimeInterval(Double(step) * 10)) }
        let copies = try MadarContainerFactory.preMigrationBackups(in: root)
        #expect(copies.count == 2)
        #expect(copies[0].lastPathComponent.hasPrefix("pre-migration-\(MadarSchema.version - 1)-"))
        for suffix in ["", "-wal", "-shm"] {
            #expect(try Data(contentsOf: copies[0].appendingPathComponent("Madar.store" + suffix)) == Data(contentsOf: root.appendingPathComponent("Madar.store" + suffix)))
        }
        // The newest two survive: the first (oldest stamp) is gone.
        #expect(copies[0].lastPathComponent > copies[1].lastPathComponent)
    }
    @Test func aCurrentVersionStoreOrNoStoreMakesNoCopy() throws {
        let current = try fixture(version: MadarSchema.version); defer { try? FileManager.default.removeItem(at: current) }
        try MadarContainerFactory.backupBeforeMigration(at: current)
        #expect(try MadarContainerFactory.preMigrationBackups(in: current).isEmpty)
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("PreMigrationEmpty-\(UUID())")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: empty) }
        try MadarContainerFactory.backupBeforeMigration(at: empty)
        #expect(try MadarContainerFactory.preMigrationBackups(in: empty).isEmpty)
    }
}
