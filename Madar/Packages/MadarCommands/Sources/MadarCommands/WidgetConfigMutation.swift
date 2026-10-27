import Foundation
import SwiftData
import MadarCore
import MadarData

/// App-only widget authoring; the extension receives a JSON catalog and never opens this context.
@MainActor enum WidgetConfigMutation {
    static func save(_ id: UUID, name: String, family: String, items: [String], style: WidgetMakerStyle,
                     context: ModelContext, now: Date, writer: String) throws -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(style)
        let existing = try context.fetch(FetchDescriptor<WidgetConfig>()).first { $0.id == id }
        guard existing == nil || (existing?.deletedAt == nil && existing?.mergedInto == nil) else { throw DataError.invalidValue("widget unavailable") }
        let row = existing ?? WidgetConfig()
        let before = try existing?.record()
        row.id = id; row.name = name; row.familyID = family; row.items = items; row.styleJSON = bytes
        if let before, try row.record() == before { return nil }
        row.updatedAt = existing == nil ? now : StableIdentity.monotonic(now: now, previous: row.updatedAt)
        row.writerID = writer
        if existing == nil { row.createdAt = now; context.insert(row) }
        return try JSONEncoder().encode(DiaryInverse(model: "WidgetConfig", after: row.record(), dayKey: "", previousOrigin: nil, before: before))
    }
    static func delete(_ id: UUID, context: ModelContext, now: Date, writer: String) throws -> Data? {
        guard let row = try context.fetch(FetchDescriptor<WidgetConfig>()).first(where: { $0.id == id && $0.mergedInto == nil }) else { throw DataError.invalidValue("widget unavailable") }
        guard row.deletedAt == nil else { return nil }
        let before = try row.record(), stamp = StableIdentity.monotonic(now: now, previous: row.updatedAt)
        row.deletedAt = stamp; row.deletionBarrierAt = stamp; row.updatedAt = stamp; row.writerID = writer
        return try JSONEncoder().encode(DiaryInverse(model: "WidgetConfig", after: row.record(), dayKey: "", previousOrigin: nil, before: before))
    }
}
