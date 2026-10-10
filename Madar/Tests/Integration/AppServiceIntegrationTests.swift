import XCTest
import SwiftData
import MadarData
@testable import Madar

@MainActor final class AppServiceIntegrationTests: XCTestCase {
    func testBackupUIAdapterRestoresSyncedDataAndPreservesDevicePreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarService-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        try await session.applySettingsAndWait(["core.firstCalendar": .string("gregorian"), "core.theme": .string("light")])
        try await backup.setSchedule(.manual)
        let file = try await backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let status = try await backup.status()
        XCTAssertEqual(status.manualCount, 1)
        XCTAssertTrue(status.keyConfigured)
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri"), "core.theme": .string("dark")])
        let preview = try await backup.previewRestore(file: file, passphrase: "test-only-passphrase", progress: { _ in })
        let originalGeneration = managed.binding.generationID
        let restored = try await backup.restore(previewID: preview.id, mode: .replace, progress: { _ in })
        XCTAssertGreaterThan(restored.restoredCount, 0)
        XCTAssertTrue(restored.warnings.isEmpty, restored.warnings.description)
        XCTAssertNotEqual(originalGeneration, managed.binding.generationID)
        XCTAssertEqual(session.string("core.firstCalendar"), "gregorian")
        XCTAssertEqual(session.string("core.theme"), "dark")
        XCTAssertEqual(session.string("core.backup"), "manual")
        XCTAssertFalse(session.maintenanceInProgress)
        let after = try await backup.status()
        XCTAssertEqual(after.automaticCount, 1)
        // The same session's already-created bus follows the promoted generation.
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri")])
        let reopened = try ManagedDataStore(root: managed.root, commandLockURL: managed.commandLockURL)
        let settings = try SettingsStore(context: ModelContext(reopened.container))
        XCTAssertEqual(try settings.value(for: "core.firstCalendar"), .string("hijri"))
    }

    func testStalePreviewDoesNotChangeGenerationOrCreateSafetyBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarService-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        let file = try await backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        let preview = try await backup.previewRestore(file: file, passphrase: "test-only-passphrase", progress: { _ in })
        try await session.applySettingsAndWait(["core.firstCalendar": .string("gregorian")])
        let originalGeneration = managed.binding.generationID
        do { _ = try await backup.restore(previewID: preview.id, mode: .replace, progress: { _ in }); XCTFail("stale preview accepted") }
        catch { XCTAssertEqual(error as? BackupOperationError, .stalePreview) }
        XCTAssertEqual(originalGeneration, managed.binding.generationID)
        let status = try await backup.status()
        XCTAssertEqual(status.automaticCount, 0)
        XCTAssertFalse(session.maintenanceInProgress)
        await backup.cancel()
    }
}
