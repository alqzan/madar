import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct SchemaCompatibilityTests {
    private var resources: URL { Bundle.module.resourceURL!.appendingPathComponent("Resources/LegacyV1") }
    private func fixtureDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSchemaV1Test-\(UUID())")
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto")
        process.arguments = ["-x","-k",resources.appendingPathComponent("flat.zip").path,base.appendingPathComponent("Flat").path]
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        return base
    }
    private func expectedRows() throws -> [DataRecord] {
        try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("expected-v2-records.json")))
    }
    @Test func originalGlobalTypesSQLiteOpensWithFrozenV1Reader() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let flat = base.appendingPathComponent("Flat")
        let rows = try LegacyV1Reader.read(syncedDirectory:flat,deviceStoreURL:flat.appendingPathComponent("Device.store"),copiedTo:base.appendingPathComponent("ReadCopy"))
        let old = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("records.json")))
        #expect(try RecordFingerprint.hash(rows) == RecordFingerprint.hash(old))
    }
    @Test func test_M0S1_RA4_originalV1ArchiveMapsOnlyAfterAuthentication() throws {
        let bytes = try Data(contentsOf:resources.appendingPathComponent("source-v1.madarbackup"))
        let backup = try BackupCodec.validate(bytes,passphrase:"legacy fixture password")
        #expect(MadarSchema.version == 2)
        #expect(backup.records.contains { $0.model == "MoneyTransaction" })
        #expect(!backup.records.contains { $0.model == "Transaction" })
        let expected = try expectedRows().filter { MadarSchema.syncedNames.contains($0.model) }
        #expect(try RecordFingerprint.hash(backup.records) == RecordFingerprint.hash(expected))
        let money = try #require(backup.records.first { $0.model == "MoneyTransaction" && $0.fields["mergedInto"] == .null })
        #expect(money.fields["amountMinor"] == .number(12345)); #expect(money.fields["currency"] == .string("KWD"))
        #expect(money.fields["restoredAt"] == .number(-978307025))
        #expect(money.fields["homeAmountMinor"] == .number(151234)); #expect(money.fields["dayKey"] == .string("2026-02-03"))
        #expect(throws:DataError.authenticationFailed) { try BackupCodec.validate(bytes,passphrase:"wrong fixture password") }
        var corrupt = bytes; corrupt[corrupt.count-20] ^= 1
        #expect(throws:DataError.authenticationFailed) { try BackupCodec.validate(corrupt,passphrase:"legacy fixture password") }
        let target = try MadarContainerFactory.makeInMemory()
        for row in backup.records { try RecordBridge.insert(row,in:target.mainContext) }; try target.mainContext.save()
        #expect(try RecordFingerprint.hash(RecordBridge.all(target.mainContext)) == RecordFingerprint.hash(expected))
        let newBytes = try BackupCodec.export(records:backup.records,passphrase:"new fixture password")
        let current = try BackupCodec.validate(newBytes,passphrase:"new fixture password")
        #expect(current.manifest.storeSchemaVersion == 2)
        #expect(current.manifest.counts["MoneyTransaction"] == 2 && current.manifest.counts["Transaction"] == nil)
    }
    @Test func test_M0S1_RA4_originalSQLiteIsAdoptedWithoutLosingAnyRow() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let managed = try ManagedDataStore.adoptLegacy(from:base.appendingPathComponent("Flat"),at:base.appendingPathComponent("Managed"))
        #expect(MadarSchema.version == 2)
        #expect(try RecordFingerprint.hash(RecordBridge.all(managed.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try managed.container.mainContext.fetchCount(FetchDescriptor<DeviceSetting>()) == 2)
        #expect(try managed.container.mainContext.fetchCount(FetchDescriptor<CommandReceipt>()) == 1)
        let reopened = try ManagedDataStore(root:managed.root)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    private func fileHashes(_ directory: URL) throws -> [String:String] {
        let files = try #require(FileManager.default.enumerator(atPath:directory.path))
        var result: [String:String] = [:]
        for case let relativePath as String in files {
            let url = directory.appendingPathComponent(relativePath)
            if try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
                result[relativePath] = BackupCodec.hash(try Data(contentsOf:url))
            }
        }
        return result
    }
    @Test func test_M0S1_RA4_fileHashesKeepSourcePathsRelativeAndOnlyExcludeRootLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarFileHashesTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at:root) }
        let sourcePaths = ["Device.store", "Device.store-wal", "Device.store-shm", "DeviceSchemaVersion.json",
                           "ActiveGeneration.json", "Generations/old/Madar.store", "Generations/old/GenerationReady.json",
                           "Generations/old/SchemaVersion.json", "Media/photo.bin", "Media/CommandBus.lock"]
        let expectedHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" // SHA-256 of "hello".
        for path in sourcePaths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("hello".utf8).write(to:file)
        }
        let before = try fileHashes(root)
        #expect(before == Dictionary(uniqueKeysWithValues:sourcePaths.map { ($0,expectedHash) }))
        try Data().write(to:root.appendingPathComponent("CommandBus.lock"))
        let after = try fileHashes(root)
        #expect(after["CommandBus.lock"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(after.filter { $0.key != "CommandBus.lock" } == before)
        #expect(after["Media/CommandBus.lock"] == expectedHash)
        try Data("changed".utf8).write(to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        #expect(try fileHashes(root).filter { $0.key != "CommandBus.lock" } != before)
    }
    private func oldManagedFixture(_ base: URL) throws -> (URL,UUID,URL) {
        let root = base.appendingPathComponent("ManagedV1")
        let id = UUID(uuidString:"00000000-0000-0000-0000-000000000099")!
        let generation = root.appendingPathComponent("Generations/\(id.uuidString)")
        try FileManager.default.createDirectory(at:generation.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.copyItem(at:base.appendingPathComponent("Flat"),to:generation)
        for url in try FileManager.default.contentsOfDirectory(at:generation,includingPropertiesForKeys:nil) where url.lastPathComponent.hasPrefix("Device.store") {
            try FileManager.default.moveItem(at:url,to:root.appendingPathComponent(url.lastPathComponent))
        }
        try DurableFiles.encode(1,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let old = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("records.json")))
        try DurableFiles.encode(GenerationReady(version:1,generationID:id,recordsHash:try RecordFingerprint.hash(old.filter { MadarSchemaV1.syncedNames.contains($0.model) }),createdAt:Date(timeIntervalSince1970:123456)),to:generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version:1,generationID:id,previousGenerationID:nil,accountHash:"legacy-account",cloudKitContainerIdentifier:"iCloud.legacy.fixture"),to:root.appendingPathComponent("ActiveGeneration.json"))
        return (root,id,generation)
    }
    @Test(arguments:[LegacyGenerationMigration.Checkpoint.afterCopy,.afterStaging,.afterPointer])
    func test_M0S1_RA4_managedMigrationRecoversAtEveryCommitBoundary(_ checkpoint: LegacyGenerationMigration.Checkpoint) async throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let (root,oldID,generation) = try oldManagedFixture(base)
        let originalHashes = try fileHashes(generation)
        let pointerBytes = try Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json"))
        #expect(throws:BackupOperationError.simulatedInterruption("migration \(checkpoint.rawValue)")) {
            try ManagedDataStore(root:root,migrationInterruption:checkpoint)
        }
        #expect(try fileHashes(generation) == originalHashes)
        if checkpoint != .afterPointer { #expect(try Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json")) == pointerBytes) }
        let migrated = try ManagedDataStore(root:root)
        #expect(migrated.binding.generationID != oldID)
        #expect(migrated.binding.accountHash == "legacy-account" && !migrated.isCloudBacked)
        #expect(migrated.recoveryRequiresRefresh)
        let pointer = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json")))
        #expect(pointer.previousGenerationID == oldID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(migrated.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try fileHashes(generation) == originalHashes)
        let reopened = try ManagedDataStore(root:root)
        #expect(reopened.binding.generationID == migrated.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("SchemaMigration.json").path))
        let coordinator = BackupCoordinator(store:reopened,backupDirectory:base.appendingPathComponent("Backups"),keyStore:MemoryBackupKeyStore())
        #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
        #expect(!reopened.recoveryRequiresRefresh)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    @Test func test_M0S1_RA4_invalidDeviceStampNeverPromotesOrChangesOldSource() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let (root,_,generation) = try oldManagedFixture(base)
        try DurableFiles.encode(999,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let hashes = try fileHashes(root)
        #expect(hashes["CommandBus.lock"] == nil)
        #expect(throws:DataError.newerStore) { try ManagedDataStore(root:root) }
        let after = try fileHashes(root)
        #expect(after["CommandBus.lock"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(after.filter { $0.key != "CommandBus.lock" } == hashes)
        #expect(try MadarContainerFactory.storeVersion(at:generation) == 1)
        try DurableFiles.encode(1,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let repaired = try ManagedDataStore(root:root)
        #expect(try RecordFingerprint.hash(RecordBridge.all(repaired.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    @Test func test_M0S1_RA4_flatSourceIsByteIdenticalAndNeverOpenedByCurrentFactory() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let flat = base.appendingPathComponent("Flat"); let before = try fileHashes(flat)
        #expect(throws:DataError.legacyStoreRequiresAdoption) { try MadarContainerFactory.makeLocal(at:flat) }
        _ = try ManagedDataStore.adoptLegacy(from:flat,at:base.appendingPathComponent("Adopted"))
        #expect(try fileHashes(flat) == before)
    }

    @Test func test_M0S1_M0R4_01_committedRestoreCleanupSurvivesMigrationAndReopen() async throws {
        for phase in [RestoreJournal.Phase.ready, .promoted] {
            for checkpoint in [LegacyGenerationMigration.Checkpoint.afterCopy, .afterStaging, .afterHooksJournal, .afterPointer] {
                let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
                let (root, id, generation) = try oldManagedFixture(base)
                let sourceHashes = try fileHashes(generation)
                try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: UUID(), newGenerationID: id, phase: phase, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
                #expect(throws: BackupOperationError.simulatedInterruption("migration \(checkpoint.rawValue)")) {
                    try ManagedDataStore(root: root, migrationInterruption: checkpoint)
                }
                let store = try ManagedDataStore(root: root)
                let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
                #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
                let context = store.container.mainContext
                #expect(try context.fetchCount(FetchDescriptor<PageSchedule>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<SessionDraft>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<ProcessingJob>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<CommandReceipt>()) == 1)
                #expect(try fileHashes(generation) == sourceHashes)
                #expect(!store.recoveryRequiresRefresh)
            }
        }
    }
    @Test func test_M0S1_M0R4_01_uncommittedRestorePreservesDeviceRowsAndRejectsMismatch() async throws {
        for phase in [RestoreJournal.Phase.preparing, .ready] {
            let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
            let (root, id, _) = try oldManagedFixture(base)
            let abandoned = UUID(); let staging = root.appendingPathComponent("Generations/\(abandoned.uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: id, newGenerationID: abandoned, phase: phase, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
            let store = try ManagedDataStore(root: root)
            let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
            #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
            #expect(try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expectedRows()))
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let (root, _, _) = try oldManagedFixture(base)
        try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: UUID(), newGenerationID: UUID(), phase: .ready, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
        let before = try fileHashes(root)
        #expect(throws: BackupOperationError.invalidManagedStore) { try ManagedDataStore(root: root) }
        #expect(try fileHashes(root).filter { $0.key != "CommandBus.lock" } == before)
    }

    @Test func test_M0S1_M0R4_02_flatAdoptionPreflightsDeviceStampWithoutTargetWrites() throws {
        for stamp in ["999", "0", "-1", "\"malformed\"", "{"] {
            let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
            let flat = base.appendingPathComponent("Flat"); let target = base.appendingPathComponent("Adopted")
            try Data(stamp.utf8).write(to: flat.appendingPathComponent("DeviceSchemaVersion.json"))
            let before = try fileHashes(flat)
            if stamp == "999" {
                #expect(throws: DataError.newerStore) { try ManagedDataStore.adoptLegacy(from: flat, at: target) }
            } else {
                #expect(throws: (any Error).self) { try ManagedDataStore.adoptLegacy(from: flat, at: target) }
            }
            #expect(try fileHashes(flat) == before)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("Adopted-AdoptionJournal.json").path))
        }
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let flat = base.appendingPathComponent("Flat"); let stamp = flat.appendingPathComponent("DeviceSchemaVersion.json")
        if FileManager.default.fileExists(atPath: stamp.path) { try FileManager.default.removeItem(at: stamp) }
        let before = try fileHashes(flat)
        let adopted = try ManagedDataStore.adoptLegacy(from: flat, at: base.appendingPathComponent("Adopted"))
        #expect(try RecordFingerprint.hash(RecordBridge.all(adopted.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try fileHashes(flat) == before)
    }

}
