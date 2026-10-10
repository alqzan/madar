import Foundation
import SwiftData

/// Forward conversion under the app's existing store lease. Old generations remain rollback sources.
@MainActor enum LegacyGenerationMigration {
    enum Checkpoint: String { case afterCopy, afterStaging, afterPointer }
    private struct Journal: Codable { let oldID: UUID; let newID: UUID }
    static func migrate(pointer: ManagedPointer, root: URL, interruption: Checkpoint?) throws -> ManagedPointer {
        let journalURL = root.appendingPathComponent("SchemaMigration.json")
        let originalDirectory = root.appendingPathComponent("Generations/\(pointer.generationID.uuidString)")
        let version = try MadarContainerFactory.storeVersion(at:originalDirectory)
        if version == MadarSchema.version {
            // Promotion committed; normal restore recovery finishes app snapshot/history hooks.
            if FileManager.default.fileExists(atPath:journalURL.path) {
                let journal = try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journalURL))
                guard journal.newID == pointer.generationID else { throw BackupOperationError.invalidManagedStore }
                try FileManager.default.removeItem(at:journalURL)
            }
            return pointer
        }
        guard version == 1 else { throw DataError.legacyStoreRequiresAdoption }
        guard FileManager.default.fileExists(atPath:originalDirectory.appendingPathComponent("GenerationReady.json").path) else { throw BackupOperationError.invalidManagedStore }
        let deviceStamp = root.appendingPathComponent("DeviceSchemaVersion.json")
        if FileManager.default.fileExists(atPath:deviceStamp.path) {
            let deviceVersion = try JSONDecoder().decode(Int.self,from:Data(contentsOf:deviceStamp))
            guard (1...MadarSchema.version).contains(deviceVersion) else { throw deviceVersion > MadarSchema.version ? DataError.newerStore : DataError.invalidValue("device store version") }
        }
        let journal: Journal
        if FileManager.default.fileExists(atPath:journalURL.path) {
            journal = try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journalURL))
            guard journal.oldID == pointer.generationID else { throw BackupOperationError.invalidManagedStore }
        } else {
            journal = .init(oldID:pointer.generationID,newID:UUID())
            try DurableFiles.encode(journal,to:journalURL)
        }
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
        let hooks = RestoreJournal(operationID:UUID(),oldGenerationID:journal.oldID,newGenerationID:journal.newID,phase:.ready,hooksPending:true,preserveDeviceRows:true)
        try DurableFiles.encode(hooks,to:root.appendingPathComponent("RestoreJournal.json"))
        try DurableFiles.encode(replacement,to:root.appendingPathComponent("ActiveGeneration.json"))
        if interruption == .afterPointer { throw BackupOperationError.simulatedInterruption("migration afterPointer") }
        try FileManager.default.removeItem(at:journalURL)
        return replacement
    }
}
