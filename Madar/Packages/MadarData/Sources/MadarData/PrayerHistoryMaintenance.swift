import Foundation
import SwiftData

/// One-time, owner-authorized removal of old backlog and unperformed-prayer records.
/// Historical qada rows are included in this cleanup; future qada records only after performance.
/// The schema stays intact so old backups and tombstones remain readable.
@MainActor public enum PrayerHistoryMaintenance {
    public static let cleanupKey = "system.migration.unperformed-prayer-records-removed-v1"

    /// Tombstones old missed, qada, unrecorded-history, and excused logs plus all debt rows. The migration marker
    /// is committed in the same ModelContext save, so an interrupted save cannot leave a
    /// marker that hides records which were not cleaned.
    @discardableResult
    public static func removeUnperformedPrayerHistory(in context: ModelContext, now: Date = .now) throws -> Int {
        let settings = try context.fetch(FetchDescriptor<Setting>())
        if settings.contains(where: { $0.key == cleanupKey && $0.deletedAt == nil && $0.mergedInto == nil }) { return 0 }

        let logs = try context.fetch(FetchDescriptor<PrayerLog>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil && ["missed", "qada", "unrecordedHistory", "excused"].contains($0.status) }
        let debts = try context.fetch(FetchDescriptor<QadaItem>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let legacyReminderSettings = settings.filter { $0.key == "salah.qadaReminder" && $0.deletedAt == nil && $0.mergedInto == nil }
        let writer = "system.unperformed-prayer-removal-v1"

        func tombstone(_ row: some MadarRecordModel) throws {
            var record = try row.record()
            let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast)
            try record.set(stamp, for: "updatedAt")
            try record.set(stamp, for: "deletedAt")
            try record.set(stamp, for: "deletionBarrierAt")
            try record.set(writer, for: "writerID")
            try row.apply(record)
        }

        do {
            for row in logs { try tombstone(row) }
            for row in debts { try tombstone(row) }
            for row in legacyReminderSettings { try tombstone(row) }

            let marker = Setting()
            marker.id = StableIdentity.uuid(for: cleanupKey)
            marker.key = cleanupKey
            marker.valueJSON = Data("true".utf8)
            marker.createdAt = now
            marker.updatedAt = now
            marker.writerID = writer
            context.insert(marker)
            try context.save()
            return logs.count + debts.count + legacyReminderSettings.count
        } catch {
            context.rollback()
            throw error
        }
    }
}
