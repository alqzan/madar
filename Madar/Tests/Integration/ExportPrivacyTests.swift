import XCTest
import SwiftData
import MadarData
@testable import Madar

/// Explicit host dependency; never selected by a production environment variable.
@MainActor final class ExportPrivacyTestAuthenticator: MadarDeviceAuthenticator {
    func verify() async throws -> Bool { true }
    func invalidate() { }
}
@MainActor enum ExportPrivacyTestHarness {
    static func install(on session: AppSession) {
        session.lockController = MadarLockController(scope: MadarLockScope(rawValue: session.string("core.faceIDLock")) ?? .notesOnly,
            service: AppPrivacyService(session: session), authenticator: { ExportPrivacyTestAuthenticator() })
    }
}

@MainActor final class ExportPrivacyTests: XCTestCase {
    private final class Auth: MadarDeviceAuthenticator {
        var allowed = true
        var delayed = false
        var calls = 0
        var invalidations = 0
        var continuation: CheckedContinuation<Bool, Never>?
        func verify() async throws -> Bool {
            calls += 1
            if delayed { return await withCheckedContinuation { continuation = $0 } }
            return allowed
        }
        func invalidate() { invalidations += 1 }
    }
    private final class Privacy: MadarLockService {
        var bindings: [MadarProtectedFeature] = []
        func redactProtectedData() async throws { bindings.removeAll() }
        func authorizeAccess(to feature: MadarProtectedFeature) async throws { bindings.append(feature) }
        func privacyScopeDidChange(to scope: MadarLockScope) async throws { }
        func persistedPrivacyScope() throws -> MadarLockScope { .notesOnly }
    }
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
        let auth: Auth
        let privacy: Privacy
        let lock: MadarLockController
        let keys: Keys
        let backup: AppBackupService
        let presented: PresentationProbe
    }
    private final class PresentationProbe { var files: [URL] = [] }
    private func fixture(scope: MadarLockScope = .app, privateRow: Bool = false, tombstone: Bool = false,
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
        let auth = Auth(), privacy = Privacy(), keys = Keys(), presented = PresentationProbe()
        let lock = MadarLockController(scope: scope, service: privacy, authenticator: { auth }); session.lockController = lock
        let backup = AppBackupService(session: session, store: store, backupDirectory: root.appending(path: "Backups"), keyStore: keys,
            sharePresentation: { file, ticket in try lock.validate(ticket); presented.files.append(file) }, deriveCredential: deriveCredential)
        return Fixture(root: root, store: store, session: session, auth: auth, privacy: privacy, lock: lock, keys: keys, backup: backup, presented: presented)
    }
    private enum ProbeError: Error { case timeout }
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() { guard ContinuousClock.now < deadline else { throw ProbeError.timeout }; await Task.yield() }
    }
    private func assertNoOutput(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(fixture.privacy.bindings.isEmpty, file: file, line: line)
        XCTAssertEqual(fixture.keys.reads, 0, file: file, line: line); XCTAssertEqual(fixture.keys.writes, 0, file: file, line: line)
        XCTAssertTrue(try fixture.backup.coordinator.catalog().isEmpty, file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appending(path: "Backups/PlainExports").path), file: file, line: line)
        XCTAssertTrue(fixture.presented.files.isEmpty, file: file, line: line)
        XCTAssertFalse(fixture.session.maintenanceInProgress, file: file, line: line)
    }

    func test_M0P1b_refusalCreatesNoPlainEncryptedFileOrKey() async throws {
        for encrypted in [false, true] {
            let fixture = try fixture(); fixture.auth.allowed = false
            do {
                if encrypted { _ = try await fixture.backup.export(passphrase: "test-only-passphrase", progress: { _ in }) }
                else { _ = try await fixture.backup.exportPlain(progress: { _ in }) }
                XCTFail("Refused export succeeded")
            } catch { }
            XCTAssertEqual(fixture.auth.calls, 1); try assertNoOutput(fixture)
        }
    }

    func test_M0P1b_cancelledVerifierCannotCreateOutputOrReadKeys() async throws {
        let fixture = try fixture(); fixture.auth.delayed = true
        let request = Task { try await fixture.backup.export(passphrase: "test-only-passphrase", progress: { _ in }) }
        try await waitUntil { fixture.auth.continuation != nil }
        XCTAssertTrue(fixture.session.maintenanceInProgress)
        request.cancel(); try await waitUntil { fixture.auth.invalidations == 1 }
        fixture.auth.continuation?.resume(returning: true); fixture.auth.continuation = nil
        do { _ = try await request.value; XCTFail("Cancelled verifier created output") } catch { }
        try assertNoOutput(fixture)
    }

    func test_M0P1b_staleVerifierCannotExportOrConfigureKey() async throws {
        let fixture = try fixture(); fixture.auth.delayed = true
        let request = Task { try await fixture.backup.export(passphrase: "test-only-passphrase", progress: { _ in }) }
        try await waitUntil { fixture.auth.continuation != nil }
        fixture.lock.sceneChanged(.background)
        fixture.auth.continuation?.resume(returning: true); fixture.auth.continuation = nil
        do { _ = try await request.value; XCTFail("Stale export succeeded") } catch { }
        try assertNoOutput(fixture)
    }

    func test_M0P1b_scopesAndPrivatePayloadUseExplicitAuthorizationIncludingTombstones() async throws {
        for scope: MadarLockScope in [.none, .notesOnly, .app] {
            for privateRow in [false, true] {
                let fixture = try fixture(scope: scope, privateRow: privateRow, tombstone: privateRow)
                let file = try await fixture.backup.exportPlain(progress: { _ in })
                try fixture.backup.validateExport(file: file)
                XCTAssertEqual(fixture.auth.calls, scope.effective == .app ? 1 : 0)
                XCTAssertEqual(Set(fixture.privacy.bindings), privateRow ? [.export, .privateNote] : [.export])
                let payload = try PortableExportCodec.validate(Data(contentsOf: file))
                XCTAssertEqual(payload.records.contains { $0.model == "NotebookNote" && $0.fields["isPrivate"] == .bool(true) }, privateRow)
                XCTAssertFalse(fixture.session.maintenanceInProgress); XCTAssertEqual(fixture.keys.writes, 0)
            }
        }
    }

    func testPrivatePayloadSharesWholeAppLockWithoutAnotherPrompt() async throws {
        let unlocked = try fixture(scope: .none, privateRow: true)
        _ = try await unlocked.backup.exportPlain(progress: { _ in })
        XCTAssertEqual(unlocked.auth.calls, 0)
        XCTAssertEqual(Set(unlocked.privacy.bindings), [.export, .privateNote])

        let locked = try fixture(scope: .app, privateRow: true); locked.auth.allowed = false
        do { _ = try await locked.backup.exportPlain(progress: { _ in }); XCTFail("Locked app exported private data") } catch { }
        XCTAssertEqual(locked.auth.calls, 1); try assertNoOutput(locked)

        let alreadyUnlocked = try fixture(scope: .app, privateRow: true)
        _ = try await alreadyUnlocked.lock.authorize([.app])
        _ = try await alreadyUnlocked.backup.exportPlain(progress: { _ in })
        XCTAssertEqual(alreadyUnlocked.auth.calls, 1, "The app gate must authorize private export without another prompt")
        XCTAssertEqual(Set(alreadyUnlocked.privacy.bindings), [.app, .export, .privateNote])
    }

    func test_M0P1b_staleKeyDerivationCannotSaveKeyOrCreateFile() async throws {
        let fixture = try fixture()
        // This hook is exercised only by the main-actor hasConfiguredKey metadata query;
        // it revokes immediately after that authorized presence check, before key derivation.
        let controller = fixture.lock
        fixture.keys.onExists = { MainActor.assumeIsolated { controller.sceneChanged(.background) } }
        do { _ = try await fixture.backup.export(passphrase: "test-only-passphrase", progress: { _ in }); XCTFail("Stale key setup succeeded") } catch { }
        XCTAssertEqual(fixture.keys.reads, 0); XCTAssertEqual(fixture.keys.writes, 0)
        XCTAssertTrue(try fixture.backup.coordinator.catalog().isEmpty)
        XCTAssertFalse(fixture.session.maintenanceInProgress)
    }

    @MainActor private final class DerivationProbe {
        var continuation: CheckedContinuation<BackupCredential, Error>?
        func derive(_ passphrase: String) async throws -> BackupCredential {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    private func importedPreview(_ fixture: Fixture) async throws -> BackupRestorePreview {
        let source = try self.fixture()
        let receipt = try await source.backup.coordinator.export(passphrase: "test-only-passphrase")
        return try await fixture.backup.previewRestore(file: receipt.fileURL, passphrase: "test-only-passphrase", progress: { _ in })
    }
    func test_M0P1b_01_restoreFirstKeyRefusalCreatesNoSafetyOrPromotion() async throws {
        let fixture = try fixture(scope: .app, privateRow: true)
        let preview = try await importedPreview(fixture), generation = fixture.store.binding.generationID
        fixture.auth.allowed = false
        do { _ = try await fixture.backup.restore(previewID: preview.id, mode: .replace, progress: { _ in }); XCTFail("Refused safety-key setup succeeded") } catch { }
        XCTAssertEqual(fixture.auth.calls, 1)
        XCTAssertEqual(fixture.store.binding.generationID, generation)
        try assertNoOutput(fixture)
    }
    func test_M0P1b_01_authorizedFirstKeyRestoreCreatesSafetyAndPromotes() async throws {
        let fixture = try fixture(scope: .app, privateRow: true)
        let preview = try await importedPreview(fixture), generation = fixture.store.binding.generationID
        _ = try await fixture.backup.restore(previewID: preview.id, mode: .replace, progress: { _ in })
        XCTAssertEqual(fixture.auth.calls, 1)
        XCTAssertEqual(fixture.keys.reads, 1); XCTAssertEqual(fixture.keys.writes, 2)
        XCTAssertNotEqual(fixture.store.binding.generationID, generation)
        XCTAssertEqual(try fixture.backup.coordinator.catalog().filter { $0.kind == .automatic }.count, 1)
        XCTAssertFalse(fixture.session.maintenanceInProgress)
    }
    func test_M0P1b_01_restoreDelayedKeyDerivationRevocationCannotSaveSafetyOrPromote() async throws {
        let credential = try await Task.detached { try BackupCredential.derive(passphrase: "test-only-passphrase") }.value
        for event in 0...3 {
            let derivation = DerivationProbe()
            let fixture = try fixture(deriveCredential: { try await derivation.derive($0) })
            let preview = try await importedPreview(fixture), generation = fixture.store.binding.generationID
            let request = Task { try await fixture.backup.restore(previewID: preview.id, mode: .replace, progress: { _ in }) }
            try await waitUntil { derivation.continuation != nil }
            XCTAssertTrue(fixture.session.maintenanceInProgress)
            switch event {
            case 0: fixture.lock.sceneChanged(.background)
            case 1: fixture.lock.lock()
            case 2: try await fixture.lock.changeScope(.none)
            default: fixture.lock.disconnect()
            }
            derivation.continuation?.resume(returning: credential); derivation.continuation = nil
            do { _ = try await request.value; XCTFail("Revoked derivation configured safety key") } catch { }
            XCTAssertEqual(fixture.keys.reads, 0); XCTAssertEqual(fixture.keys.writes, 0)
            XCTAssertTrue(try fixture.backup.coordinator.catalog().isEmpty)
            XCTAssertEqual(fixture.store.binding.generationID, generation)
            XCTAssertFalse(fixture.session.maintenanceInProgress)
        }
    }
    func test_M0P1b_02_settingsConfiguredStatusDoesNotLoadOrSaveCredential() async throws {
        let fixture = try fixture(scope: .none)
        let model = BackupSettingsModel(service: fixture.backup)
        await model.refresh()
        XCTAssertEqual(model.status?.keyConfigured, false)
        let credential = try await Task.detached { try BackupCredential.derive(passphrase: "test-only-passphrase") }.value
        try fixture.keys.seed(credential)
        await model.refresh()
        XCTAssertEqual(model.status?.keyConfigured, true)
        XCTAssertEqual(fixture.keys.reads, 0); XCTAssertEqual(fixture.keys.writes, 0)
        XCTAssertEqual(fixture.auth.calls, 0)
        // Unattended automatic backup still loads the configured credential.
        try await fixture.backup.runScheduledBackup()
        XCTAssertEqual(fixture.keys.reads, 1); XCTAssertEqual(fixture.keys.writes, 1)
        XCTAssertEqual(fixture.auth.calls, 0)
        XCTAssertEqual(try fixture.backup.coordinator.catalog().filter { $0.kind == .automatic }.count, 1)
        model.close()
    }

    func test_M0P1b_cachedShareReauthorizesOriginalPrivatePayloadAndRetainsFile() async throws {
        let fixture = try fixture(scope: .app, privateRow: true)
        let file = try await fixture.backup.exportPlain(progress: { _ in })
        // The cached file still contains private text even if live metadata changes.
        let notes = try fixture.store.container.mainContext.fetch(FetchDescriptor<NotebookNote>())
        notes.first?.isPrivate = false; try fixture.store.container.mainContext.save()
        fixture.lock.lock(); fixture.auth.allowed = false
        do { try await fixture.backup.share(file: file); XCTFail("Cached private share bypassed fresh auth") } catch { }
        XCTAssertTrue(fixture.presented.files.isEmpty)
        fixture.auth.allowed = true; try await fixture.backup.share(file: file)
        XCTAssertEqual(fixture.auth.calls, 3); XCTAssertEqual(fixture.presented.files, [file])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_M0P1b_backgroundDuringCachedShareCannotPresent() async throws {
        let fixture = try fixture(scope: .app)
        let file = try await fixture.backup.exportPlain(progress: { _ in })
        fixture.lock.lock(); fixture.auth.delayed = true
        let request = Task { try await fixture.backup.share(file: file) }
        try await waitUntil { fixture.auth.continuation != nil }
        fixture.lock.sceneChanged(.background)
        fixture.auth.continuation?.resume(returning: true); fixture.auth.continuation = nil
        do { try await request.value; XCTFail("Stale share presented") } catch { }
        XCTAssertTrue(fixture.presented.files.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_M0P1b_modelRevokesCachedURLsAndPassphrasesAndDeletesCompletedExport() async throws {
        let fixture = try fixture(scope: .none)
        let model = BackupSettingsModel(service: fixture.backup)
        model.exportPlain(); try await waitUntil { model.plainExportedURL != nil && !model.busy }
        let file = try XCTUnwrap(model.plainExportedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        model.exportPassphrase = "test-only-passphrase"; model.exportConfirmation = model.exportPassphrase
        fixture.lock.sceneChanged(.inactive)
        XCTAssertNil(model.plainExportedURL); XCTAssertNil(model.exportedURL)
        XCTAssertEqual(model.exportPassphrase, ""); XCTAssertEqual(model.exportConfirmation, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        model.sharePlain(); XCTAssertTrue(fixture.presented.files.isEmpty); model.close()
    }
}
