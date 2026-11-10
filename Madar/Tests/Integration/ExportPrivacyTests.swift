import XCTest
import SwiftData
import MadarData
@testable import Madar

/// Backup, export and restore behaviour through the app service. The app lock was removed (owner, 10 Nov 2026):
/// nothing here asks for device authentication any more.
@MainActor enum ExportPrivacyTestHarness {
    /// Kept so older test setups still compile: there is no lock to install.
    static func install(on session: AppSession) { session.authorizeProtectedData() }
}

@MainActor final class ExportPrivacyTests: XCTestCase {
    /// Counter/storage mutation is protected by NSLock, like MemoryBackupKeyStore.
    private final class Keys: BackupKeyStore, @unchecked Sendable {
        private let mutex = NSLock()
        private let storage = MemoryBackupKeyStore()
        private var readCount = 0
        private var writeCount = 0
        var onExists: (@Sendable () -> Void)?
        var reads: Int { mutex.lock(); defer { mutex.unlock() }; return readCount }
        var writes: Int { mutex.lock(); defer { mutex.unlock() }; return writeCount }
        func exists() throws -> Bool { onExists?(); return try storage.exists() }
        func load() throws -> BackupCredential? {
            mutex.lock(); readCount += 1; mutex.unlock()
            return try storage.load()
        }
        func seed(_ credential: BackupCredential) throws { try storage.save(credential) }
        func save(_ credential: BackupCredential) throws { mutex.lock(); writeCount += 1; mutex.unlock(); try storage.save(credential) }
        func remove() throws { try storage.remove() }
    }
    private struct Fixture {
        let root: URL
        let store: ManagedDataStore
        let session: AppSession
        let keys: Keys
        let backup: AppBackupService
        let presented: PresentationProbe
        let plainExportGate: PlainExportGate
    }
    private final class PresentationProbe { var files: [URL] = [] }
    @MainActor private final class PlainExportGate {
        var pauseOnReturn = false
        var fileURL: URL?
        var continuation: CheckedContinuation<Void, Never>?
        func didCreate(_ file: URL) async {
            fileURL = file
            guard pauseOnReturn else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func resume() { continuation?.resume(); continuation = nil; pauseOnReturn = false }
    }
    private func fixture(privateRow: Bool = false, tombstone: Bool = false,
                         plainExportGate: PlainExportGate = PlainExportGate(),
                         deriveCredential: @escaping @Sendable (String) async throws -> BackupCredential = { passphrase in
                             try await Task.detached { try BackupCredential.derive(passphrase: passphrase) }.value
                         }) throws -> Fixture {
        // Keep synthetic SQLite files until process exit while SwiftData holds them.
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarExportPrivacy-\(UUID())")
        let store = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        if privateRow {
            let note = NotebookNote(); note.isPrivate = true; note.text = "خصوصية اختبار فقط"
            if tombstone { note.deletedAt = Date(); note.deletionBarrierAt = note.deletedAt }
            store.container.mainContext.insert(note); try store.container.mainContext.save()
        }
        let keys = Keys(), presented = PresentationProbe()
        let backup = AppBackupService(session: session, store: store, backupDirectory: root.appending(path: "Backups"), keyStore: keys,
            sharePresentation: { file in presented.files.append(file) },
            didCreatePlainExport: { file in await plainExportGate.didCreate(file) }, deriveCredential: deriveCredential)
        return Fixture(root: root, store: store, session: session, keys: keys, backup: backup, presented: presented, plainExportGate: plainExportGate)
    }
    private enum ProbeError: Error { case timeout }
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() { guard ContinuousClock.now < deadline else { throw ProbeError.timeout }; await Task.yield() }
    }
    private func importedPreview(_ fixture: Fixture) async throws -> BackupRestorePreview {
        let source = try self.fixture()
        let receipt = try await source.backup.coordinator.export(passphrase: "test-only-passphrase")
        return try await fixture.backup.previewRestore(file: receipt.fileURL, passphrase: "test-only-passphrase", progress: { _ in })
    }

