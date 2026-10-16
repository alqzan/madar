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
        guard version == MadarSchema.version || (2...4).contains(version) else { throw DataError.legacyStoreRequiresAdoption }
    }
    public static func make(at syncedDirectory: URL, deviceStoreURL: URL, cloudKitContainerIdentifier: String? = nil) throws -> ModelContainer {
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
        let container = try ModelContainer(for:MadarSchema.schema,migrationPlan:migrationPlan,configurations:[
            ModelConfiguration("synced",schema:Schema(MadarSchema.syncedTypes),url:syncedDirectory.appendingPathComponent("Madar.store"),cloudKitDatabase:.none),
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
        let container = try ModelContainer(for: MadarSchema.schema, migrationPlan: MadarMigrationPlan.self, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchema.syncedTypes), url: directory.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), url: directory.appendingPathComponent("Device.store"), cloudKitDatabase: .none)
        ])
        try JSONEncoder().encode(MadarSchema.version).write(to: stamp, options: .atomic)
        return container
    }
}
