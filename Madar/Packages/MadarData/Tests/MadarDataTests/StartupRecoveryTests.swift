import Foundation
import Testing
@testable import MadarData

/// T03: the backup list is readable without a session, and setting the store aside never deletes it.
struct StartupRecoveryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Recovery-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func listsPreMigrationFoldersAndCatalogueBackupsWithoutASession() throws {
        let group = try folder(); defer { try? FileManager.default.removeItem(at: group) }
        let pre = group.appendingPathComponent("\(MadarContainerFactory.preMigrationFolderPrefix)17-20261101T100000Z", isDirectory: true)
        try FileManager.default.createDirectory(at: pre, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: pre.appendingPathComponent("Madar.store"))
        let backups = group.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let file = backups.appendingPathComponent("a.madarbackup"); try Data("yy".utf8).write(to: file)
        let receipt = BackupReceipt(id: UUID(), fileURL: URL(fileURLWithPath: "/old/container/a.madarbackup"), createdAt: Date(timeIntervalSince1970: 2_000_000_000), kind: .automatic, generationID: UUID(), sha256: "", counts: [:])
        try JSONEncoder().encode([receipt]).write(to: backups.appendingPathComponent("BackupCatalog.json"))
        let found = StartupRecovery.candidates(groupDirectory: group)
        #expect(found.count == 2)
        #expect(found.contains { $0.source == .automatic && $0.url.lastPathComponent == "a.madarbackup" && $0.bytes == 2 })
        #expect(found.contains { $0.source == .preMigration && $0.bytes == 1 })
    }
    @Test func settingTheStoreAsideKeepsEveryFileAndPutBackRestoresIt() throws {
        let group = try folder(); defer { try? FileManager.default.removeItem(at: group) }
        let root = group.appendingPathComponent("ManagedData", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("Madar.store"))
        let aside = try StartupRecovery.setAsideStore(groupDirectory: group)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(FileManager.default.fileExists(atPath: aside.appendingPathComponent("Madar.store").path))
        try StartupRecovery.putBack(aside, groupDirectory: group)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Madar.store").path))
    }
}
