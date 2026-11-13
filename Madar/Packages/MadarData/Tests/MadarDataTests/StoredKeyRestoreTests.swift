import Foundation
import Testing
@testable import MadarData

/// T04: this device's backups open with the stored key; a wrong passphrase gives the specific error; no key gives the specific error.
@MainActor struct StoredKeyRestoreTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StoredKey-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func make(_ base: URL, keys: MemoryBackupKeyStore) throws -> BackupCoordinator {
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"), commandLockURL: base.appendingPathComponent("CommandBus.lock"))
        return BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: keys)
    }
    @Test func previewOpensThisDevicesBackupWithTheStoredKeyAndNoPassphrase() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let keys = MemoryBackupKeyStore(), coordinator = try make(base, keys: keys)
        try await coordinator.configurePassphrase("correct long password")
        let receipt = try await coordinator.export(kind: .manual)
        let preview = try await coordinator.preview(file: receipt.fileURL)
        #expect(preview.fileName == receipt.fileURL.lastPathComponent)
    }
    @Test func wrongPassphraseIsTheSpecificAuthenticationError() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let keys = MemoryBackupKeyStore(), coordinator = try make(base, keys: keys)
        try await coordinator.configurePassphrase("correct long password")
        let receipt = try await coordinator.export(kind: .manual)
        await #expect(throws: DataError.authenticationFailed) { try await coordinator.preview(file: receipt.fileURL, passphrase: "a wrong long password") }
    }
    @Test func noStoredKeyAndNoPassphraseIsNotConfigured() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let withKey = MemoryBackupKeyStore(), first = try make(base, keys: withKey)
        try await first.configurePassphrase("correct long password")
        let receipt = try await first.export(kind: .manual)
        let other = try scratch(); defer { try? FileManager.default.removeItem(at: other) }
        let empty = try make(other, keys: MemoryBackupKeyStore())
        await #expect(throws: BackupOperationError.backupNotConfigured) { try await empty.preview(file: receipt.fileURL) }
    }
    @Test func changingThePassphraseMakesNewBackupsOpenWithTheNewKeyOnly() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let keys = MemoryBackupKeyStore(), coordinator = try make(base, keys: keys)
        try await coordinator.configurePassphrase("correct long password")
        let old = try await coordinator.export(kind: .manual)
        try await coordinator.replacePassphrase("another long password")
        let new = try await coordinator.export(kind: .manual)
        _ = try await coordinator.preview(file: new.fileURL, passphrase: "another long password")
        _ = try await coordinator.preview(file: new.fileURL) // stored key is the new one
        await #expect(throws: BackupOperationError.backupNotConfigured) { try await coordinator.preview(file: old.fileURL) }
        _ = try await coordinator.preview(file: old.fileURL, passphrase: "correct long password")
    }
}
