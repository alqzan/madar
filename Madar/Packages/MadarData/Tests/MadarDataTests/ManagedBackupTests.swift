import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct ManagedBackupTests {
    private final class PresenceKeys: BackupKeyStore, @unchecked Sendable {
        private let mutex = NSLock()
        private var credential: BackupCredential?
        private var loads = 0
        private var saves = 0
        var accesses: (Int, Int) { mutex.lock(); defer { mutex.unlock() }; return (loads, saves) }
        func exists() throws -> Bool { mutex.lock(); defer { mutex.unlock() }; return credential != nil }
        func load() throws -> BackupCredential? { mutex.lock(); defer { mutex.unlock() }; loads += 1; return credential }
        func save(_ value: BackupCredential) throws { mutex.lock(); defer { mutex.unlock() }; saves += 1; credential = value }
        func remove() throws { mutex.lock(); defer { mutex.unlock() }; credential = nil }
    }
    @Test func test_M0P1b_02_configuredPresenceNeverLoadsSecretAndAutomaticBackupStillDoes() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"), commandLockURL: base.appendingPathComponent("CommandBus.lock"))
        let keys = PresenceKeys(), coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: keys)
        #expect(try !coordinator.hasConfiguredKey()); #expect(keys.accesses.0 == 0); #expect(keys.accesses.1 == 0)
        try await coordinator.configurePassphrase("correct long password")
        let writes = keys.accesses.1
        #expect(try coordinator.hasConfiguredKey()); #expect(keys.accesses.0 == 0); #expect(keys.accesses.1 == writes)
        #expect(try await coordinator.performScheduledBackupIfDue(schedule: .weekly) != nil)
        #expect(keys.accesses.0 == 1); #expect(keys.accesses.1 == writes + 1)
    }
    @Test func test_M0P1b_01_restoreAuthorizationRefusesBeforeKeyReadSafetyAndPromotion() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"), commandLockURL: base.appendingPathComponent("CommandBus.lock"))
        let keys = PresenceKeys(), coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: keys)
        let file = try backupFile([], base: base), generation = store.binding.generationID
        let preview = try await coordinator.preview(file: file, passphrase: "correct long password")
        enum Refusal: Error { case denied }
        var barrierHeld = false
        await #expect(throws: Refusal.denied) {
            try await coordinator.restore(preview: preview, mode: .replace, authorization: {
                barrierHeld = store.isBusy; throw Refusal.denied
            })
        }
        #expect(barrierHeld); #expect(!store.isBusy)
        #expect(keys.accesses.0 == 0); #expect(keys.accesses.1 == 0)
        #expect(try coordinator.catalog().isEmpty); #expect(store.binding.generationID == generation)
    }
    private func scratch() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarManagedTests-\(UUID())"); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url }
    private func backupFile(_ records: [DataRecord],base:URL) throws -> URL { let url = base.appendingPathComponent("Source.madarbackup"); try BackupCodec.export(records:records,passphrase:"correct long password").write(to:url); return url }
    private func makeCoordinator(base:URL,seed:Bool=false,lifecycle:BackupLifecycle=BackupLifecycle()) async throws -> (ManagedDataStore,BackupCoordinator,MemoryBackupKeyStore) {
        let store = try ManagedDataStore(root:base.appendingPathComponent("Managed"),commandLockURL:base.appendingPathComponent("CommandBus.lock"))
        if seed { try fixture(store.container.mainContext) }
        let keys = MemoryBackupKeyStore(); let coordinator = BackupCoordinator(store:store,backupDirectory:base.appendingPathComponent("Backups"),keyStore:keys,lifecycle:lifecycle)
        try await coordinator.configurePassphrase("correct long password"); return (store,coordinator,keys)
    }
    private func addBook(_ context: ModelContext, title: String, bytes: Int, turath: Int? = nil) throws -> (book: UUID, media: UUID) {
        let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ title.count) })
        let media = Media(); media.kind = "doc"; media.contentType = "com.adobe.pdf"; media.data = data; media.sizeBytes = data.count; media.sha256 = BackupCodec.hash(data); context.insert(media)
        let book = Book(); book.title = title; book.kind = "file"; book.format = "pdf"; book.mediaID = media.id; book.fileHash = media.sha256; book.turathID = turath; context.insert(book)
        try context.save(); return (book.id, media.id)
    }
    @Test func rd4BooksOverBudgetLeaveTurathFirstThenLargestAndBackupSucceeds() throws {
        let container = try MadarContainerFactory.makeInMemory(); try fixture(container.mainContext)
        let small = try addBook(container.mainContext, title: "صغير", bytes: 2_000)
        let large = try addBook(container.mainContext, title: "كبير", bytes: 9_000)
        let turath = try addBook(container.mainContext, title: "من تراث", bytes: 3_000, turath: 12028)
        let rows = try RecordBridge.all(container.mainContext); let total = BackupBookFiles.estimatedBytes(rows)
        #expect(BackupBookFiles.fitting(rows, budget: total).excluded.isEmpty)
        // Removing the Turath file alone is not enough; the largest user file goes next, the small one stays.
        let fitted = BackupBookFiles.fitting(rows, budget: total - 3_500)
        #expect(fitted.excluded.map(\.title) == ["من تراث", "كبير"]); #expect(fitted.excluded.first?.fromTurath == true)
        func media(_ id: UUID) -> DataRecord? { fitted.records.first { $0.model == "Media" && $0.id == id } }
        #expect(media(turath.media)?.fields["state"] == .string("missing")); #expect(media(turath.media)?.fields["data"] == .null)
        #expect(media(large.media)?.fields["state"] == .string("missing"))
        #expect(media(small.media)?.fields["state"] == .string("ok")); #expect(media(small.media)?.fields["data"] != .null)
        // Photos and audio are never candidates, and the archive still validates (missing is an allowed state).
        #expect(fitted.records.filter { $0.model == "Media" && $0.fields["kind"]?.string != "doc" } == rows.filter { $0.model == "Media" && $0.fields["kind"]?.string != "doc" })
        let sealed = try BackupCodec.export(records: fitted.records, passphrase: "correct long password")
        #expect(try BackupCodec.validate(sealed, passphrase: "correct long password").records.count == rows.count)
    }
    @Test func rd4RestoreKeepsDeviceBookBytesInMergeAndReplaceAndReportsExclusion() async throws {
        for mode in [RestoreMode.merge, .replace] {
            let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
            let (store,coordinator,_) = try await makeCoordinator(base:base,seed:true)
            let ids = try addBook(store.container.mainContext, title: "كتابي", bytes: 6_000)
            let before = try RecordBridge.all(store.container.mainContext).first { $0.model == "Media" && $0.id == ids.media }
            coordinator.bookBudget = try coordinator.estimatedBytes() - 1
            let receipt = try await coordinator.export(kind:.manual,now:Date().addingTimeInterval(10))
            #expect(try coordinator.status().excludedBooks == [BackupBookExclusion(title: "كتابي", bytes: 6_000, fromTurath: false)])
            let saved = try BackupCodec.validate(Data(contentsOf:receipt.fileURL),passphrase:"correct long password").records.first { $0.model == "Media" && $0.id == ids.media }
            #expect(saved?.fields["state"] == .string("missing")); #expect(saved?.fields["data"] == .null)
            let generationBeforePreview = store.binding.generationID
            let fingerprintBeforePreview = try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext))
            let preview = try await coordinator.preview(file:receipt.fileURL,passphrase:"correct long password")
            #expect(preview.warnings.contains("النسخة لا تتضمن ملفات بعض الكتب. يحتفظ الاسترجاع بالملفات المطابقة الموجودة على هذا الجهاز؛ وإلا فأعد استيرادها."))
            #expect(store.binding.generationID == generationBeforePreview)
            #expect(try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext)) == fingerprintBeforePreview)
            let result = try await coordinator.restore(preview:preview,mode:mode,now:Date().addingTimeInterval(100))
            let after = try RecordBridge.all(result.container.mainContext).first { $0.model == "Media" && $0.id == ids.media }
            #expect(after?.fields["state"] == .string("ok")); #expect(after?.fields["data"] == before?.fields["data"]); #expect(after?.isLive == true)
        }
    }
    @Test func rd4CleanRestoreWithoutTheDeviceFileMarksBookMissing() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext)
        let ids = try addBook(source.mainContext, title: "مفقود", bytes: 5_000)
        let rows = try RecordBridge.all(source.mainContext)
        let fitted = BackupBookFiles.fitting(rows, budget: BackupBookFiles.estimatedBytes(rows) - 1)
        let file = try backupFile(fitted.records,base:base); let (_,coordinator,_) = try await makeCoordinator(base:base)
        let result = try await coordinator.restore(preview:try await coordinator.preview(file:file,passphrase:"correct long password"),mode:.replace)
        let media = try RecordBridge.all(result.container.mainContext).first { $0.model == "Media" && $0.id == ids.media }
        #expect(media?.fields["state"] == .string("missing")); #expect(media?.fields["data"] == .null)
        #expect(try RecordBridge.all(result.container.mainContext).contains { $0.model == "Book" && $0.id == ids.book && $0.isLive })
    }
    @Test func logicalAdoptionPreservesAll61ModelsAndSourceAndReopens() throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let source = try MadarContainerFactory.makeLocal(at:base.appendingPathComponent("FlatNewMadar")); source.mainContext.autosaveEnabled = false; try fixture(source.mainContext)
        let setting = DeviceSetting(); setting.key = "core.theme"; setting.valueJSON = try JSONEncoder().encode("dark"); source.mainContext.insert(setting)
        source.mainContext.insert(NotificationLedger()); source.mainContext.insert(CommandReceipt()); source.mainContext.insert(PageSchedule()); source.mainContext.insert(SessionDraft()); source.mainContext.insert(ProcessingJob()); try source.mainContext.save()
        let before = try RecordBridge.all(source.mainContext,syncedOnly:false); let fingerprint = try RecordFingerprint.hash(before)
        let root = base.appendingPathComponent("Managed"); let lock = base.appendingPathComponent("CommandBus.lock")
        let adopted = try ManagedDataStore.adopt(from:source,at:root,commandLockURL:lock)
        #expect(try RecordFingerprint.hash(RecordBridge.all(adopted.container.mainContext,syncedOnly:false)) == fingerprint)
        #expect(try RecordFingerprint.hash(RecordBridge.all(source.mainContext,syncedOnly:false)) == fingerprint)
        #expect(Set(before.map(\.model)).count == 61)
        let reopened = try ManagedDataStore(root:root,commandLockURL:lock)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == fingerprint)
        #expect(reopened.binding.deviceStoreURL == root.appendingPathComponent("Device.store"))
    }
    @Test func adoptionInterruptionBeforeAndAfterPromotionRecovers() throws {
        for checkpoint in [ManagedDataStore.AdoptionCheckpoint.afterCopy,.afterPromotion] {
            let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
            let source = try MadarContainerFactory.makeLocal(at:base.appendingPathComponent("Flat")); try fixture(source.mainContext)
            let root = base.appendingPathComponent("Managed"); let lock = base.appendingPathComponent("CommandBus.lock"); let before = try RecordFingerprint.hash(RecordBridge.all(source.mainContext,syncedOnly:false))
            #expect(throws:(any Error).self) { try ManagedDataStore.adoptForTesting(from:source,at:root,commandLockURL:lock,interruption:checkpoint) }
            #expect(throws:BackupOperationError.busy) { try StoreLease.checkMaintenance(lockURL:lock) }
            let recovered = try ManagedDataStore.adopt(from:source,at:root,commandLockURL:lock)
            #expect(try RecordFingerprint.hash(RecordBridge.all(recovered.container.mainContext,syncedOnly:false)) == before)
            #expect(try RecordFingerprint.hash(RecordBridge.all(source.mainContext,syncedOnly:false)) == before)
            try StoreLease.checkMaintenance(lockURL:lock)
        }
    }
    @Test func freshRestoreAllSyncedModelsMediaTombstonesAndAliasesEqual() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext); let expected = try RecordBridge.all(source.mainContext)
        let file = try backupFile(expected,base:base); let (store,coordinator,_) = try await makeCoordinator(base:base)
        let deviceURL = store.binding.deviceStoreURL; let preview = try await coordinator.preview(file:file,passphrase:"correct long password")
        #expect(preview.counts.count == 56); #expect(preview.additions == expected.count)
        let result = try await coordinator.restore(preview:preview,mode:.replace)
        #expect(result.warnings.isEmpty); #expect(try RecordFingerprint.hash(RecordBridge.all(result.container.mainContext)) == RecordFingerprint.hash(expected))
        #expect(store.binding.deviceStoreURL == deviceURL); #expect(FileManager.default.fileExists(atPath:result.automaticBackup.fileURL.path))
        let reopened = try ManagedDataStore(root:store.root,commandLockURL:store.commandLockURL)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext)) == RecordFingerprint.hash(expected))
    }
    @Test func populatedReplaceRetainsAbsentTombstonesAndFixedDeviceSettings() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext); let incoming = try RecordBridge.all(source.mainContext); let file = try backupFile(incoming,base:base)
        let (store,coordinator,_) = try await makeCoordinator(base:base,seed:true)
        let context = store.container.mainContext; let extra = Entry(); extra.text = "current only"; context.insert(extra)
        let device = DeviceSetting(); device.key = "core.theme"; device.valueJSON = try JSONEncoder().encode("dark"); context.insert(device); try context.save()
        let extraID = extra.id; let deviceID = device.id; let deviceBefore = try device.record(); let deviceURL = store.binding.deviceStoreURL; let oldGeneration = store.binding.generationID
        let preview = try await coordinator.preview(file:file,passphrase:"correct long password"); #expect(preview.deletions >= 1)
        let now = Date().addingTimeInterval(100)
        let result = try await coordinator.restore(preview:preview,mode:.replace,now:now)
        let rows = try RecordBridge.all(result.container.mainContext)
        #expect(rows.first { $0.id == extraID }?.deletedAt != nil)
        #expect(rows.filter { $0.fields["mergedInto"] == .null && $0.id != extraID }.allSatisfy { ($0.date("updatedAt") ?? .distantPast) >= now })
        #expect(store.binding.generationID != oldGeneration); #expect(store.binding.deviceStoreURL == deviceURL)
        #expect(try result.container.mainContext.fetch(FetchDescriptor<DeviceSetting>()).first { $0.id == deviceID }?.record() == deviceBefore)
        let safety = try BackupArtifact.validate(file:result.automaticBackup.fileURL,passphrase:"correct long password")
        #expect(safety.records.contains { $0.id == extraID && $0.isLive })
    }
    @Test func interruptedRestoreBeforeCommitRetainsOldAndAfterCommitRecoversHooks() async throws {
        for checkpoint in [BackupCoordinator.Checkpoint.afterJournal,.afterStagingSave,.afterReady,.afterPointer] {
            let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
            let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext); let file = try backupFile(RecordBridge.all(source.mainContext),base:base)
            let (store,coordinator,keys) = try await makeCoordinator(base:base); let oldID = store.binding.generationID
            let preview = try await coordinator.preview(file:file,passphrase:"correct long password"); coordinator.interruption = checkpoint
            await #expect(throws:(any Error).self) { try await coordinator.restore(preview:preview,mode:.replace) }
            let recovered = try ManagedDataStore(root:store.root,commandLockURL:store.commandLockURL)
            if checkpoint == .afterPointer {
                #expect(recovered.binding.generationID != oldID); #expect(recovered.recoveryRequiresRefresh)
                let recovery = BackupCoordinator(store:recovered,backupDirectory:base.appendingPathComponent("Backups"),keyStore:keys)
                #expect(try await recovery.recoverPendingLifecycle().isEmpty); #expect(!recovered.recoveryRequiresRefresh)
                #expect(try RecordBridge.all(recovered.container.mainContext).count > 55)
            } else { #expect(recovered.binding.generationID == oldID); #expect(try RecordBridge.all(recovered.container.mainContext).isEmpty); #expect(!recovered.recoveryRequiresRefresh) }
            try StoreLease.checkMaintenance(lockURL:store.commandLockURL)
        }
    }
    @Test func cancellationDuringStagingKeepsOldGenerationAndCleansOnlyPartialWork() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext); let file = try backupFile(RecordBridge.all(source.mainContext),base:base)
        let (store,coordinator,_) = try await makeCoordinator(base:base); let oldID = store.binding.generationID
        let preview = try await coordinator.preview(file:file,passphrase:"correct long password"); let cancel = BackupCancellation()
        await #expect(throws:BackupOperationError.cancelled) { try await coordinator.restore(preview:preview,mode:.replace,progress:{ if $0.phase == .staging && $0.completedUnits >= 2 { cancel.cancel() } },cancellation:cancel) }
        #expect(store.binding.generationID == oldID); #expect(try RecordBridge.all(store.container.mainContext).isEmpty)
        #expect(try coordinator.catalog().count == 1); #expect(!FileManager.default.fileExists(atPath:store.journalURL.path)); try StoreLease.checkMaintenance(lockURL:store.commandLockURL)
    }
    @Test func retentionScheduleCredentialNonceAndCancelExportKeepPreviousBackup() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let (_,coordinator,keys) = try await makeCoordinator(base:base,seed:true); let initial = try keys.load()!.nextNonceCounter
        let now = Date(timeIntervalSince1970:2_000_000_000)
        let manual = try await coordinator.export(kind:.manual,now:now); let manualBytes = try Data(contentsOf:manual.fileURL)
        for day in 1...6 { _ = try await coordinator.export(kind:.automatic,now:now.addingTimeInterval(Double(day)*86400)) }
        #expect(try coordinator.catalog().filter { $0.kind == .automatic }.count == 4); #expect(try coordinator.catalog().filter { $0.kind == .manual }.count == 1)
        // Fixture has a photo and audio: index + two distinct media envelopes per automatic set.
        let finalCounter = try keys.load()!.nextNonceCounter
        #expect(finalCounter == initial + 19)
        #expect(try await coordinator.performScheduledBackupIfDue(schedule:.weekly,now:now.addingTimeInterval(7*86400)) == nil)
        #expect(try await coordinator.performScheduledBackupIfDue(schedule:.daily,now:now.addingTimeInterval(7*86400)) != nil)
        let cancel = BackupCancellation()
        await #expect(throws:BackupOperationError.cancelled) { try await coordinator.export(progress:{ if $0.phase == .writing { cancel.cancel() } },cancellation:cancel) }
        #expect(try Data(contentsOf:manual.fileURL) == manualBytes); #expect(try coordinator.status().lastResult == "cancelled")
        #expect(try FileManager.default.contentsOfDirectory(atPath:coordinator.backupDirectory.path).allSatisfy { !$0.hasSuffix(".partial") })
    }
    @Test func authenticatedMissingMediaAndMalformedRowsLeaveLiveDiskByteIdentical() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let (store,coordinator,_) = try await makeCoordinator(base:base,seed:true)
        let records = try RecordBridge.all(store.container.mainContext); let originalFiles = try BackupCodec.decodeArchive(BackupCodec.archive(records:records)); let credential = try BackupCredential.derive(passphrase:"correct long password")
        func diskBytes() throws -> [String:Data] {
            let files = FileManager.default.enumerator(at:store.root,includingPropertiesForKeys:[.isRegularFileKey])!.allObjects.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true }
            return try Dictionary(uniqueKeysWithValues:files.map { ($0.path,try Data(contentsOf:$0)) })
        }
        let before = try diskBytes()
        for missing in [true,false] {
            var files = originalFiles
            if missing { let name = files.keys.first { $0.hasPrefix("media/") }!; files.removeValue(forKey:name) }
            else {
                let name = "data/PrayerLog.jsonl"; var field = try JSONDecoder().decode([String:JSONValue].self,from:Data(files[name]!.split(separator:0x0a)[0])); field["status"] = .string("invalid-status"); var data = try JSONValue.object(field).canonicalData(); data.append(0x0a); files[name] = data
            }
            let old = try JSONDecoder().decode(BackupManifest.self,from:files["manifest.json"]!)
            let manifest = BackupManifest(formatVersion:old.formatVersion,storeSchemaVersion:old.storeSchemaVersion,createdAt:old.createdAt,counts:old.counts,files:files.filter { $0.key != "manifest.json" }.map { .init(path:$0.key,bytes:$0.value.count,sha256:BackupCodec.hash($0.value)) })
            files["manifest.json"] = try JSONEncoder().encode(manifest)
            let encrypted = try BackupCodec.seal(archive:BackupCodec.encodeArchive(files),credential:credential,noncePrefix:BackupCodec.random(count:4))
            let file = base.appendingPathComponent(missing ? "Missing.madarbackup" : "Malformed.madarbackup"); try encrypted.write(to:file)
            await #expect(throws:(any Error).self) { try await coordinator.preview(file:file,passphrase:"correct long password") }
            #expect(try diskBytes() == before)
        }
    }
    @Test func stalePreviewRejectsWithoutBackupOrPromotionAndLeaseFailsFast() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let (store,coordinator,_) = try await makeCoordinator(base:base,seed:true); let file = try backupFile(RecordBridge.all(store.container.mainContext),base:base)
        let preview = try await coordinator.preview(file:file,passphrase:"correct long password"); let changed = Entry(); store.container.mainContext.insert(changed); try store.container.mainContext.save(); let id = store.binding.generationID
        await #expect(throws:BackupOperationError.stalePreview) { try await coordinator.restore(preview:preview,mode:.replace) }
        #expect(try coordinator.catalog().isEmpty); #expect(store.binding.generationID == id)
        let first = StoreLease(lockURL:store.commandLockURL); try first.acquire(); defer { first.release() }; try first.beginMaintenance(operationID:UUID())
        #expect(throws:BackupOperationError.busy) { try StoreLease.checkMaintenance(lockURL:store.commandLockURL) }
        let second = StoreLease(lockURL:store.commandLockURL); #expect(throws:BackupOperationError.busy) { try second.acquire() }; try first.endMaintenance()
    }
    @Test func committedHookFailureResumesAndReplayClearsLocalDerivedRows() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        enum HookError: Error { case unavailable }
        var resumes = 0
        let lifecycle = BackupLifecycle(rebuildSnapshots: { _ in throw HookError.unavailable }, resume: { resumes += 1 })
        let (store,coordinator,keys) = try await makeCoordinator(base:base,lifecycle:lifecycle)
        store.container.mainContext.insert(PageSchedule()); store.container.mainContext.insert(SessionDraft()); store.container.mainContext.insert(ProcessingJob()); try store.container.mainContext.save()
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext)
        let file = try backupFile(RecordBridge.all(source.mainContext),base:base)
        let preview = try await coordinator.preview(file:file,passphrase:"correct long password")
        let result = try await coordinator.restore(preview:preview,mode:.replace)
        #expect(result.warnings.count == 1); #expect(resumes == 1); #expect(store.recoveryRequiresRefresh)
        try StoreLease.checkMaintenance(lockURL:store.commandLockURL)
        #expect(try store.container.mainContext.fetch(FetchDescriptor<PageSchedule>()).isEmpty)
        #expect(try store.container.mainContext.fetch(FetchDescriptor<SessionDraft>()).isEmpty)
        #expect(try store.container.mainContext.fetch(FetchDescriptor<ProcessingJob>()).isEmpty)
        let reopened = try ManagedDataStore(root:store.root,commandLockURL:store.commandLockURL)
        let recovery = BackupCoordinator(store:reopened,backupDirectory:coordinator.backupDirectory,keyStore:keys)
        #expect(try await recovery.recoverPendingLifecycle().isEmpty); #expect(!reopened.recoveryRequiresRefresh)
    }
    @Test func initializationJournalRetryAndLocalAccountRotationKeepDeviceStore() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let root = base.appendingPathComponent("Managed"); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let desired = ManagedPointer(version:1,generationID:UUID(),previousGenerationID:nil,accountHash:"A",cloudKitContainerIdentifier:nil)
        try DurableFiles.encode(desired,to:root.appendingPathComponent("InitializationJournal.json"))
        let store = try ManagedDataStore(root:root,commandLockURL:base.appendingPathComponent("CommandBus.lock"))
        #expect(store.binding.generationID == desired.generationID); #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("InitializationJournal.json").path))
        try fixture(store.container.mainContext)
        let keys = MemoryBackupKeyStore(); let coordinator = BackupCoordinator(store:store,backupDirectory:base.appendingPathComponent("Backups"),keyStore:keys)
        try await coordinator.configurePassphrase("correct long password")
        let device = DeviceSetting(); device.key = "core.theme"; device.valueJSON = try JSONEncoder().encode("dark"); store.container.mainContext.insert(device); try store.container.mainContext.save()
        let deviceRecord = try device.record(); let syncedHash = try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext)); let fixedURL = store.binding.deviceStoreURL
        _ = try await coordinator.rotateLocalStore(accountHash:"B",preservingCurrentRows:true)
        #expect(store.binding.accountHash == "B"); #expect(try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext)) == syncedHash)
        _ = try await coordinator.rotateLocalStore(accountHash:nil,preservingCurrentRows:false)
        #expect(store.binding.accountHash == nil); #expect(try RecordBridge.all(store.container.mainContext).isEmpty)
        #expect(store.binding.deviceStoreURL == fixedURL)
        #expect(try RecordBridge.all(store.container.mainContext,syncedOnly:false).contains(deviceRecord))
        let reopened = try ManagedDataStore(root:root,commandLockURL:store.commandLockURL)
        #expect(reopened.binding.accountHash == nil); #expect(try RecordBridge.all(reopened.container.mainContext,syncedOnly:false).contains(deviceRecord))
    }

}
