import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct IncrementalBackupTests {
    private let password = "synthetic long password"
    private let alpha = Data("SYNTHETIC-PRIVATE-MEDIA-ALPHA".utf8)
    private let beta = Data("SYNTHETIC-PRIVATE-MEDIA-BETA".utf8)
    private func fixture() async throws -> (URL, ManagedDataStore, BackupCoordinator, MemoryBackupKeyStore, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarIncremental-" + UUID().uuidString)
        let store = try ManagedDataStore(root: root.appendingPathComponent("Data"))
        let context = store.container.mainContext
        let first = Media(); first.sourceID = "synthetic-first"; first.data = alpha; first.sizeBytes = alpha.count; first.sha256 = BackupCodec.hash(alpha)
        let second = Media(); second.sourceID = "synthetic-second"; second.data = alpha; second.sizeBytes = alpha.count; second.sha256 = BackupCodec.hash(alpha)
        context.insert(first); context.insert(second); try context.save()
        let keys = MemoryBackupKeyStore(), coordinator = BackupCoordinator(store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: keys)
        try await coordinator.configurePassphrase(password)
        return (root, store, coordinator, keys, first.id)
    }
    private func blobs(_ package: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: package.appendingPathComponent("Media"), includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
    }
    private func alter(_ store: ManagedDataStore, id: UUID) throws {
        let context = ModelContext(store.container)
        let row = try #require(try context.fetch(FetchDescriptor<Media>()).first { $0.id == id })
        row.data = beta; row.sizeBytes = beta.count; row.sha256 = BackupCodec.hash(beta); row.updatedAt = .now
        try context.save()
    }
    /// Explicit opt-in only. Writes generated encrypted media into a fresh subfolder of the chosen provider,
    /// never reads its existing contents, and removes only that subfolder when the trial ends.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP_FOLDER"] != nil, "Chosen-provider trial only"))
    func chosenProviderPackageRestoresAfterLocalRemoval() async throws {
        try await chosenProviderTrial(requireCloudUpload: false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP_FOLDER"] != nil && ProcessInfo.processInfo.environment["MADAR_TRIAL_REQUIRE_CLOUD_UPLOAD"] == "1", "Requires an account exposing actual cloud-upload metadata"))
    func chosenProviderConfirmsActualCloudUpload() async throws {
        try await chosenProviderTrial(requireCloudUpload: true)
    }

    private func chosenProviderTrial(requireCloudUpload: Bool) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP_FOLDER"])
        let chosen = URL(fileURLWithPath: path).appendingPathComponent("Madar-Verification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: chosen) }
        let (root, _, source, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await source.export(kind: .automatic)
        let selected = try BackupFolderDelivery.select(chosen)
        let delivery = try await BackupFolderDelivery.deliver([receipt], from: source.backupDirectory, to: selected)
        let external = chosen.appendingPathComponent("Madar-" + selected.ownerID.uuidString).appendingPathComponent(receipt.fileURL.lastPathComponent)
        #expect(try BackupArtifact.fingerprint(file: external) == receipt.sha256)
        try FileManager.default.removeItem(at: source.backupDirectory)
        let target = try ManagedDataStore(root: root.appendingPathComponent("Recovered"))
        let recovery = BackupCoordinator(store: target, backupDirectory: root.appendingPathComponent("Safety"), keyStore: MemoryBackupKeyStore())
        try await recovery.configurePassphrase(password)
        let preview = try await recovery.preview(file: external, passphrase: password)
        _ = try await recovery.restore(preview: preview, mode: .merge)
        let rows = try RecordBridge.all(ModelContext(target.container)).filter { $0.model == "Media" }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { (try? $0.decode("data", as: Data.self)) == alpha })
        guard requireCloudUpload else { return }
        var uploaded = delivery.uploadedToICloud
        for _ in 0..<45 where uploaded != true {
            try await Task.sleep(for: .seconds(2))
            uploaded = await BackupFolderDelivery.uploadStatus(delivery.configuration)
        }
        #expect(uploaded == true, "Provider copy and recovery passed; the OS must separately confirm actual cloud upload")
    }
    @Test func mediaIsEncryptedOncePerHashReusedAndEachSetStaysIndependent() async throws {
        let (root, store, coordinator, keys, id) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let start = try #require(try keys.load()).nextNonceCounter
        let first = try await coordinator.export(kind: .automatic)
        #expect(first.fileURL.pathExtension == "madarbackupset")
        let original = try #require(try blobs(first.fileURL).first), originalBytes = try Data(contentsOf: original)
        #expect(try blobs(first.fileURL).count == 1, "two source rows with identical bytes use one authenticated object")
        #expect(!original.lastPathComponent.contains(BackupCodec.hash(alpha)), "plaintext media hashes are inside the encrypted index")
        #expect(originalBytes.range(of: alpha) == nil)
        #expect(try keys.load()?.nextNonceCounter == start + 2, "one index and one distinct media envelope")
        try alter(store, id: id)
        let second = try await coordinator.export(kind: .automatic, now: .now.addingTimeInterval(10))
        #expect(try blobs(second.fileURL).count == 2)
        let reused = second.fileURL.appendingPathComponent("Media").appendingPathComponent(original.lastPathComponent)
        #expect(try Data(contentsOf: reused) == originalBytes, "unchanged media is reused byte for byte, without encryption again")
        // A clone is not a hard link. Mutating an old envelope must not corrupt the new snapshot.
        try Data("damaged old envelope".utf8).write(to: original)
        let checked = try BackupArtifact.validate(file: second.fileURL, passphrase: password)
        #expect(checked.records.filter { $0.model == "Media" }.count == 2)
        #expect(try checked.records.first { $0.id == id }?.decode("data", as: Data.self) == beta)
        #expect(try Data(contentsOf: reused) == originalBytes)
        try FileManager.default.removeItem(at: first.fileURL)
        #expect(try BackupArtifact.validate(file: second.fileURL, passphrase: password).records.count == 2)
        let manual = try await coordinator.export(kind: .manual)
        #expect(manual.fileURL.pathExtension == "madarbackup")
        #expect(try BackupCodec.validate(Data(contentsOf: manual.fileURL), passphrase: password).records.count == 2)
    }
    @Test func retentionAndFolderDeliveryPreserveStandaloneRestoreAfterSourceRemoval() async throws {
        let (root, _, coordinator, _, _) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for day in 0..<4 { _ = try await coordinator.export(kind: .automatic, now: now.addingTimeInterval(Double(day) * 86400)) }
        let initial = try coordinator.catalog(), oldest = try #require(initial.last)
        let folder = root.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = try BackupFolderDelivery.select(folder)
        let first = try await BackupFolderDelivery.deliver(initial, from: coordinator.backupDirectory, to: configuration)
        let remote = folder.appendingPathComponent("Madar-" + configuration.ownerID.uuidString)
        let changed = remote.appendingPathComponent(oldest.fileURL.lastPathComponent)
        let changedBlob = try #require(try blobs(changed).first)
        try Data("provider changed this encrypted object".utf8).write(to: changedBlob)
        _ = try await coordinator.export(kind: .automatic, now: now.addingTimeInterval(4 * 86400))
        let second = try await BackupFolderDelivery.deliver(coordinator.catalog(), from: coordinator.backupDirectory, to: first.configuration)
        #expect(second.preservedChangedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: changed.path))
        _ = try await coordinator.export(kind: .automatic, now: now.addingTimeInterval(5 * 86400))
        let receipts = try coordinator.catalog()
        let delivered = try await BackupFolderDelivery.deliver(receipts, from: coordinator.backupDirectory, to: second.configuration)
        #expect(receipts.count == 4); #expect(delivered.configuration.owned.count == 5)
        #expect(delivered.preservedChangedFiles == 1); #expect(delivered.uploadedToICloud == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: coordinator.backupDirectory.path).filter { $0.hasSuffix(".madarbackupset") }.count == 4)
        #expect(try FileManager.default.contentsOfDirectory(atPath: remote.path).filter { $0.hasSuffix(".madarbackupset") }.count == 5)
        #expect(try Data(contentsOf: changedBlob) == Data("provider changed this encrypted object".utf8))
        try FileManager.default.removeItem(at: coordinator.backupDirectory)
        for receipt in receipts {
            let file = folder.appendingPathComponent("Madar-" + configuration.ownerID.uuidString).appendingPathComponent(receipt.fileURL.lastPathComponent)
            #expect(try BackupArtifact.fingerprint(file: file) == receipt.sha256)
            #expect(try BackupArtifact.validate(file: file, passphrase: password).records.count == 2)
        }
    }
    @Test func missingTamperedOrUnexpectedMediaAndWrongPasswordCannotTouchLiveRecords() async throws {
        let (root, store, coordinator, _, _) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await coordinator.export(kind: .automatic)
        let before = try RecordFingerprint.hash(RecordBridge.all(ModelContext(store.container))), generation = store.binding.generationID
        for mode in 0..<4 {
            let copy = root.appendingPathComponent("Invalid-\(mode).madarbackupset")
            try FileManager.default.copyItem(at: receipt.fileURL, to: copy)
            let blob = try #require(try blobs(copy).first)
            if mode == 0 { try FileManager.default.removeItem(at: blob) }
            if mode == 1 { try Data("tampered".utf8).write(to: blob) }
            if mode == 2 { try FileManager.default.createSymbolicLink(at: copy.appendingPathComponent("unexpected"), withDestinationURL: blob) }
            await #expect(throws: (any Error).self) { try await coordinator.preview(file: copy, passphrase: mode == 3 ? "wrong long password" : password) }
            #expect(store.binding.generationID == generation)
            #expect(try RecordFingerprint.hash(RecordBridge.all(ModelContext(store.container))) == before)
            #expect(try coordinator.catalog().map(\.id) == [receipt.id])
        }
        // Replace a required envelope with a symlink, even to correct bytes: refuse it.
        let copy = root.appendingPathComponent("Linked.madarbackupset")
        try FileManager.default.copyItem(at: receipt.fileURL, to: copy)
        let blob = try #require(try blobs(copy).first); try FileManager.default.removeItem(at: blob)
        try FileManager.default.createSymbolicLink(at: blob, withDestinationURL: #require(try blobs(receipt.fileURL).first))
        #expect(throws: (any Error).self) { try BackupArtifact.validate(file: copy, passphrase: password) }
    }
    @Test func cancellationKeepsPriorReceiptAndKeyRotationFallsBackToNewEncryptedMedia() async throws {
        let (root, _, coordinator, _, _) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let prior = try await coordinator.export(kind: .automatic), fingerprint = try BackupArtifact.fingerprint(file: prior.fileURL)
        let cancel = BackupCancellation()
        await #expect(throws: BackupOperationError.cancelled) {
            try await coordinator.export(kind: .automatic, progress: { if $0.phase == .writing { cancel.cancel() } }, cancellation: cancel)
        }
        #expect(try coordinator.catalog().map(\.id) == [prior.id]); #expect(try BackupArtifact.fingerprint(file: prior.fileURL) == fingerprint)
        #expect(try FileManager.default.contentsOfDirectory(atPath: coordinator.backupDirectory.path).allSatisfy { !$0.hasSuffix(".partial") })
        try await coordinator.configurePassphrase("a different long password")
        let rotated = try await coordinator.export(kind: .automatic)
        #expect(try Set(blobs(rotated.fileURL).map(\.lastPathComponent)).isDisjoint(with: blobs(prior.fileURL).map(\.lastPathComponent)))
        #expect(try BackupArtifact.validate(file: rotated.fileURL, passphrase: "a different long password").records.count == 2)
        #expect(try BackupArtifact.validate(file: prior.fileURL, passphrase: password).records.count == 2)
    }
    @Test func packageMergeReplayAndReplaceUseTheNormalSafetyAndTombstonePath() async throws {
        let (root, _, source, _, _) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await source.export(kind: .automatic)
        let target = try ManagedDataStore(root: root.appendingPathComponent("Target"))
        let old = Entry(); old.text = "synthetic local entry"; target.container.mainContext.insert(old); try target.container.mainContext.save()
        let oldID = old.id
        let coordinator = BackupCoordinator(store: target, backupDirectory: root.appendingPathComponent("TargetBackups"), keyStore: MemoryBackupKeyStore())
        try await coordinator.configurePassphrase(password)
        let preview = try await coordinator.preview(file: receipt.fileURL, passphrase: password)
        #expect(preview.additions == 2)
        _ = try await coordinator.restore(preview: preview, mode: .merge)
        let merged = try RecordBridge.all(ModelContext(target.container))
        #expect(merged.filter { $0.model == "Media" }.count == 2)
        #expect(merged.first { $0.id == oldID }?.isLive == true)
        let replay = try await coordinator.preview(file: receipt.fileURL, passphrase: password)
        #expect(replay.additions == 0); #expect(replay.updates == 0)
        _ = try await coordinator.restore(preview: replay, mode: .merge)
        #expect(try RecordFingerprint.hash(RecordBridge.all(ModelContext(target.container))) == RecordFingerprint.hash(merged))
        let replace = try await coordinator.preview(file: receipt.fileURL, passphrase: password)
        let result = try await coordinator.restore(preview: replace, mode: .replace)
        let rows = try RecordBridge.all(ModelContext(result.container))
        #expect(rows.first { $0.id == oldID }?.deletedAt != nil)
        #expect(rows.filter { $0.model == "Media" }.allSatisfy { (try? $0.decode("data", as: Data.self)) == alpha })
        let safety = try BackupArtifact.validate(file: result.automaticBackup.fileURL, passphrase: password)
        #expect(safety.records.first { $0.id == oldID }?.isLive == true)
    }
}
