import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct LocalStoreTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarLocalOnlyTests-\(UUID())")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    private func expectLocal(_ container: ModelContainer) {
        #expect(!container.configurations.isEmpty)
        for configuration in container.configurations {
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
    }
    @Test func test_M0S1_RA1_allFactoryPathsAreLocalWithLegacyCloudPreference() throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        expectLocal(try MadarContainerFactory.makeInMemory())
        expectLocal(try MadarContainerFactory.makeLocal(at:base.appendingPathComponent("Flat")))
        expectLocal(try MadarContainerFactory.makeSyncedStaging(at:base.appendingPathComponent("Staging")))
        let directory = base.appendingPathComponent("Generation"), deviceURL = base.appendingPathComponent("Device.store")
        // This legacy ID is metadata. Opening a local v1 store must not require entitlements or a CloudKit account.
        let legacyID = "iCloud.example.Madar.Legacy"
        func writePreference(_ enabled: Bool) throws {
            let local = try MadarContainerFactory.make(at:directory,deviceStoreURL:deviceURL)
            let setting = DeviceSetting(); setting.key = "core.iCloudSync"; setting.valueJSON = try JSONEncoder().encode(enabled)
            local.mainContext.insert(setting); try local.mainContext.save()
        }
        // Missing preference, then true, then false must all open the same local files.
        expectLocal(try MadarContainerFactory.make(at:directory,deviceStoreURL:deviceURL,cloudKitContainerIdentifier:legacyID))
        try writePreference(true)
        let withTrue = try MadarContainerFactory.make(at:directory,deviceStoreURL:deviceURL,cloudKitContainerIdentifier:legacyID)
        expectLocal(withTrue)
        #expect(try withTrue.mainContext.fetch(FetchDescriptor<DeviceSetting>()).first?.valueJSON == JSONEncoder().encode(true))
        try writePreference(false)
        expectLocal(try MadarContainerFactory.make(at:directory,deviceStoreURL:deviceURL,cloudKitContainerIdentifier:legacyID))
    }
    @Test func test_M0S1_RA1_legacyPointerReopensWithoutCloudAndPreservesMetadata() throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at:base) }
        let root = base.appendingPathComponent("Managed"), legacyID = "iCloud.example.Madar.Legacy"
        let initial = try ManagedDataStore(root:root,cloudKitContainerIdentifier:legacyID,accountHash:"legacy-account")
        expectLocal(initial.container); #expect(!initial.isCloudBacked && !initial.binding.cloudEnabled)
        let entry = Entry(); entry.text = "بيانات محلية محفوظة"; initial.container.mainContext.insert(entry)
        let preference = DeviceSetting(); preference.key = "core.iCloudSync"; preference.valueJSON = try JSONEncoder().encode(true)
        initial.container.mainContext.insert(preference); try initial.container.mainContext.save()
        let fingerprint = try RecordFingerprint.hash(RecordBridge.all(initial.container.mainContext,syncedOnly:false))
        let pointerBytes = try Data(contentsOf:initial.pointerURL)
        let reopened = try ManagedDataStore(root:root)
        expectLocal(reopened.container); #expect(!reopened.isCloudBacked && !reopened.binding.cloudEnabled)
        #expect(reopened.binding.generationID == initial.binding.generationID)
        #expect(reopened.binding.accountHash == "legacy-account")
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == fingerprint)
        #expect(try Data(contentsOf:initial.pointerURL) == pointerBytes)
        let pointer = try JSONDecoder().decode(ManagedPointer.self,from:pointerBytes)
        #expect(pointer.cloudKitContainerIdentifier == legacyID)
        // Simulate a legacy active-generation switch and exercise refresh as well as initial reopen.
        let next = UUID(), nextDirectory = reopened.generationDirectory(next)
        let staging = try MadarContainerFactory.makeSyncedStaging(at:nextDirectory)
        let replacementEntry = Entry(); replacementEntry.text = "جيل محلي آخر"; staging.mainContext.insert(replacementEntry); try staging.mainContext.save()
        try DurableFiles.encode(GenerationReady(version:1,generationID:next,recordsHash:try RecordFingerprint.hash(RecordBridge.all(staging.mainContext)),createdAt:Date()),to:nextDirectory.appendingPathComponent("GenerationReady.json"))
        let nextPointer = ManagedPointer(version:1,generationID:next,previousGenerationID:pointer.generationID,accountHash:pointer.accountHash,cloudKitContainerIdentifier:legacyID)
        try DurableFiles.encode(nextPointer,to:reopened.pointerURL)
        try reopened.refreshIfNeeded()
        expectLocal(reopened.container); #expect(!reopened.isCloudBacked && !reopened.binding.cloudEnabled)
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<Entry>()).first?.text == "جيل محلي آخر")
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<DeviceSetting>()).first?.valueJSON == JSONEncoder().encode(true))
    }
}
