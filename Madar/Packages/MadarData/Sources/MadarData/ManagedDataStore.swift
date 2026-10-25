import Foundation
import SwiftData
import Darwin

struct ManagedPointer: Codable {
    let version: Int; let generationID: UUID; let previousGenerationID: UUID?; let accountHash: String?; let cloudKitContainerIdentifier: String?
}
struct RestoreJournal: Codable {
    enum Phase: String, Codable { case preparing, ready, promoted }
    let operationID: UUID; let oldGenerationID: UUID; let newGenerationID: UUID; var phase: Phase; var hooksPending: Bool
    var preserveDeviceRows: Bool? = nil
}
struct GenerationReady: Codable { let version: Int; let generationID: UUID; let recordsHash: String; let createdAt: Date }

@MainActor public final class ManagedDataStore {
    public let root: URL; public let commandLockURL: URL
    public private(set) var container: ModelContainer
    public private(set) var binding: ManagedStoreBinding
    public private(set) var isBusy = false
    /// The container this signed build may mirror to (nil: local only). Fixed for the store's life.
    public let provisionedContainer: String?
    /// The active pointer names this build's container: the person turned sync on for this generation. The store
    /// still opens on the device first; the mirror attaches only after the iCloud account is confirmed the same
    /// (`bindCloudMirror`), because CloudKit mirroring opened under a changed account can purge local rows.
    public private(set) var mirrorBound = false
    public var isCloudBacked: Bool { binding.cloudEnabled }
    public var recoveryRequiresRefresh: Bool { journal()?.hooksPending ?? false }
    var pointerURL: URL { root.appendingPathComponent("ActiveGeneration.json") }
    var journalURL: URL { root.appendingPathComponent("RestoreJournal.json") }
    public convenience init(root: URL, commandLockURL: URL? = nil, cloudKitContainerIdentifier: String? = nil, accountHash: String? = nil) throws {
        try self.init(root:root,commandLockURL:commandLockURL,cloudKitContainerIdentifier:cloudKitContainerIdentifier,accountHash:accountHash,migrationInterruption:nil)
    }
    init(root: URL, commandLockURL: URL? = nil, cloudKitContainerIdentifier: String? = nil, accountHash: String? = nil, migrationInterruption: LegacyGenerationMigration.Checkpoint?) throws {
        self.root = root; self.commandLockURL = commandLockURL ?? root.appendingPathComponent("CommandBus.lock")
        provisionedContainer = MadarCloudMirror.provisionedContainerIdentifier
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let lease = StoreLease(lockURL:self.commandLockURL); try lease.acquire(failIfMaintenance:false); defer { lease.release() }
        let pointerURL = root.appendingPathComponent("ActiveGeneration.json")
        var pointer: ManagedPointer
        if FileManager.default.fileExists(atPath:pointerURL.path) { pointer = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:pointerURL)); guard pointer.version == 1 else { throw BackupOperationError.invalidManagedStore } }
        else {
            let bootstrapURL = root.appendingPathComponent("InitializationJournal.json")
            if FileManager.default.fileExists(atPath:bootstrapURL.path) {
                pointer = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:bootstrapURL))
                guard pointer.version == 1 else { throw BackupOperationError.invalidManagedStore }
            } else {
                guard !FileManager.default.fileExists(atPath:root.appendingPathComponent("Madar.store").path) && !FileManager.default.fileExists(atPath:root.appendingPathComponent("Device.store").path) else { throw BackupOperationError.adoptionRequiresEmptyRoot }
                pointer = ManagedPointer(version:1,generationID:UUID(),previousGenerationID:nil,accountHash:accountHash,cloudKitContainerIdentifier:cloudKitContainerIdentifier)
                try lease.beginMaintenance(operationID:UUID()); try DurableFiles.encode(pointer,to:bootstrapURL)
            }
            let id = pointer.generationID; let directory = root.appendingPathComponent("Generations/\(id.uuidString)",isDirectory:true)
            let empty = try MadarContainerFactory.make(at:directory,deviceStoreURL:root.appendingPathComponent("Device.store"),cloudKitContainerIdentifier:pointer.cloudKitContainerIdentifier)
            empty.mainContext.autosaveEnabled = false
            // A retried bootstrap may reopen only its own empty stores; arbitrary user stores never get adopted here.
            guard try RecordBridge.all(empty.mainContext,syncedOnly:false).isEmpty else { throw BackupOperationError.invalidManagedStore }
            try DurableFiles.encode(GenerationReady(version:1,generationID:id,recordsHash:try RecordFingerprint.hash([]),createdAt:Date()),to:directory.appendingPathComponent("GenerationReady.json"))
            try DurableFiles.encode(pointer,to:pointerURL); try FileManager.default.removeItem(at:bootstrapURL)
        }
        pointer = try LegacyGenerationMigration.migrate(pointer:pointer,root:root,interruption:migrationInterruption)
        let directory = root.appendingPathComponent("Generations/\(pointer.generationID.uuidString)",isDirectory:true)
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("GenerationReady.json").path) else { throw BackupOperationError.invalidManagedStore }
        // Always opens on the device; a bound pointer is remembered and re-attached after the account check.
        mirrorBound = MadarCloudMirror.target(pointerIdentifier:pointer.cloudKitContainerIdentifier,provisioned:provisionedContainer) != .local
        binding = .init(generationID:pointer.generationID,syncedDirectory:directory,deviceStoreURL:root.appendingPathComponent("Device.store"),accountHash:pointer.accountHash,cloudEnabled:false)
        container = try MadarContainerFactory.make(at:directory,deviceStoreURL:binding.deviceStoreURL); container.mainContext.autosaveEnabled = false
        try recoverInterruptedOperation(pointer:pointer)
        try lease.endMaintenance()
    }
    public static func adopt(from source: ModelContainer, at root: URL, commandLockURL: URL? = nil) throws -> ManagedDataStore {
        try adoptForTesting(from:source,at:root,commandLockURL:commandLockURL,interruption:nil)
    }
    enum AdoptionCheckpoint: String { case afterCopy, afterPromotion }
    private struct AdoptionJournal: Codable { let stagingName: String; let targetName: String }
    static func adoptForTesting(from source: ModelContainer, at root: URL, commandLockURL: URL? = nil, interruption: AdoptionCheckpoint?) throws -> ManagedDataStore {
        try adoptRecords(at:root,commandLockURL:commandLockURL,interruption:interruption) { try RecordBridge.all(source.mainContext,syncedOnly:false) }
    }
    /// Converts an explicitly chosen legacy flat store from a read-only clone; never opens its source.
    public static func adoptLegacy(from directory: URL, at root: URL, commandLockURL: URL? = nil) throws -> ManagedDataStore {
        // Fail closed before adoption writes a target, journal or replacement schema stamp.
        guard try MadarContainerFactory.storeVersion(at:directory) == 1 else { throw DataError.invalidValue("legacy adoption source") }
        try SchemaCompatibility.validateDeviceVersion(at: directory)
        return try adoptRecords(at:root,commandLockURL:commandLockURL,interruption:nil) {
            try SchemaCompatibility.validateDeviceVersion(at: directory)
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("MadarLegacyAdoption-\(UUID())")
            defer { try? FileManager.default.removeItem(at:copy) }
            let original = try LegacyV1Reader.read(syncedDirectory:directory,deviceStoreURL:directory.appendingPathComponent("Device.store"),copiedTo:copy)
            return try SchemaCompatibility.currentRecords(original,from:1)
        }
    }
    private static func adoptRecords(at root: URL, commandLockURL: URL?, interruption: AdoptionCheckpoint?, records readRecords: () throws -> [DataRecord]) throws -> ManagedDataStore {
        let lockURL = commandLockURL ?? root.appendingPathComponent("CommandBus.lock")
        // Place the shared default lock beside the target so acquiring it never creates the target directory prematurely.
        let effectiveLockURL = commandLockURL == nil ? root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent)-Adoption.lock") : lockURL
        let lease = StoreLease(lockURL:effectiveLockURL); try lease.acquire(failIfMaintenance:false)
        let journalURL = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent)-AdoptionJournal.json")
        var preserveRecovery = false
        defer { if !preserveRecovery { try? lease.endMaintenance() }; lease.release() }
        if FileManager.default.fileExists(atPath:journalURL.path) {
            let journal = try JSONDecoder().decode(AdoptionJournal.self,from:Data(contentsOf:journalURL))
            guard journal.targetName == root.lastPathComponent, journal.stagingName.hasPrefix(".\(root.lastPathComponent)-Adopting-"), !journal.stagingName.contains("/") else { throw BackupOperationError.invalidManagedStore }
            let previousStaging = root.deletingLastPathComponent().appendingPathComponent(journal.stagingName)
            if FileManager.default.fileExists(atPath:root.appendingPathComponent("ActiveGeneration.json").path) {
                try FileManager.default.removeItem(at:journalURL); try lease.endMaintenance(); lease.release()
                return try ManagedDataStore(root:root,commandLockURL:commandLockURL)
            }
            if FileManager.default.fileExists(atPath:previousStaging.path) { try FileManager.default.removeItem(at:previousStaging) }
            try FileManager.default.removeItem(at:journalURL)
        }
        if FileManager.default.fileExists(atPath:root.path) {
            guard try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty else { throw BackupOperationError.adoptionRequiresEmptyRoot }
            try FileManager.default.removeItem(at:root)
        }
        try lease.beginMaintenance(operationID:UUID())
        let staging = root.deletingLastPathComponent().appendingPathComponent(".\(root.lastPathComponent)-Adopting-\(UUID())",isDirectory:true)
        try DurableFiles.encode(AdoptionJournal(stagingName:staging.lastPathComponent,targetName:root.lastPathComponent),to:journalURL)
        do {
            // Source is scanned while the same cross-process write lease is held. It is never saved or mutated.
            let records = try readRecords()
            func prepare() throws {
                let temporary = try ManagedDataStore(root:staging,commandLockURL:staging.appendingPathComponent("AdoptionPreparation.lock"))
                for row in records { try RecordBridge.insert(row,in:temporary.container.mainContext) }
                try temporary.container.mainContext.save()
                let copied = try RecordBridge.all(temporary.container.mainContext,syncedOnly:false)
                guard copied.count == records.count, Set(copied) == Set(records) else { throw BackupOperationError.invalidManagedStore }
                let synced = copied.filter { MadarSchema.syncedNames.contains($0.model) }
                try DurableFiles.encode(GenerationReady(version:1,generationID:temporary.binding.generationID,recordsHash:try RecordFingerprint.hash(synced),createdAt:Date()),to:temporary.binding.syncedDirectory.appendingPathComponent("GenerationReady.json"))
            }
            try prepare() // closes staging containers before the directory is atomically moved.
            if interruption == .afterCopy { preserveRecovery = true; throw BackupOperationError.simulatedInterruption("adoption afterCopy") }
            guard rename(staging.path,root.path) == 0 else { throw BackupOperationError.invalidManagedStore }
            let fd = open(root.deletingLastPathComponent().path,O_RDONLY); if fd >= 0 { _ = fsync(fd); close(fd) }
            if interruption == .afterPromotion { preserveRecovery = true; throw BackupOperationError.simulatedInterruption("adoption afterPromotion") }
            try FileManager.default.removeItem(at:journalURL); try lease.endMaintenance(); lease.release()
            return try ManagedDataStore(root:root,commandLockURL:commandLockURL)
        } catch {
            if !preserveRecovery { if FileManager.default.fileExists(atPath:staging.path) { try? FileManager.default.removeItem(at:staging) }; try? FileManager.default.removeItem(at:journalURL) }
            throw error
        }
    }
    public func refreshIfNeeded() throws {
        let pointer = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:pointerURL)); guard pointer.version == 1 else { throw BackupOperationError.invalidManagedStore }
        guard pointer.generationID != binding.generationID else { return }
        let directory = generationDirectory(pointer.generationID)
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("GenerationReady.json").path) else { throw BackupOperationError.invalidManagedStore }
        let replacement = try MadarContainerFactory.make(at:directory,deviceStoreURL:binding.deviceStoreURL); replacement.mainContext.autosaveEnabled = false
        mirrorBound = MadarCloudMirror.target(pointerIdentifier:pointer.cloudKitContainerIdentifier,provisioned:provisionedContainer) != .local
        container = replacement; binding = .init(generationID:pointer.generationID,syncedDirectory:directory,deviceStoreURL:binding.deviceStoreURL,accountHash:pointer.accountHash,cloudEnabled:false)
    }
    public func containerForTransaction() throws -> ModelContainer { try refreshIfNeeded(); return container }
    func generationDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Generations/\(id.uuidString)",isDirectory:true) }
    func journal() -> RestoreJournal? { try? JSONDecoder().decode(RestoreJournal.self,from:Data(contentsOf:journalURL)) }
    func setBusy(_ value: Bool) { isBusy = value }
    func promote(_ id: UUID) throws { try promote(id,accountHash:binding.accountHash) }
    func promote(_ id: UUID,accountHash: String?) throws {
        guard !isCloudBacked else { throw BackupOperationError.cloudRestoreUnsupported }
        let ready = generationDirectory(id).appendingPathComponent("GenerationReady.json")
        guard FileManager.default.fileExists(atPath:ready.path) else { throw BackupOperationError.invalidManagedStore }
        let pointer = ManagedPointer(version:1,generationID:id,previousGenerationID:binding.generationID,accountHash:accountHash,cloudKitContainerIdentifier:nil)
        // Open/validate the replacement before committing the single active pointer; Device.store remains fixed.
        let replacement = try MadarContainerFactory.make(at:generationDirectory(id),deviceStoreURL:binding.deviceStoreURL); replacement.mainContext.autosaveEnabled = false
        try DurableFiles.encode(pointer,to:pointerURL)
        container = replacement; binding = .init(generationID:id,syncedDirectory:generationDirectory(id),deviceStoreURL:binding.deviceStoreURL,accountHash:pointer.accountHash,cloudEnabled:false)
    }
    /// Turns the private-database mirror on or off for the active generation without copying or
    /// rotating it: the same Madar.store gains or loses its CloudKit configuration. Callers hold
    /// CommandBus.lock with writers paused and a verified backup checkpoint.
    public func bindCloudMirror(enabled: Bool, accountHash: String?) throws {
        guard !isBusy, journal() == nil else { throw BackupOperationError.invalidManagedStore }
        let current = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:pointerURL))
        guard current.version == 1, current.generationID == binding.generationID else { throw BackupOperationError.invalidManagedStore }
        let identifier = enabled ? provisionedContainer : nil
        if enabled && identifier == nil { throw BackupOperationError.cloudRestoreUnsupported }
        let pointer = ManagedPointer(version:1,generationID:current.generationID,previousGenerationID:current.previousGenerationID,accountHash:accountHash,cloudKitContainerIdentifier:identifier)
        let directory = generationDirectory(pointer.generationID)
        // The old container stays active until the replacement opens and the pointer is durable; a failure
        // leaves both exactly as they were. The caller hands the new container to every holder (bindContainer).
        let replacement = try MadarContainerFactory.make(at:directory,deviceStoreURL:binding.deviceStoreURL,cloudKitContainerIdentifier:identifier,provisionedContainer:provisionedContainer)
        replacement.mainContext.autosaveEnabled = false
        try DurableFiles.encode(pointer,to:pointerURL)
        container = replacement; mirrorBound = identifier != nil
        binding = .init(generationID:pointer.generationID,syncedDirectory:directory,deviceStoreURL:binding.deviceStoreURL,accountHash:accountHash,cloudEnabled:identifier != nil)
    }
    private func recoverInterruptedOperation(pointer: ManagedPointer) throws {
        guard FileManager.default.fileExists(atPath:journalURL.path) else { return }
        var journal = try JSONDecoder().decode(RestoreJournal.self,from:Data(contentsOf:journalURL))
        if pointer.generationID == journal.newGenerationID {
            journal.phase = .promoted; journal.hooksPending = true; try DurableFiles.encode(journal,to:journalURL)
        } else if pointer.generationID == journal.oldGenerationID {
            let staging = generationDirectory(journal.newGenerationID)
            if FileManager.default.fileExists(atPath:staging.path) { try FileManager.default.removeItem(at:staging) }
            try FileManager.default.removeItem(at:journalURL)
        } else { throw BackupOperationError.invalidManagedStore }
    }
}
