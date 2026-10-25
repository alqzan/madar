import XCTest
import SwiftData
import MadarCore
import MadarData
import CryptoKit
import UniformTypeIdentifiers
@testable import Madar

@MainActor final class BackupFolderServiceTests: XCTestCase {
    func testIncrementalPackageCopiesIntoRestoreCacheAndPreviewsWithoutChangingStore() async throws {
        let type = try XCTUnwrap(UTType(filenameExtension: "madarbackupset", conformingTo: .package))
        XCTAssertEqual(type.identifier, "com.alqzan.madar2.backupset"); XCTAssertTrue(type.conforms(to: .package))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupSetService-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root.appendingPathComponent("Data"))
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let service = AppBackupService(session: session, store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        let context = ModelContext(store.container), media = Media(), bytes = Data([1, 2, 3, 4])
        media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        context.insert(media); try context.save()
        try await service.coordinator.configurePassphrase("synthetic long password")
        let receipt = try await service.coordinator.export(kind: .automatic)
        XCTAssertEqual(receipt.fileURL.pathExtension, "madarbackupset")
        let before = try RecordBridge.all(ModelContext(store.container)), generation = store.binding.generationID
        let preview = try await service.previewRestore(file: receipt.fileURL, passphrase: "synthetic long password", progress: { _ in })
        XCTAssertEqual(preview.fileName, receipt.fileURL.lastPathComponent)
        XCTAssertEqual(preview.additions, 0); XCTAssertEqual(preview.updates, 0); XCTAssertEqual(preview.deletions, 0)
        XCTAssertEqual(store.binding.generationID, generation)
        XCTAssertEqual(try RecordBridge.all(ModelContext(store.container)), before)
        await service.cancel()
    }
    func testDeviceOnlyFolderPersistsCopiesEncryptedBackupAndUndoKeepsFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupFolderService-" + UUID().uuidString)
        let store = try ManagedDataStore(root: root.appendingPathComponent("Data"))
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let keys = MemoryBackupKeyStore()
        let service = AppBackupService(session: session, store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: keys)
        let folder = root.appendingPathComponent("SelectedFolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await service.coordinator.configurePassphrase("synthetic long password")
        let receipt = try await service.coordinator.export(kind: .automatic)
        let before = try RecordBridge.all(ModelContext(store.container), syncedOnly: true)
        try await service.chooseFolder(folder)
        let status = try await service.status()
        XCTAssertEqual(status.folderName, "SelectedFolder")
        XCTAssertNotNil(status.folderCopiedAt)
        XCTAssertNil(status.folderUploadConfirmed)
        let context = ModelContext(store.container)
        let key = "sys.backupFolder"
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key })).first)
        let configuration = try JSONDecoder().decode(BackupFolderConfiguration.self, from: row.valueJSON)
        let delivered = folder.appendingPathComponent("Madar-" + configuration.ownerID.uuidString).appendingPathComponent(receipt.fileURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: delivered), try Data(contentsOf: receipt.fileURL))
        let reopened = AppBackupService(session: session, store: store, backupDirectory: service.coordinator.backupDirectory, keyStore: keys)
        let persisted = try await reopened.status(); XCTAssertEqual(persisted.folderName, "SelectedFolder")
        try await reopened.clearFolder()
        let cleared = try await reopened.status(); XCTAssertNil(cleared.folderName); XCTAssertTrue(cleared.canUndoFolderChange)
        XCTAssertTrue(FileManager.default.fileExists(atPath: delivered.path))
        try await reopened.undoFolderChange()
        let restored = try await reopened.status(); XCTAssertEqual(restored.folderName, "SelectedFolder")
        XCTAssertEqual(try RecordBridge.all(ModelContext(store.container), syncedOnly: true), before)
    }
    func testFailedDeliveryKeepsItsDestinationAndRetriesWithoutAnotherBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupFolderRetry-" + UUID().uuidString)
        let store = try ManagedDataStore(root: root.appendingPathComponent("Data"))
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let service = AppBackupService(session: session, store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        let folder = root.appendingPathComponent("Chosen"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await service.coordinator.configurePassphrase("synthetic long password")
        let receipt = try await service.coordinator.export(kind: .automatic)
        let original = try Data(contentsOf: receipt.fileURL)
        try Data("synthetic damaged source".utf8).write(to: receipt.fileURL)
        do { try await service.chooseFolder(folder); XCTFail("A damaged source must not be delivered") }
        catch { XCTAssertEqual(error as? BackupFolderError, .invalidSource) }
        let failed = try await service.status()
        XCTAssertEqual(failed.folderName, "Chosen"); XCTAssertNil(failed.folderCopiedAt)
        XCTAssertNotNil(failed.folderMessage); XCTAssertEqual(failed.automaticCount, 1)
        try original.write(to: receipt.fileURL)
        try await service.retryFolderDelivery()
        let retried = try await service.status()
        XCTAssertNotNil(retried.folderCopiedAt); XCTAssertNil(retried.folderMessage)
        XCTAssertEqual(retried.automaticCount, 1, "Retry uses the existing encrypted receipt")
    }

}
