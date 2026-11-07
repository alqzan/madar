import Foundation
import SwiftData
import OSLog
import MadarData

private struct CursorEnvelope: Codable {
    let version: Int
    let generationID: UUID
    let tokens: [String: DefaultHistoryToken]
}
public struct HistoryDrainReport: Equatable, Sendable {
    public let transactions: Int
    public let changedModels: Set<String>
    public let reconciledRows: Int
    public let cursorRecovered: Bool
    public init(transactions: Int, changedModels: Set<String>, reconciledRows: Int, cursorRecovered: Bool) { self.transactions = transactions; self.changedModels = changedModels; self.reconciledRows = reconciledRows; self.cursorRecovered = cursorRecovered }
}
/// App process only. Fresh contexts never leave MainActor; persistent tokens are scoped by
/// both Managed generation and physical SwiftData storeIdentifier. History observation alone
/// is not proof that CloudKit imported/exported anything.
@MainActor public final class HistoryProcessor {
    public static let author = "madar.sync.history"
    private let cursorKey: String
    private let signposter = OSSignposter(subsystem: "com.alqzan.madar2", category: "PersistentHistory")
    public init(consumerID: String = "app") { cursorKey = "sys.historyCursor." + consumerID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } }
    public func drain(container: ModelContainer, generationID: UUID, publishSnapshots: (Set<String>) throws -> Void) throws -> HistoryDrainReport {
        let interval = signposter.beginInterval("HistoryDrain"); defer { signposter.endInterval("HistoryDrain", interval) }
        let context = ModelContext(container); context.autosaveEnabled = false; context.author = Self.author
        let cursorRows = try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == cursorKey && $0.deletedAt == nil && $0.mergedInto == nil }
        let cursorRow = cursorRows.max { $0.updatedAt < $1.updatedAt }
        let envelope = cursorRow.flatMap { try? JSONDecoder().decode(CursorEnvelope.self, from: $0.valueJSON) }
        let valid = envelope?.version == 1 && envelope?.generationID == generationID
        let recovered = cursorRow != nil && !valid
        let cursors = valid ? envelope!.tokens : [:]
        let descriptor = HistoryDescriptor<DefaultHistoryTransaction>(sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.transactionIdentifier)])
        let fetched = try context.fetchHistory(descriptor)
        let fresh = fetched.filter { tx in cursors[tx.storeIdentifier].map { tx.token > $0 } ?? true }
        let relevant = fresh.filter { $0.author != Self.author && $0.author != "madar.sync.reconciliation" }
        guard !relevant.isEmpty || recovered else { return .init(transactions: 0, changedModels: [], reconciledRows: 0, cursorRecovered: false) }
        let models = Set(relevant.flatMap { $0.changes.map { $0.changedPersistentIdentifier.entityName } })
        var tokens = cursors
        for transaction in fresh { if tokens[transaction.storeIdentifier].map({ transaction.token > $0 }) ?? true { tokens[transaction.storeIdentifier] = transaction.token } }
        do {
            let mergeContext = ModelContext(container); mergeContext.autosaveEnabled = false; mergeContext.author = "madar.sync.reconciliation"
            // The merge reads synced rows only and is idempotent, so when no synced model changed since the last drain it cannot
            // change anything. Owner 7 Nov 2026 («أول ما أفتح التطبيق يعلق»): a launch after a session that only wrote device rows
            // (the visit record, the notification ledger) re-read and re-merged the whole store on the main thread.
            let needsMerge = recovered || !models.isDisjoint(with: MadarSchema.syncedNames)
            let count = needsMerge ? try RowMerger(context: mergeContext).run() : 0
            // Snapshot failure leaves cursor untouched; replay is safe because merge is idempotent.
            try publishSnapshots(models)
            let row = cursorRow ?? DeviceSetting(); row.key = cursorKey
            if row.modelContext == nil { row.id = StableIdentity.uuid(for: "DeviceSetting:" + cursorKey); context.insert(row) }
            row.valueJSON = try JSONEncoder().encode(CursorEnvelope(version: 1, generationID: generationID, tokens: tokens))
            let now = Date()
            row.writerID = try SettingsStore(context: context).writerIDForWrite(now: now)
            row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
            try context.save()
            return .init(transactions: relevant.count, changedModels: models, reconciledRows: count, cursorRecovered: recovered)
        } catch { context.rollback(); throw error }
    }
    public func reset(container: ModelContainer) throws {
        let context = ModelContext(container); context.author = Self.author; context.autosaveEnabled = false
        let now = Date(), writer = try SettingsStore(context: context).writerIDForWrite(now: Date())
        for row in try context.fetch(FetchDescriptor<DeviceSetting>()) where row.key == cursorKey { row.deletedAt = now; row.deletionBarrierAt = row.deletedAt; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer }
        try context.save()
    }
}
