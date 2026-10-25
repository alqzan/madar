import Foundation
import SwiftData
import MadarCore
import MadarData

/// §7.1 B03: a user «يوم يهمّك» stores its rule only. Saves and deletes carry an inverse for undo; deletes are tombstones.
@MainActor enum BahwUpcomingHandler {
    static func save(_ id: UUID, title: String, calendar: String, year: Int?, month: Int, day: Int, repeats: String, countFrom: String, countUpAfter: Bool = false, context: ModelContext, now: Date, writer: String) throws -> Data? {
        func apply(_ row: UpcomingDay) { row.title = title; row.calendar = calendar; row.year = year; row.month = month; row.day = day; row.repeats = repeats; row.countFromDayKey = countFrom; row.countUpAfter = countUpAfter }
        if let row = try context.fetch(FetchDescriptor<UpcomingDay>()).first(where: { $0.id == id }) {
            guard row.deletedAt == nil, row.mergedInto == nil else { throw DataError.invalidValue("missing upcoming day") }
            let before = try row.record()
            apply(row)
            guard try row.record() != before else { return nil }
            row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            return try JSONEncoder().encode(DiaryInverse(model: "UpcomingDay", after: row.record(), dayKey: "", previousOrigin: nil, before: before))
        }
        let row = UpcomingDay(); row.id = id; apply(row); row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
        return try JSONEncoder().encode(DiaryInverse(model: "UpcomingDay", after: row.record(), dayKey: "", previousOrigin: nil))
    }
    static func delete(_ id: UUID, context: ModelContext, now: Date, writer: String) throws -> Data? {
        guard let row = try context.fetch(FetchDescriptor<UpcomingDay>()).first(where: { $0.id == id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing upcoming day") }
        guard row.deletedAt == nil else { return nil }
        let before = try row.record(), stamp = StableIdentity.monotonic(now: now, previous: row.updatedAt)
        row.deletedAt = stamp; row.deletionBarrierAt = stamp; row.updatedAt = stamp; row.writerID = writer
        return try JSONEncoder().encode(DiaryInverse(model: "UpcomingDay", after: row.record(), dayKey: "", previousOrigin: nil, before: before))
    }
}
