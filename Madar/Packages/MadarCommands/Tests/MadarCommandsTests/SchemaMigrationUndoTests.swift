import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
@testable import MadarCommands

private struct LegacyUndoEnvelope: Codable {
    let settings: [String: MadarData.JSONValue]
    let afterSettings: [String: MadarData.JSONValue]
    let layouts: [String: Data?]
    let afterLayouts: [String: Data]
    let prayerBefore: DataRecord?
    let prayerAfter: DataRecord?
}

private struct SyntheticPointer: Codable {
    let version: Int
    let generationID: UUID
    let previousGenerationID: UUID?
    let accountHash: String?
    let cloudKitContainerIdentifier: String?
}

private struct SyntheticGenerationReady: Codable {
    let version: Int
    let generationID: UUID
    let recordsHash: String
    let createdAt: Date
}

private struct LegacyReceiptScope: Codable {
    let version: Int
    let generationID: UUID
}

@Suite(.serialized) @MainActor struct SchemaMigrationUndoTests {
    @Test func appliedV2PrayerUndoSurvivesAdditiveMigration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV2UndoMigration-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(uuidString: "00000000-0000-0000-0000-000000000713")!
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-000000000723")!
        let receiptID = UUID(uuidString: "00000000-0000-0000-0000-000000000733")!
        let eventAt = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00+03:00")!
        let generation = root.appendingPathComponent("Generations/\(oldID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let after = try legacyPrayerRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000743")!, at: eventAt)

        let oldContainer = try ModelContainer(for: MadarSchemaV2.schema, configurations: [
            ModelConfiguration("synced", schema: Schema(MadarSchemaV2.syncedTypes),
                url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
            ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV2.deviceTypes),
                url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)
        ])
        oldContainer.mainContext.autosaveEnabled = false
        let oldPrayer = MadarSchemaV2.PrayerLog()
        oldPrayer.id = try after.decode("id", as: UUID.self)
        oldPrayer.createdAt = eventAt; oldPrayer.updatedAt = eventAt; oldPrayer.writerID = "synthetic-device"
        oldPrayer.dayKey = "2026-10-09"; oldPrayer.prayer = "dhuhr"; oldPrayer.status = "jamaah"
        oldPrayer.eventAt = eventAt; oldPrayer.tzID = "Asia/Riyadh"; oldPrayer.dayPolicy = "prayerDay@1"
        oldPrayer.loggedAt = eventAt; oldPrayer.source = "app"
        oldContainer.mainContext.insert(oldPrayer)

        let inverse = LegacyUndoEnvelope(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:],
            prayerBefore: nil, prayerAfter: after)
        let receipt = CommandReceipt()
        receipt.id = receiptID; receipt.commandID = commandID; receipt.name = "prayer.log"
        receipt.payloadHash = "synthetic-v2-prayer"; receipt.source = "app"; receipt.issuedAt = eventAt
        receipt.createdAt = eventAt; receipt.updatedAt = eventAt; receipt.status = "applied"
        receipt.undoJSON = try JSONEncoder().encode(inverse)
        receipt.expiresAt = eventAt.addingTimeInterval(86400); receipt.undoExpiresAt = eventAt.addingTimeInterval(600)
        oldContainer.mainContext.insert(receipt)
        let scope = DeviceSetting()
        scope.id = UUID(uuidString: "00000000-0000-0000-0000-000000000753")!
        scope.key = "sys.commandReceiptScope:\(receiptID.uuidString)"
        scope.valueJSON = try JSONEncoder().encode(LegacyReceiptScope(version: 1, generationID: oldID))
        oldContainer.mainContext.insert(scope)
        try oldContainer.mainContext.save()

        try writeJSON(2, to: generation.appendingPathComponent("SchemaVersion.json"))
        try writeJSON(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try writeJSON(SyntheticGenerationReady(version: 1, generationID: oldID,
            recordsHash: "synthetic-v2", createdAt: eventAt),
            to: generation.appendingPathComponent("GenerationReady.json"))
        try writeJSON(SyntheticPointer(version: 1, generationID: oldID, previousGenerationID: nil,
            accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))

        let migrated = try ManagedDataStore(root: root)
        #expect(migrated.binding.generationID != oldID)
        let currentScope = try #require(migrated.container.mainContext.fetch(FetchDescriptor<DeviceSetting>())
            .first(where: { $0.key == "sys.commandReceiptScope:\(receiptID.uuidString)" }))
        let migratedScope = try JSONDecoder().decode(LegacyReceiptScope.self, from: currentScope.valueJSON)
        #expect(migratedScope.generationID == migrated.binding.generationID)

        let bus = CommandBus(adapter: DurableCommandAdapter(containerProvider: { try migrated.containerForTransaction() },
            lockDirectory: root, transactionClock: { $0 }, generationProvider: { migrated.binding.generationID }))
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(commandID.uuidString)]), issuedAt: eventAt)
        #expect(try await bus.execute(undo, now: eventAt.addingTimeInterval(1)).status == .applied)
        let restored = try #require(migrated.container.mainContext.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(restored.deletedAt != nil && restored.deletionBarrierAt != nil)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func legacyPrayerRecord(id: UUID, at date: Date) throws -> DataRecord {
        try DataRecord(model: "PrayerLog", fields: [
            "id": JSONValue.encode(id), "createdAt": JSONValue.encode(date), "updatedAt": JSONValue.encode(date),
            "deletedAt": JSONValue.encode(Date?.none), "writerID": JSONValue.encode("synthetic-device"),
            "mergedInto": JSONValue.encode(UUID?.none), "deletionBarrierAt": JSONValue.encode(Date?.none),
            "restoredAt": JSONValue.encode(Date?.none), "dayKey": JSONValue.encode("2026-10-09"),
            "prayer": JSONValue.encode("dhuhr"), "status": JSONValue.encode("jamaah"),
            "heart": JSONValue.encode(String?.none), "eventAt": JSONValue.encode(date),
            "tzID": JSONValue.encode("Asia/Riyadh"), "dayPolicy": JSONValue.encode("prayerDay@1"),
            "loggedAt": JSONValue.encode(Date?.some(date)), "source": JSONValue.encode("app"),
            "tripID": JSONValue.encode(UUID?.none), "pairID": JSONValue.encode(UUID?.none),
            "shortened": JSONValue.encode(Bool?.none)
        ])
    }
}
