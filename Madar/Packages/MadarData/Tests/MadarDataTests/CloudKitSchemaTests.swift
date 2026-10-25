import Foundation
import SwiftData
import Testing
@testable import MadarData

/// CloudKit mirroring rules (Apple, "Syncing model data across a person's devices"): every
/// attribute optional or defaulted, no unique attributes or uniqueness constraints, every
/// relationship optional with an inverse and no deny rule. Expected values are those rules,
/// never the generator's output. Nothing here opens a CloudKit container.
@Suite @MainActor struct CloudKitSchemaTests {
    private let synced = Schema(MadarSchema.syncedTypes)
    private let device = Schema(MadarSchema.deviceTypes)

    @Test func everySyncedAttributeIsOptionalOrDefaulted() {
        var missing: [String] = []
        for entity in synced.entities {
            for attribute in entity.attributes where !attribute.isOptional && attribute.defaultValue == nil {
                missing.append("\(entity.name).\(attribute.name)")
            }
        }
        #expect(missing.isEmpty, "attributes without optional/default: \(missing.sorted())")
    }

    @Test func noSyncedEntityDeclaresUniqueness() {
        var unique: [String] = []
        for entity in synced.entities {
            if !entity.uniquenessConstraints.isEmpty { unique.append(entity.name) }
            for attribute in entity.attributes where attribute.options.contains(.unique) { unique.append("\(entity.name).\(attribute.name)") }
        }
        #expect(unique.isEmpty, "unique constraints: \(unique.sorted())")
    }

    @Test func syncedRelationshipsAreOptionalWithInversesAndNeverReachDeviceEntities() {
        let deviceNames = Set(device.entities.map(\.name))
        var bad: [String] = []
        for entity in synced.entities {
            for relationship in entity.relationships {
                let name = "\(entity.name).\(relationship.name)"
                if !relationship.isOptional { bad.append(name + " required") }
                if relationship.inverseName == nil { bad.append(name + " no inverse") }
                if relationship.deleteRule == .deny { bad.append(name + " deny") }
                if deviceNames.contains(relationship.destination) { bad.append(name + " → device") }
            }
        }
        #expect(bad.isEmpty, "relationships: \(bad.sorted())")
    }

    /// CloudKit records are capped at 1 MB; only external storage becomes a CKAsset.
    /// JSON blobs below are bounded small payloads; any raw byte field must be external.
    @Test func rawSyncedBytesUseExternalStorage() {
        var inline: [String] = []
        for entity in synced.entities {
            for attribute in entity.attributes where attribute.valueType == Data.self || attribute.valueType == Optional<Data>.self {
                if !attribute.name.hasSuffix("JSON") && !attribute.options.contains(.externalStorage) { inline.append("\(entity.name).\(attribute.name)") }
            }
        }
        #expect(inline.isEmpty, "inline raw Data: \(inline.sorted())")
    }

    @Test func everySyncedTypeIsInspected() {
        #expect(synced.entities.count == MadarSchema.syncedTypes.count)
    }

    @Test func mirrorOpensOnlyForTheProvisionedContainer() {
        let id = "iCloud.com.alqzan.madar2"
        #expect(MadarCloudMirror.target(pointerIdentifier: nil, provisioned: nil) == .local)
        #expect(MadarCloudMirror.target(pointerIdentifier: id, provisioned: nil) == .local)
        #expect(MadarCloudMirror.target(pointerIdentifier: nil, provisioned: id) == .local)
        #expect(MadarCloudMirror.target(pointerIdentifier: "", provisioned: "") == .local)
        #expect(MadarCloudMirror.target(pointerIdentifier: "iCloud.other", provisioned: id) == .local)
        #expect(MadarCloudMirror.target(pointerIdentifier: id, provisioned: id) == .privateDatabase(id))
    }

    /// An unprovisioned build never opens CloudKit: a pointer carrying a legacy identifier stays
    /// local, keeps its rows, and asking to mirror is refused without touching the pointer.
    @Test func unprovisionedStoreStaysLocalAndRefusesMirror() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarMirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        MadarCloudMirror.provisionedContainerIdentifier = nil
        let store = try ManagedDataStore(root: root, cloudKitContainerIdentifier: "iCloud.com.alqzan.madar2")
        #expect(!store.binding.cloudEnabled)
        let entry = Entry(); entry.dayKey = "2026-10-25"; entry.text = "synthetic"
        store.container.mainContext.insert(entry); try store.container.mainContext.save()
        let pointer = try Data(contentsOf: root.appendingPathComponent("ActiveGeneration.json"))
        #expect(throws: (any Error).self) { try store.bindCloudMirror(enabled: true, accountHash: "a") }
        #expect(try Data(contentsOf: root.appendingPathComponent("ActiveGeneration.json")) == pointer)
        try store.bindCloudMirror(enabled: false, accountHash: nil)
        #expect(!store.binding.cloudEnabled)
        #expect(try store.container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.text) == ["synthetic"])
    }

    @Test func syncedAndDeviceSchemasAreDisjoint() {
        #expect(Set(synced.entities.map(\.name)).isDisjoint(with: device.entities.map(\.name)))
    }
}
