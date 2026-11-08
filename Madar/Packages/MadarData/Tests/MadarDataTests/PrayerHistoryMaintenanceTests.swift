import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct PrayerHistoryMaintenanceTests {
    @Test func oldUnperformedPrayerHistoryIsTombstonedOnceAndFutureQadaRemainsRecordable() throws {
        let container = try MadarContainerFactory.makeInMemory()
        let context = container.mainContext
        let stamp = Date(timeIntervalSince1970: 1_760_000_000)
        let oldStatuses = ["missed", "qada", "unrecordedHistory", "excused"]

        for (index, status) in (oldStatuses + ["jamaah", "alone"]).enumerated() {
            let row = PrayerLog()
            row.dayKey = String(format: "2026-10-%02d", index + 1)
            row.prayer = "fajr"
            row.status = status
            row.createdAt = stamp
            row.updatedAt = stamp.addingTimeInterval(Double(index))
            context.insert(row)
        }
        for (index, madeUpAt) in [Date?.none, stamp].enumerated() {
            let debt = QadaItem()
            debt.prayer = index == 0 ? "dhuhr" : "asr"
            debt.originalDayKey = index == 0 ? "2026-10-01" : "2026-10-02"
            debt.createdAt = stamp
            debt.updatedAt = stamp.addingTimeInterval(Double(index))
            debt.madeUpAt = madeUpAt
            context.insert(debt)
        }
        let oldReminder = Setting()
        oldReminder.key = "salah.qadaReminder"
        oldReminder.valueJSON = Data("\"afterIsha\"".utf8)
        oldReminder.createdAt = stamp
        oldReminder.updatedAt = stamp
        context.insert(oldReminder)
        try context.save()

        let removed = try PrayerHistoryMaintenance.removeUnperformedPrayerHistory(in: context, now: stamp.addingTimeInterval(60))
        #expect(removed == 7)
        let rows = try context.fetch(FetchDescriptor<PrayerLog>())
        #expect(rows.filter { $0.deletedAt == nil }.map(\.status).sorted() == ["alone", "jamaah"])
        #expect(rows.filter { oldStatuses.contains($0.status) }.allSatisfy { $0.deletedAt != nil && $0.deletionBarrierAt != nil })
        let debts = try context.fetch(FetchDescriptor<QadaItem>())
        #expect(debts.count == 2 && debts.allSatisfy { $0.deletedAt != nil && $0.deletionBarrierAt != nil })
        #expect(oldReminder.deletedAt != nil && oldReminder.deletionBarrierAt != nil)

        let newPerformedQada = PrayerLog()
        newPerformedQada.dayKey = "2026-11-08"
        newPerformedQada.prayer = "fajr"
        newPerformedQada.status = "qada"
        newPerformedQada.createdAt = stamp.addingTimeInterval(120)
        newPerformedQada.updatedAt = stamp.addingTimeInterval(120)
        context.insert(newPerformedQada)
        try context.save()

        #expect(try PrayerHistoryMaintenance.removeUnperformedPrayerHistory(in: context, now: stamp.addingTimeInterval(180)) == 0)
        #expect(newPerformedQada.deletedAt == nil, "The one-time cleanup must not remove late prayers recorded after migration.")
    }
}
