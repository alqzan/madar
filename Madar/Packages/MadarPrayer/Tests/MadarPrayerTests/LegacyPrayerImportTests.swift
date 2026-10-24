import Foundation
import Testing
import MadarCore
@testable import MadarPrayer

/// Expected values come from the legacy definitions (types.ts at aba0c1b: PrayerStatus لم/منفردة/جماعة/فائتة/قضاء,
/// KHUSHU_META 1 شارد · 2 حاضر · 3 خاشع), §17 (unrecorded history, never missed) and RP1. 2026-07-03 is a Friday.
@Suite struct LegacyPrayerImportTests {
    func uuid(_ key: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 { key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100000001b3 } }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        return UUID(uuidString: String(format: "%08X-%04X-%04X-%04X-%012llX", UInt32(a >> 32), UInt16((a >> 16) & 0xFFFF), UInt16(a & 0xFFFF), UInt16(b >> 48), b & 0xFFFFFFFFFFFF))!
    }
    let fixture: [String: Any] = [
        "qadaBacklog": 0,
        "prayerLogs": [
            ["date": "2026-07-02", "prayers": ["الفجر": "جماعة", "الظهر": "منفردة", "العصر": "فائتة", "المغرب": "قضاء", "العشاء": "لم"],
             "khushu": ["الفجر": 3, "الظهر": 2, "المغرب": 1], "prayerUpdatedAt": ["المغرب": 1783090800000]],
            ["date": "2026-07-04", "prayers": ["الفجر": "جماعة", "الظهر": "جماعة"]],
            ["date": "2026-07-03x", "prayers": ["الفجر": "جماعة"]],
        ],
    ]
    func run(_ value: [String: Any]? = nil) throws -> LegacyPrayerImport.Plan {
        try LegacyPrayerImport.plan(backup: JSONSerialization.data(withJSONObject: value ?? fixture), home: .riyadh, uuid: { uuid($0) })
    }
    func row(_ plan: LegacyPrayerImport.Plan, _ day: String, _ prayer: Prayer) -> LegacyPrayerImport.LogRow? { plan.logs.first { $0.dayKey == day && $0.prayer == prayer } }

    @Test func statusesHeartsAndDebts() throws {
        let plan = try run()
        #expect(row(plan, "2026-07-02", .fajr)?.status == .jamaah && row(plan, "2026-07-02", .fajr)?.heart == .khashi)
        #expect(row(plan, "2026-07-02", .dhuhr)?.status == .alone && row(plan, "2026-07-02", .dhuhr)?.heart == .present)
        #expect(row(plan, "2026-07-02", .asr)?.status == .missed && row(plan, "2026-07-02", .asr)?.heart == nil)
        #expect(row(plan, "2026-07-02", .maghrib)?.status == .qada && row(plan, "2026-07-02", .maghrib)?.heart == .distracted)
        // «لم» on a past legacy day is history, never a debt (RP1).
        #expect(row(plan, "2026-07-02", .isha)?.status == .unrecordedHistory)
        let owed = plan.qada.first { $0.dayKey == "2026-07-02" && $0.prayer == .asr }
        let madeUp = plan.qada.first { $0.dayKey == "2026-07-02" && $0.prayer == .maghrib }
        #expect(owed != nil && owed?.madeUpAt == nil)
        #expect(madeUp?.madeUpAt == Date(timeIntervalSince1970: 1_783_090_800))
        #expect(plan.qada.count == 2)
    }

    @Test func historyGapsFridayAndTracking() throws {
        let plan = try run()
        #expect(plan.trackingStart?.description == "2026-07-02")
        #expect(plan.counts["skipped.day"] == 1)
        // 07-03 has no legacy record inside the history: all five prayers are unrecorded history.
        #expect(Prayer.allCases.allSatisfy { row(plan, "2026-07-03", $0)?.status == .unrecordedHistory })
        #expect(plan.counts["day.absentInsideHistory"] == 1)
        // Days after the last legacy day are not invented.
        #expect(plan.logs.contains { $0.dayKey > "2026-07-04" } == false)
        #expect(plan.logs.count == 15)
        #expect(row(plan, "2026-07-03", .dhuhr)?.fridayKind == nil)
    }

    @Test func fridayNoonAloneIsDhuhrJamaahIsNotGuessed() throws {
        let plan = try run(["prayerLogs": [["date": "2026-07-03", "prayers": ["الظهر": "منفردة"]], ["date": "2026-07-10", "prayers": ["الظهر": "جماعة"]]]])
        #expect(row(plan, "2026-07-03", .dhuhr)?.fridayKind == .dhuhr)
        #expect(row(plan, "2026-07-10", .dhuhr)?.status == .jamaah && row(plan, "2026-07-10", .dhuhr)?.fridayKind == nil)
        #expect(plan.counts["friday.kindUnknown"] == 1)
    }

    @Test func eventTimesAreTheDayAdhanAndRunIsDeterministic() throws {
        let plan = try run()
        let times = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-07-02"), place: .riyadh, options: .init()))
        #expect(row(plan, "2026-07-02", .fajr)?.eventAt == times.fajr)
        #expect(row(plan, "2026-07-02", .isha)?.loggedAt == nil)
        #expect(try run() == plan)
        #expect(LegacyPrayerImport.heart(legacy: 4) == nil && LegacyPrayerImport.heart(legacy: true) == nil)
    }

    /// Owner data, this Mac only: runs when MADAR_TRIAL_PRAYER names the old backup. Prints counts, never content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_PRAYER"] != nil)) func ownerBackupPlans() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MADAR_TRIAL_PRAYER"])
        let plan = try LegacyPrayerImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), home: .riyadh, uuid: { uuid($0) })
        print("OWNER-PRAYER-COUNTS", plan.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "), "qada=\(plan.qada.count) open=\(plan.qada.filter { $0.madeUpAt == nil }.count) start=\(plan.trackingStart?.description ?? "-")")
        #expect(plan.counts.keys.contains { $0.hasPrefix("skipped.") || $0.hasPrefix("archived.unknown") } == false)
    }
}
