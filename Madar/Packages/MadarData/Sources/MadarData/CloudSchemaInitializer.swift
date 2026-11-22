#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Owner, 22 Nov 2026 (iCloud sync live): creates every synced record type in the CloudKit **Development** environment so the
/// schema can then be deployed to Production for TestFlight builds. It works on a throwaway store in a temporary folder and
/// never opens, reads or uploads a real Madar store; Core Data writes one sample record per type and deletes it again.
/// Debug builds only: a release build never contains it.
public enum MadarCloudSchemaInitializer {
    public static func initializeDevelopmentSchema(containerIdentifier: String) throws -> [String] {
        guard containerIdentifier.hasPrefix("iCloud.") else { throw DataError.invalidValue("container") }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: MadarSchema.syncedTypes) else { throw DataError.invalidValue("model") }
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarCloudSchema-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let description = NSPersistentStoreDescription(url: root.appending(path: "Schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "MadarCloudSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try container.initializeCloudKitSchema(options: [])
        for store in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(store) }
        return model.entities.compactMap(\.name).sorted()
    }
}
#endif
