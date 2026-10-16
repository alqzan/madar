import Foundation
import SwiftData

/// Forward conversion under the app's existing store lease. Old generations remain rollback sources.
@MainActor enum LegacyGenerationMigration {
    enum Checkpoint: String { case afterCopy, afterStaging, afterHooksJournal, afterPointer }
    private struct Journal: Codable { let oldID: UUID; let newID: UUID; var preserveDeviceRows: Bool? = nil }
    private struct CommandReceiptScope: Codable { let version: Int; let generationID: UUID }
    static func migrate(pointer: ManagedPointer, root: URL, interruption: Checkpoint?) throws -> ManagedPointer {
        let journalURL = root.appendingPathComponent("SchemaMigration.json")
        let originalDirectory = root.appendingPathComponent("Generations/\(pointer.generationID.uuidString)")
        let version = try MadarContainerFactory.storeVersion(at:originalDirectory)
        if version == MadarSchema.version {
            // Promotion committed; normal restore recovery finishes app snapshot/history hooks.
            if FileManager.default.fileExists(atPath:journalURL.path) {
                let journal = try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journalURL))
                guard journal.newID == pointer.generationID else { throw BackupOperationError.invalidManagedStore }
                if journal.preserveDeviceRows == true {
                    try retagReceiptScopes(in: originalDirectory, root: root, from: journal.oldID, to: journal.newID)
                }
                try FileManager.default.removeItem(at:journalURL)
            }
            return pointer
        }
        if version == 2 || version == 3 { return try migrateV2(pointer: pointer, root: root, interruption: interruption) }
        guard version == 1 else { throw DataError.legacyStoreRequiresAdoption }
        guard FileManager.default.fileExists(atPath:originalDirectory.appendingPathComponent("GenerationReady.json").path) else { throw BackupOperationError.invalidManagedStore }
        try SchemaCompatibility.validateDeviceVersion(at: root)
        var journal: Journal
        if FileManager.default.fileExists(atPath:journalURL.path) {
            journal = try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journalURL))
            guard journal.oldID == pointer.generationID else { throw BackupOperationError.invalidManagedStore }
        } else {
            journal = .init(oldID:pointer.generationID,newID:UUID())
        }
        // The active pointer decides whether an older restore committed. Persist this obligation
        // before replacing its hooks journal, so retries before/after migration promotion keep it.
        let restoreURL = root.appendingPathComponent("RestoreJournal.json")
        var preserveDeviceRows = true
        if FileManager.default.fileExists(atPath:restoreURL.path) {
            let restore = try JSONDecoder().decode(RestoreJournal.self,from:Data(contentsOf:restoreURL))
            guard restore.oldGenerationID != restore.newGenerationID else { throw BackupOperationError.invalidManagedStore }
            if pointer.generationID == restore.newGenerationID {
                preserveDeviceRows = restore.preserveDeviceRows == true
            } else if pointer.generationID == restore.oldGenerationID {
                guard restore.phase != .promoted else { throw BackupOperationError.invalidManagedStore }
                if restore.newGenerationID != journal.newID {
                    let abandoned = root.appendingPathComponent("Generations/\(restore.newGenerationID.uuidString)")
                    if FileManager.default.fileExists(atPath:abandoned.path) { try FileManager.default.removeItem(at:abandoned) }
                }
            } else { throw BackupOperationError.invalidManagedStore }
        }
        journal.preserveDeviceRows = journal.preserveDeviceRows ?? preserveDeviceRows
        try DurableFiles.encode(journal,to:journalURL)
        let safety = root.appendingPathComponent("MigrationSafety/\(journal.oldID.uuidString)")
        try FileManager.default.createDirectory(at:safety,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let sourceCopy = safety.appendingPathComponent("SourceV1")
        // Retry reads a fresh source clone; the original DB/WAL/SHM and generation are never opened.
        if FileManager.default.fileExists(atPath:sourceCopy.path) { try FileManager.default.removeItem(at:sourceCopy) }
        let original = try LegacyV1Reader.read(syncedDirectory:originalDirectory,deviceStoreURL:root.appendingPathComponent("Device.store"),copiedTo:sourceCopy)
        try DurableFiles.encode(original,to:safety.appendingPathComponent("RecordsV1.json"))
        let reread = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:safety.appendingPathComponent("RecordsV1.json")))
        guard try RecordFingerprint.hash(reread) == RecordFingerprint.hash(original) else { throw BackupOperationError.invalidManagedStore }
        try DurableFiles.encode(try RecordFingerprint.hash(original),to:safety.appendingPathComponent("RecordsV1.sha256.json"))
        if interruption == .afterCopy { throw BackupOperationError.simulatedInterruption("migration afterCopy") }
        let converted = try SchemaCompatibility.currentRecords(original,from:1)
        let synced = converted.filter { MadarSchema.syncedNames.contains($0.model) }
        let staging = root.appendingPathComponent("Generations/\(journal.newID.uuidString)")
        if FileManager.default.fileExists(atPath:staging.path) { try FileManager.default.removeItem(at:staging) }
        func stage() throws {
            let container = try MadarContainerFactory.makeSyncedStaging(at:staging)
            container.mainContext.autosaveEnabled = false
            for row in synced { try RecordBridge.insert(row,in:container.mainContext) }
            try container.mainContext.save()
            let written = try RecordBridge.all(container.mainContext)
            guard written.count == synced.count, try RecordFingerprint.hash(written) == RecordFingerprint.hash(synced) else { throw BackupOperationError.invalidManagedStore }
            try DurableFiles.encode(GenerationReady(version:1,generationID:journal.newID,recordsHash:try RecordFingerprint.hash(written),createdAt:Date()),to:staging.appendingPathComponent("GenerationReady.json"))
        }
        try stage()
        if interruption == .afterStaging { throw BackupOperationError.simulatedInterruption("migration afterStaging") }
        // The unchanged device entity schema can reopen the fixed file. Validate rows before promotion.
        func validateDevice() throws {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("MadarDeviceValidation-\(UUID())")
            try FileManager.default.copyItem(at:sourceCopy,to:copy); defer { try? FileManager.default.removeItem(at:copy) }
            // The V1 device file was created with a combined schema. Validate with the current
            // combined schema too; SDK metadata migration may write only this expendable clone.
            for file in try FileManager.default.contentsOfDirectory(at:copy,includingPropertiesForKeys:nil) where !file.lastPathComponent.hasPrefix("Device.store") {
                try FileManager.default.removeItem(at:file)
            }
            for file in try FileManager.default.contentsOfDirectory(at:staging,includingPropertiesForKeys:nil) {
                try FileManager.default.copyItem(at:file,to:copy.appendingPathComponent(file.lastPathComponent))
            }
            let device = try MadarContainerFactory.make(at:copy,deviceStoreURL:copy.appendingPathComponent("Device.store"))
            device.mainContext.autosaveEnabled = false
            let rows = try RecordBridge.deviceRecords(device.mainContext)
            let expected = original.filter { !MadarSchemaV1.syncedNames.contains($0.model) }
            guard rows.count == expected.count, try RecordFingerprint.hash(rows) == RecordFingerprint.hash(expected) else { throw BackupOperationError.invalidManagedStore }
        }
        try validateDevice()
        let replacement = ManagedPointer(version:pointer.version,generationID:journal.newID,previousGenerationID:pointer.generationID,accountHash:pointer.accountHash,cloudKitContainerIdentifier:pointer.cloudKitContainerIdentifier)
        let hooks = RestoreJournal(operationID:UUID(),oldGenerationID:journal.oldID,newGenerationID:journal.newID,phase:.ready,hooksPending:true,preserveDeviceRows:journal.preserveDeviceRows)
        try DurableFiles.encode(hooks,to:root.appendingPathComponent("RestoreJournal.json"))
        if interruption == .afterHooksJournal { throw BackupOperationError.simulatedInterruption("migration afterHooksJournal") }
        try DurableFiles.encode(replacement,to:root.appendingPathComponent("ActiveGeneration.json"))
        if interruption == .afterPointer { throw BackupOperationError.simulatedInterruption("migration afterPointer") }
        try FileManager.default.removeItem(at:journalURL)
        return replacement
    }

    /// Upgrade the prior managed generation on a staged copy so the schema migration never edits its rollback source.
    private static func migrateV2(pointer: ManagedPointer, root: URL, interruption: Checkpoint?) throws -> ManagedPointer {
        let oldID = pointer.generationID
        let originalDirectory = root.appendingPathComponent("Generations/\(oldID.uuidString)", isDirectory: true)
        let originalReadyURL = originalDirectory.appendingPathComponent("GenerationReady.json")
        guard FileManager.default.fileExists(atPath: originalReadyURL.path) else { throw BackupOperationError.invalidManagedStore }
        let originalReady = try JSONDecoder().decode(GenerationReady.self, from: Data(contentsOf: originalReadyURL))
        guard originalReady.generationID == oldID else { throw BackupOperationError.invalidManagedStore }

        let journalURL = root.appendingPathComponent("SchemaMigration.json")
        var journal: Journal
        if FileManager.default.fileExists(atPath: journalURL.path) {
            journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            guard journal.oldID == oldID else { throw BackupOperationError.invalidManagedStore }
        } else {
            journal = .init(oldID: oldID, newID: UUID())
        }

        var preserveDeviceRows = true
        let restoreURL = root.appendingPathComponent("RestoreJournal.json")
        if FileManager.default.fileExists(atPath: restoreURL.path) {
            let restore = try JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: restoreURL))
            guard restore.oldGenerationID != restore.newGenerationID else { throw BackupOperationError.invalidManagedStore }
            if oldID == restore.newGenerationID {
                preserveDeviceRows = restore.preserveDeviceRows == true
            } else if oldID == restore.oldGenerationID {
                guard restore.phase != .promoted else { throw BackupOperationError.invalidManagedStore }
                if restore.newGenerationID != journal.newID {
                    let abandoned = root.appendingPathComponent("Generations/\(restore.newGenerationID.uuidString)")
                    if FileManager.default.fileExists(atPath: abandoned.path) { try FileManager.default.removeItem(at: abandoned) }
                }
            } else {
                throw BackupOperationError.invalidManagedStore
            }
        }
        journal.preserveDeviceRows = journal.preserveDeviceRows ?? preserveDeviceRows
        try DurableFiles.encode(journal, to: journalURL)

        let staging = root.appendingPathComponent("Generations/\(journal.newID.uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: originalDirectory, to: staging)
        if interruption == .afterCopy { throw BackupOperationError.simulatedInterruption("schema-2 migration afterCopy") }

        let rows = try migrateCopiedV2Generation(staging, root: root, pointer: pointer)
        guard try MadarContainerFactory.storeVersion(at: staging) == MadarSchema.version else { throw BackupOperationError.invalidManagedStore }
        try RecordValidator.validate(rows)
        let ready = GenerationReady(version: 1, generationID: journal.newID,
            recordsHash: try RecordFingerprint.hash(rows), createdAt: Date())
        try DurableFiles.encode(ready, to: staging.appendingPathComponent("GenerationReady.json"))
        if interruption == .afterStaging { throw BackupOperationError.simulatedInterruption("schema-2 migration afterStaging") }

        let replacement = ManagedPointer(version: pointer.version, generationID: journal.newID,
            previousGenerationID: oldID, accountHash: pointer.accountHash,
            cloudKitContainerIdentifier: pointer.cloudKitContainerIdentifier)
        let hooks = RestoreJournal(operationID: UUID(), oldGenerationID: oldID, newGenerationID: journal.newID,
            phase: .ready, hooksPending: true, preserveDeviceRows: journal.preserveDeviceRows)
        try DurableFiles.encode(hooks, to: restoreURL)
        if interruption == .afterHooksJournal { throw BackupOperationError.simulatedInterruption("schema-2 migration afterHooksJournal") }
        try DurableFiles.encode(replacement, to: root.appendingPathComponent("ActiveGeneration.json"))
        if interruption == .afterPointer { throw BackupOperationError.simulatedInterruption("schema-2 migration afterPointer") }
        if journal.preserveDeviceRows == true {
            try retagReceiptScopes(in: staging, root: root, from: oldID, to: journal.newID)
        }
        try FileManager.default.removeItem(at: journalURL)
        return replacement
    }

    private static func migrateCopiedV2Generation(_ staging: URL, root: URL, pointer: ManagedPointer) throws -> [DataRecord] {
        let container = try MadarContainerFactory.make(at: staging,
            deviceStoreURL: root.appendingPathComponent("Device.store"),
            cloudKitContainerIdentifier: pointer.cloudKitContainerIdentifier)
        container.mainContext.autosaveEnabled = false
        return try RecordBridge.all(container.mainContext)
    }

    /// Synced facts are identical across this additive schema migration. Keep their
    /// device-local undo/replay receipts in the new generation so they remain usable.
    private static func retagReceiptScopes(in generation: URL, root: URL, from oldID: UUID, to newID: UUID) throws {
        let container = try MadarContainerFactory.make(at: generation, deviceStoreURL: root.appendingPathComponent("Device.store"))
        let context = ModelContext(container); context.autosaveEnabled = false
        let receiptIDs = Set(try context.fetch(FetchDescriptor<CommandReceipt>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .map(\.id))
        var changed = false
        for scope in try context.fetch(FetchDescriptor<DeviceSetting>()) where scope.key.hasPrefix("sys.commandReceiptScope:") && scope.deletedAt == nil && scope.mergedInto == nil {
            guard let id = UUID(uuidString: String(scope.key.dropFirst("sys.commandReceiptScope:".count))), receiptIDs.contains(id),
                  let decoded = try? JSONDecoder().decode(CommandReceiptScope.self, from: scope.valueJSON),
                  decoded.version == 1, decoded.generationID == oldID else { continue }
            scope.valueJSON = try JSONEncoder().encode(CommandReceiptScope(version: 1, generationID: newID))
            changed = true
        }
        if changed { try context.save() }
    }
}
