import Foundation
import SwiftData

/// V1 is read only, from a caller-selected copy. Never opens or stamps the source files.
@MainActor enum LegacyV1Reader {
    static func read(syncedDirectory: URL, deviceStoreURL: URL?, copiedTo copy: URL) throws -> [DataRecord] {
        try FileManager.default.copyItem(at:syncedDirectory,to:copy)
        if let deviceStoreURL, deviceStoreURL.standardizedFileURL != syncedDirectory.appendingPathComponent("Device.store").standardizedFileURL {
            for source in try FileManager.default.contentsOfDirectory(at:deviceStoreURL.deletingLastPathComponent(),includingPropertiesForKeys:nil) where source.lastPathComponent.hasPrefix(deviceStoreURL.lastPathComponent) {
                try FileManager.default.copyItem(at:source,to:copy.appendingPathComponent(source.lastPathComponent))
            }
        }
        // Retain the raw copy byte-for-byte. SDK metadata/SHM writes, if any, affect only this read clone.
        let readCopy = FileManager.default.temporaryDirectory.appendingPathComponent("MadarLegacyRead-\(UUID())")
        try FileManager.default.copyItem(at:copy,to:readCopy)
        defer { try? FileManager.default.removeItem(at:readCopy) }
        let deviceCopy = readCopy.appendingPathComponent("Device.store")
        var configurations = [ModelConfiguration("synced",schema:Schema(MadarSchemaV1.syncedTypes),url:readCopy.appendingPathComponent("Madar.store"),allowsSave:false,cloudKitDatabase:.none)]
        if deviceStoreURL != nil { configurations.append(ModelConfiguration("deviceOnly",schema:Schema(MadarSchemaV1.deviceTypes),url:deviceCopy,allowsSave:false,cloudKitDatabase:.none)) }
        let schema = deviceStoreURL == nil ? Schema(MadarSchemaV1.syncedTypes) : Schema(versionedSchema:MadarSchemaV1.self)
        let container = try ModelContainer(for:schema,configurations:configurations)
        container.mainContext.autosaveEnabled = false
        return try LegacyRecordBridge.all(container.mainContext,syncedOnly:deviceStoreURL == nil)
    }
}
