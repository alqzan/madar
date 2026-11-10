import Foundation
import SwiftData

public enum MadarContainerFactory {
    public static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(for: MadarSchema.schema, migrationPlan: MadarMigrationPlan.self, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchema.syncedTypes), isStoredInMemoryOnly: true, cloudKitDatabase: .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }
    public static func makeLocal(at directory: URL) throws -> ModelContainer { try build(at: directory) }
    @MainActor public static func makeAppGroup(identifier: String, cloudKitContainerIdentifier: String? = nil) throws -> ModelContainer {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { throw DataError.missingAppGroup }
        // RA1: retain the legacy signature and stored preference, but v1 always opens local files.
        return try build(at: directory)
    }
    public static func storeVersionForAdoption(at directory: URL) throws -> Int { try storeVersion(at:directory) }
    static func storeVersion(at directory: URL) throws -> Int {
        let stamp = directory.appendingPathComponent("SchemaVersion.json")
        guard FileManager.default.fileExists(atPath:stamp.path) else { return FileManager.default.fileExists(atPath:directory.appendingPathComponent("Madar.store").path) ? 1 : MadarSchema.version }
        let version = try JSONDecoder().decode(Int.self,from:Data(contentsOf:stamp))
        guard version >= 1 else { throw DataError.invalidValue("store schema version") }
        guard version <= MadarSchema.version else { throw DataError.newerStore }
        return version
    }
    private static func preflightVersion(at directory: URL) throws {
        let version = try storeVersion(at:directory)
        guard version == MadarSchema.version || (2..<MadarSchema.version).contains(version) else { throw DataError.legacyStoreRequiresAdoption }
    }
    public static func make(at syncedDirectory: URL, deviceStoreURL: URL, cloudKitContainerIdentifier: String? = nil, provisionedContainer: String? = nil) throws -> ModelContainer {
        try FileManager.default.createDirectory(at:syncedDirectory,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:deviceStoreURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try preflightVersion(at:syncedDirectory)
        let deviceStamp = deviceStoreURL.deletingLastPathComponent().appendingPathComponent("DeviceSchemaVersion.json")
        if FileManager.default.fileExists(atPath:deviceStamp.path) {
            let version = try JSONDecoder().decode(Int.self,from:Data(contentsOf:deviceStamp))
            guard version <= MadarSchema.version else { throw DataError.newerStore }
            guard version >= 1 else { throw DataError.invalidValue("device store version") }
        }
        // V2 synced facts need the declared additive migration. A staged current generation
        // can be paired with the unchanged V1 device entities: their original combined
        // metadata is not a version in that plan. Infer only that device metadata upgrade;
        // LegacyGenerationMigration validates it on an expendable clone before promotion.
        let migrationPlan: (any SchemaMigrationPlan.Type)? = try storeVersion(at: syncedDirectory) < MadarSchema.version ? MadarMigrationPlan.self : nil
        let mirror = MadarCloudMirror.target(pointerIdentifier:cloudKitContainerIdentifier,provisioned:provisionedContainer)
        let container = try ModelContainer(for:MadarSchema.schema,migrationPlan:migrationPlan,configurations:[
            ModelConfiguration("synced",schema:Schema(MadarSchema.syncedTypes),url:syncedDirectory.appendingPathComponent("Madar.store"),cloudKitDatabase:mirror.database),
            ModelConfiguration("deviceOnly",schema:Schema(MadarSchema.deviceTypes),url:deviceStoreURL,cloudKitDatabase:.none)
        ])
        try DurableFiles.encode(MadarSchema.version,to:syncedDirectory.appendingPathComponent("SchemaVersion.json"))
        // Device model shape is still V1. Never rewrite an existing device version stamp on rename.
        if !FileManager.default.fileExists(atPath:deviceStamp.path) { try DurableFiles.encode(1,to:deviceStamp) }
        return container
    }
    static func makeSyncedStaging(at directory: URL) throws -> ModelContainer {
        try preflightVersion(at:directory)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let container = try ModelContainer(for:MadarSchema.schema,migrationPlan:MadarMigrationPlan.self,configurations:[
            ModelConfiguration("synced",schema:Schema(MadarSchema.syncedTypes),url:directory.appendingPathComponent("Madar.store"),cloudKitDatabase:.none),
            ModelConfiguration("deviceOnly",schema:Schema(MadarSchema.deviceTypes),isStoredInMemoryOnly:true,cloudKitDatabase:.none)
        ])
        try DurableFiles.encode(MadarSchema.version,to:directory.appendingPathComponent("SchemaVersion.json"))
        return container
    }
    private static func build(at directory: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = directory.appendingPathComponent("SchemaVersion.json")
        try preflightVersion(at: directory)
        try backupBeforeMigration(at: directory)
        let container = try ModelContainer(for: MadarSchema.schema, migrationPlan: MadarMigrationPlan.self, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchema.syncedTypes), url: directory.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), url: directory.appendingPathComponent("Device.store"), cloudKitDatabase: .none)
        ])
        try JSONEncoder().encode(MadarSchema.version).write(to: stamp, options: .atomic)
        return container
    }

    /// B1-14: before SwiftData migrates an older store in place, copy its three files aside. If the migration fails or loses
    /// something, the pre-migration copy is still there. Only the two newest copies are kept.
    public static let preMigrationFolderPrefix = "pre-migration-"
    static func backupBeforeMigration(at directory: URL, now: Date = Date(), keeping: Int = 2) throws {
        let fileManager = FileManager.default
        let store = directory.appendingPathComponent("Madar.store")
        guard fileManager.fileExists(atPath: store.path) else { return }
        let version = try storeVersion(at: directory)
        guard version < MadarSchema.version else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC"); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = directory.appendingPathComponent("\(preMigrationFolderPrefix)\(version)-\(formatter.string(from: now))", isDirectory: true)
        // A copy for this schema and second already exists: never overwrite it.
        guard !fileManager.fileExists(atPath: folder.path) else { return }
        let staging = directory.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = directory.appendingPathComponent("Madar.store" + suffix)
                if fileManager.fileExists(atPath: source.path) { try fileManager.copyItem(at: source, to: staging.appendingPathComponent("Madar.store" + suffix)) }
            }
            try fileManager.moveItem(at: staging, to: folder)
        } catch { try? fileManager.removeItem(at: staging); throw error }
        let copies = try preMigrationBackups(in: directory)
        for old in copies.dropFirst(keeping) { try? fileManager.removeItem(at: old) }
    }
    /// Newest first.
    public static func preMigrationBackups(in directory: URL) throws -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        // The name ends with a sortable UTC stamp, so the stamp orders copies even across schema versions.
        return names.filter { $0.hasPrefix(preMigrationFolderPrefix) }
            .sorted { $0.split(separator: "-").suffix(2).joined() > $1.split(separator: "-").suffix(2).joined() }
            .map { directory.appendingPathComponent($0, isDirectory: true) }
    }
}
