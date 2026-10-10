import Foundation
import SwiftData

public enum MadarContainerFactory {
    public static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(for: MadarSchema.schema, migrationPlan: MadarMigrationPlan.self, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchema.syncedTypes), isStoredInMemoryOnly: true, cloudKitDatabase: .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }
    public static func makeLocal(at directory: URL) throws -> ModelContainer { try build(at: directory, cloudKitIdentifier: nil) }
    @MainActor public static func makeAppGroup(identifier: String, cloudKitContainerIdentifier: String? = nil) throws -> ModelContainer {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { throw DataError.missingAppGroup }
        try preflightVersion(at: directory)
        // Read the device store alone before opening CloudKit. Missing preference = schema default true.
        let device = try ModelContainer(for: Schema(MadarSchema.deviceTypes), configurations: ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), url: directory.appendingPathComponent("Device.store"), cloudKitDatabase: .none))
        let rows = try device.mainContext.fetch(FetchDescriptor<DeviceSetting>())
        let preference = rows.filter { $0.key == "core.iCloudSync" && $0.deletedAt == nil && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }
        let enabled = preference.flatMap { try? JSONDecoder().decode(Bool.self, from: $0.valueJSON) } ?? true
        return try build(at: directory, cloudKitIdentifier: enabled ? cloudKitContainerIdentifier : nil)
    }
    private static func preflightVersion(at directory: URL) throws {
        let stamp = directory.appendingPathComponent("SchemaVersion.json")
        guard FileManager.default.fileExists(atPath:stamp.path) else { return }
        let version = try JSONDecoder().decode(Int.self,from:Data(contentsOf:stamp))
        guard version >= 1 else { throw DataError.invalidValue("store schema version") }
        guard version <= MadarSchema.version else { throw DataError.newerStore }
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
        let container = try ModelContainer(for:MadarSchema.schema,migrationPlan:MadarMigrationPlan.self,configurations:[
            ModelConfiguration("synced",schema:Schema(MadarSchema.syncedTypes),url:syncedDirectory.appendingPathComponent("Madar.store"),cloudKitDatabase:cloudKitContainerIdentifier.map { .private($0) } ?? .none),
            ModelConfiguration("deviceOnly",schema:Schema(MadarSchema.deviceTypes),url:deviceStoreURL,cloudKitDatabase:.none)
        ])
        try DurableFiles.encode(MadarSchema.version,to:syncedDirectory.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(MadarSchema.version,to:deviceStamp)
        return container
    }
    static func makeSyncedStaging(at directory: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        return try ModelContainer(for:Schema(MadarSchema.syncedTypes),configurations:ModelConfiguration("synced",schema:Schema(MadarSchema.syncedTypes),url:directory.appendingPathComponent("Madar.store"),cloudKitDatabase:.none))
    }
    private static func build(at directory: URL, cloudKitIdentifier: String?) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = directory.appendingPathComponent("SchemaVersion.json")
        try preflightVersion(at: directory)
        let container = try ModelContainer(for: MadarSchema.schema, migrationPlan: MadarMigrationPlan.self, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchema.syncedTypes), url: directory.appendingPathComponent("Madar.store"), cloudKitDatabase: cloudKitIdentifier.map { .private($0) } ?? .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchema.deviceTypes), url: directory.appendingPathComponent("Device.store"), cloudKitDatabase: .none)
        ])
        try JSONEncoder().encode(MadarSchema.version).write(to: stamp, options: .atomic)
        return container
    }
}
