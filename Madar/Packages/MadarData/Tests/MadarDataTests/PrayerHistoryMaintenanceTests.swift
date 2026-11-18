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

    /// Owner 17 Nov 2026: every prayer and qada row is removed; other records stay; a second run finds nothing.
    @Test func allPrayerRecordsAreTombstonedWithABarrierAndOtherRecordsStay() throws {
        let container = try MadarContainerFactory.makeInMemory()
        let context = container.mainContext
        let stamp = Date(timeIntervalSince1970: 1_760_000_000)
        for (index, status) in ["jamaah", "alone", "qada", "missed"].enumerated() {
            let row = PrayerLog()
            row.dayKey = String(format: "2026-11-%02d", index + 1)
            row.prayer = "isha"
            row.status = status
            row.createdAt = stamp
            row.updatedAt = stamp
            context.insert(row)
        }
        let debt = QadaItem()
        debt.prayer = "fajr"
        debt.originalDayKey = "2026-11-01"
        debt.createdAt = stamp
        debt.updatedAt = stamp
        context.insert(debt)
        let keep = Setting()
        keep.key = "salah.method"
        keep.valueJSON = Data("\"ummAlQura\"".utf8)
        keep.createdAt = stamp
        keep.updatedAt = stamp
        context.insert(keep)
        try context.save()

        let later = stamp.addingTimeInterval(120)
        #expect(try PrayerHistoryMaintenance.removeAllPrayerRecords(in: context, now: later) == 5)
        let logs = try context.fetch(FetchDescriptor<PrayerLog>())
        #expect(logs.count == 4)
        #expect(logs.allSatisfy { $0.deletedAt != nil && $0.deletionBarrierAt != nil && $0.writerID == "system.prayer-records-removed-v2" })
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<Setting>()).first { $0.key == "salah.method" }?.deletedAt == nil)
        #expect(try PrayerHistoryMaintenance.removeAllPrayerRecords(in: context, now: later) == 0)
    }

    @Test func oneTimeScrubEmptiesEveryPrayerRowAndFrozenSalahLinesButKeepsKeys() throws {
        let context = ModelContext(try MadarContainerFactory.makeInMemory())
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let row = PrayerLog()
        row.dayKey = "2026-11-10"; row.prayer = "fajr"; row.status = "jamaah"; row.heart = "present"; row.source = "notification"
        row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight@1"; row.loggedAt = stamp; row.tripID = UUID(); row.shortened = true
        row.createdAt = stamp.addingTimeInterval(-60); row.updatedAt = stamp; row.deletedAt = stamp; row.deletionBarrierAt = stamp
        context.insert(row)
        let debt = QadaItem(); debt.prayer = "dhuhr"; debt.originalDayKey = "2026-11-01"; debt.madeUpAt = stamp; debt.createdAt = stamp; debt.updatedAt = stamp; debt.deletedAt = stamp
        context.insert(debt)
        let frozen = DeviceSetting(); frozen.key = "sys.diaryAutoLines.2026-11-10"
        frozen.valueJSON = Data(#"[{"id":"a","kind":"salah","text":"x"},{"id":"b","kind":"quran","text":"y"}]"#.utf8)
        frozen.createdAt = stamp; frozen.updatedAt = stamp
        context.insert(frozen)
        try context.save()
        _ = try PrayerHistoryMaintenance.removeAllPrayerRecords(in: context, now: stamp.addingTimeInterval(60))
        let after = try #require(try context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(after.heart == nil && after.loggedAt == nil && after.tripID == nil && after.shortened == nil)
        #expect(after.status == "unrecordedHistory" && after.source == "system" && after.tzID.isEmpty && after.dayPolicy.isEmpty)
        #expect(after.dayKey == "2026-11-10" && after.prayer == "fajr", "the natural key stays")
        #expect(after.deletedAt == stamp && after.updatedAt == stamp)
        let qada = try #require(try context.fetch(FetchDescriptor<QadaItem>()).first)
        #expect(qada.madeUpAt == nil && qada.originalDayKey == "2026-11-01")
        let storedFrozen = try #require(try context.fetch(FetchDescriptor<DeviceSetting>()).first)
        let parsed = try JSONSerialization.jsonObject(with: storedFrozen.valueJSON)
        let lines = try #require(parsed as? [[String: Any]])
        #expect(lines.map { $0["kind"] as? String } == ["quran"])
        #expect(try context.fetch(FetchDescriptor<Setting>()).contains { $0.key == PrayerHistoryMaintenance.contentScrubKey })
    }
}
