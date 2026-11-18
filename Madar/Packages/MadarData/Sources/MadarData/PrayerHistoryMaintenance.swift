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

    /// Owner 17 Nov 2026 («امسح كل شي خلاص معاد ابيه»): every prayer log and qada row is removed for good.
    /// Rows are tombstoned with a deletion barrier (not erased) so iCloud sync and old backups cannot bring them back.
    /// It runs on every launch: a prayer command queued by an older extension before the update is cleared the next time.
    @discardableResult
    public static func removeAllPrayerRecords(in context: ModelContext, now: Date = .now) throws -> Int {
        try scrubOldTombstoneHearts(in: context, now: now)
        let logs = try context.fetch(FetchDescriptor<PrayerLog>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.mergedInto == nil }
        let debts = try context.fetch(FetchDescriptor<QadaItem>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.mergedInto == nil }
        guard !logs.isEmpty || !debts.isEmpty else { return 0 }
        let writer = "system.prayer-records-removed-v2"
        func tombstone(_ row: some MadarRecordModel) throws {
            var record = try row.record()
            // The tombstone keeps only the natural key; the personal content goes with the record.
            Self.scrubContent(&record)
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
            try context.save()
            return logs.count + debts.count
        } catch {
            context.rollback()
            throw error
        }
    }

    public static let contentScrubKey = "system.migration.prayer-content-scrubbed-v1"

    /// Empties everything personal in a prayer or qada row and keeps only its natural key (`dayKey`+`prayer`, `originalDayKey`+`prayer`) so
    /// sync and old backups still recognise the tombstone. Status becomes the neutral «no record».
    static func scrubContent(_ record: inout DataRecord) {
        switch record.model {
        case "PrayerLog":
            record.fields["status"] = .string("unrecordedHistory")
            for key in ["heart", "loggedAt", "tripID", "pairID", "shortened"] where record.fields[key] != nil { record.fields[key] = .null }
            record.fields["tzID"] = .string(""); record.fields["dayPolicy"] = .string(""); record.fields["source"] = .string("system")
            if let created = record.fields["createdAt"] { record.fields["eventAt"] = created }
        case "QadaItem":
            if record.fields["madeUpAt"] != nil { record.fields["madeUpAt"] = .null }
        default: break
        }
    }

    /// One pass, guarded by a marker: clears the content of every prayer and qada row, including rows deleted by earlier builds, and removes the
    /// frozen «salah» lines from stored diary day snapshots (other lines stay). `updatedAt` and `deletedAt` are untouched, so sync order and the barrier hold.
    static func scrubOldTombstoneHearts(in context: ModelContext, now: Date) throws {
        let settings = try context.fetch(FetchDescriptor<Setting>(predicate: #Predicate { $0.key == "system.migration.prayer-content-scrubbed-v1" }))
        if settings.contains(where: { $0.deletedAt == nil }) { return }
        do {
            for row in try context.fetch(FetchDescriptor<PrayerLog>()) {
                var record = try row.record(); scrubContent(&record); try row.apply(record)
            }
            for row in try context.fetch(FetchDescriptor<QadaItem>()) {
                var record = try row.record(); scrubContent(&record); try row.apply(record)
            }
            for row in try context.fetch(FetchDescriptor<DeviceSetting>()) where row.key.hasPrefix("sys.diaryAutoLines.") {
                guard var lines = (try? JSONSerialization.jsonObject(with: row.valueJSON)) as? [[String: Any]] else { continue }
                let kept = lines.filter { ($0["kind"] as? String) != "salah" }
                guard kept.count != lines.count else { continue }
                lines = kept
                row.valueJSON = try JSONSerialization.data(withJSONObject: lines)
            }
            let marker = Setting()
            marker.id = StableIdentity.uuid(for: contentScrubKey)
            marker.key = contentScrubKey
            marker.valueJSON = Data("true".utf8)
            marker.createdAt = now; marker.updatedAt = now
            marker.writerID = "system.prayer-content-scrub-v1"
            context.insert(marker)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