    func testPlainExportCarriesPrivateNotesAndTombstonesWithoutAnyPrompt() async throws {
        for privateRow in [false, true] {
            let fixture = try fixture(privateRow: privateRow, tombstone: privateRow)
            let file = try await fixture.backup.exportPlain(progress: { _ in })
            let payload = try PortableExportCodec.validate(Data(contentsOf: file))
            XCTAssertEqual(payload.records.contains { $0.model == "NotebookNote" && $0.fields["isPrivate"] == .bool(true) }, privateRow)
            XCTAssertFalse(fixture.session.maintenanceInProgress); XCTAssertEqual(fixture.keys.writes, 0)
        }
    }

    func testEncryptedExportSavesTheKeyOnceAndSharePresentsTheFile() async throws {
        let fixture = try fixture()
        let file = try await fixture.backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(fixture.keys.writes, 1)
        try await fixture.backup.share(file: file)
        XCTAssertEqual(fixture.presented.files, [file])
        XCTAssertFalse(fixture.session.maintenanceInProgress)
    }

    func testCancelledExportLeavesNoFileAndNoCatalogEntry() async throws {
        let fixture = try fixture(plainExportGate: { let g = PlainExportGate(); g.pauseOnReturn = true; return g }())
        let gate = fixture.plainExportGate
        let request = Task { try await fixture.backup.exportPlain(progress: { _ in }) }
        try await waitUntil { gate.continuation != nil && gate.fileURL != nil }
        let file = try XCTUnwrap(gate.fileURL)
        await fixture.backup.cancel()
        gate.resume()
        do { _ = try await request.value; XCTFail("Cancelled export returned a file") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try fixture.backup.coordinator.catalog().isEmpty)
        XCTAssertFalse(fixture.session.maintenanceInProgress)
    }

    func test_M0P1b_01_firstKeyRestoreCreatesSafetyAndPromotes() async throws {
        let fixture = try fixture(privateRow: true)
        let preview = try await importedPreview(fixture), generation = fixture.store.binding.generationID
        _ = try await fixture.backup.restore(previewID: preview.id, mode: .replace, progress: { _ in })
        XCTAssertEqual(fixture.keys.reads, 1); XCTAssertEqual(fixture.keys.writes, 2)
        XCTAssertNotEqual(fixture.store.binding.generationID, generation)
        XCTAssertEqual(try fixture.backup.coordinator.catalog().filter { $0.kind == .automatic }.count, 1)
        XCTAssertFalse(fixture.session.maintenanceInProgress)
    }

    func test_M0P1b_02_settingsConfiguredStatusDoesNotLoadOrSaveCredential() async throws {
        let fixture = try fixture()
        let model = BackupSettingsModel(service: fixture.backup)
        await model.refresh()
        XCTAssertEqual(model.status?.keyConfigured, false)
        let credential = try await Task.detached { try BackupCredential.derive(passphrase: "test-only-passphrase") }.value
        try fixture.keys.seed(credential)
        await model.refresh()
        XCTAssertEqual(model.status?.keyConfigured, true)
        XCTAssertEqual(fixture.keys.reads, 0); XCTAssertEqual(fixture.keys.writes, 0)
        // Unattended automatic backup still loads the configured credential.
        try await fixture.backup.runScheduledBackup()
        XCTAssertEqual(fixture.keys.reads, 1); XCTAssertEqual(fixture.keys.writes, 1)
        XCTAssertEqual(try fixture.backup.coordinator.catalog().filter { $0.kind == .automatic }.count, 1)
        model.close()
    }

    func testClosingTheScreenDeletesThePlainExport() async throws {
        let fixture = try fixture()
        let model = BackupSettingsModel(service: fixture.backup)
        model.exportPlain(); try await waitUntil { model.plainExportedURL != nil && !model.busy }
        let file = try XCTUnwrap(model.plainExportedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        model.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
