import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

private struct DiaryInverse: Codable {
    let model: String
    let after: DataRecord
    let dayKey: String
    let previousOrigin: String?
}
@MainActor enum DiaryMutationHandler {
    static func stage(text: String, day: String, targetDay: String?, id: UUID, context: ModelContext, now: Date, writer: String) throws -> Data? {
        let settings = try SettingsStore(context: context), prayer = try PrayerRepository(context: context)
        let place = prayer.place(at: now), civil = GregorianDay.containing(now, in: place.timeZone)
        let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "") ?? .fajr
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: prayer.options) }
        let stored = try MadarDay.resolve(instant: now, place: place, boundary: boundary, prayerDays: days)
        let key = day == "yesterday" ? stored.date.adding(days: -1) : stored.date
        if let targetDay {
            guard let target = try? GregorianDay(targetDay), target < stored.date else { throw DataError.invalidValue("margin target") }
            let rows = try context.fetch(FetchDescriptor<MarginNote>())
            if rows.contains(where: { $0.id == id }) { return nil }
            let row = MarginNote(); row.id = id; row.text = text; row.targetDayKey = targetDay
            row.writtenAt = now; row.writtenDayKey = stored.dayKey; row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"
            row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
            return try JSONEncoder().encode(DiaryInverse(model: "MarginNote", after: row.record(), dayKey: stored.dayKey, previousOrigin: nil))
        }
        let entries = try context.fetch(FetchDescriptor<Entry>())
        if entries.contains(where: { $0.id == id }) { return nil }
        let keyedPages = try context.fetch(FetchDescriptor<DayPage>()).filter { $0.dayKey == key.description && $0.mergedInto == nil }
        guard !keyedPages.contains(where: { $0.deletedAt != nil }) else { throw DataError.invalidValue("explicitRestoreRequired: diary day") }
        let pages = keyedPages.filter { $0.deletedAt == nil }
        let page = pages.max { $0.updatedAt < $1.updatedAt } ?? DayPage()
        let previousOrigin = page.origin
        if pages.isEmpty {
            page.dayKey = key.description; page.createdAt = now; context.insert(page)
        }
        page.origin = "native"; page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
        let row = Entry(); row.id = id; row.dayKey = key.description; row.eventAt = now
        row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"; row.text = text
        row.ink = day == "yesterday" ? "late" : "normal"; row.source = "native"
        row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
        return try JSONEncoder().encode(DiaryInverse(model: "Entry", after: row.record(), dayKey: key.description, previousOrigin: previousOrigin))
    }
    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(DiaryInverse.self, from: data)
        func tombstone<T: MadarRecordModel>(_ row: T) throws {
            guard try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: diary") }
            var record = try row.record(); let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
            try record.set(stamp, for: "deletedAt"); try record.set(stamp, for: "deletionBarrierAt")
            try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID"); try row.apply(record)
        }
        if inverse.model == "Entry" {
            let rows = try context.fetch(FetchDescriptor<Entry>())
            guard let row = rows.first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing diary entry") }
            try tombstone(row)
            if inverse.previousOrigin == "dayOne", !rows.contains(where: { $0.id != row.id && $0.dayKey == inverse.dayKey && $0.source == "native" && $0.deletedAt == nil && $0.mergedInto == nil }) {
                for page in try context.fetch(FetchDescriptor<DayPage>()) where page.dayKey == inverse.dayKey && page.deletedAt == nil && page.mergedInto == nil {
                    page.origin = "dayOne"; page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
                }
            }
        } else {
            guard let row = try context.fetch(FetchDescriptor<MarginNote>()).first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing margin") }
            try tombstone(row)
        }
    }
}
