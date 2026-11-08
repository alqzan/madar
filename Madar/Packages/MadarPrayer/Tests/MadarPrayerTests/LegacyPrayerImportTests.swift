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
        "qadaBacklog": 37,
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

    @Test func importsOnlyPerformedPrayerRecordsAndStripsUnperformedArchiveFields() throws {
        let plan = try run()
        #expect(row(plan, "2026-07-02", .fajr)?.status == .jamaah && row(plan, "2026-07-02", .fajr)?.heart == .khashi)
        #expect(row(plan, "2026-07-02", .dhuhr)?.status == .alone && row(plan, "2026-07-02", .dhuhr)?.heart == .present)
        for prayer in [Prayer.asr, .maghrib, .isha] {
            #expect(row(plan, "2026-07-02", prayer) == nil)
        }
        #expect(plan.logs.count == 4)
        #expect(plan.counts["prayer.oldQadaSkipped"] == 1)
        #expect((plan.counts["prayer.unperformedSkipped"] ?? 0) > 0)
        let archive = try #require(plan.archives.first { $0.dayKey == "2026-07-02" })
        let archived = try #require(JSONSerialization.jsonObject(with: archive.json) as? [String: Any])
        let prayers = try #require(archived["prayers"] as? [String: String])
        #expect(prayers == ["الفجر": "جماعة", "الظهر": "منفردة"])
        let hearts = try #require(archived["khushu"] as? [String: Int])
        #expect(hearts == ["الفجر": 3, "الظهر": 2])
        let stamps = try #require(archived["prayerUpdatedAt"] as? [String: Int])
        #expect(stamps.isEmpty)
    }

    @Test func historyGapsFridayAndTracking() throws {
        let plan = try run()
        #expect(plan.trackingStart?.description == "2026-07-02")
        #expect(plan.counts["skipped.day"] == 1)
        // 07-03 has no legacy record inside the history and imports no placeholder rows.
        #expect(Prayer.allCases.allSatisfy { row(plan, "2026-07-03", $0) == nil })
        #expect(plan.counts["day.absentInsideHistory"] == 1)
        // Days after the last legacy day are not invented.
        #expect(plan.logs.contains { $0.dayKey > "2026-07-04" } == false)
        #expect(plan.logs.count == 4)
        #expect(plan.counts["prayer.oldQadaSkipped"] == 1)
    }

    @Test func fridayNoonAloneIsDhuhrOtherwiseJumuah() throws {
        // Owner, 24 Oct 2026: the old app's recorded Friday noons were Jumu'ah, except «منفردة», which cannot be.
        let plan = try run(["prayerLogs": [["date": "2026-07-03", "prayers": ["الظهر": "منفردة"]], ["date": "2026-07-10", "prayers": ["الظهر": "جماعة"]]]])
        #expect(row(plan, "2026-07-03", .dhuhr)?.fridayKind == .dhuhr)
        #expect(row(plan, "2026-07-10", .dhuhr)?.status == .jamaah && row(plan, "2026-07-10", .dhuhr)?.fridayKind == .jumuah)
        #expect(plan.counts["friday.jumuahByOwner"] == 1)
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
        print("OWNER-PRAYER-COUNTS", plan.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "), "logs=\(plan.logs.count) start=\(plan.trackingStart?.description ?? "-")")
        #expect(plan.counts.keys.contains { $0.hasPrefix("skipped.") || $0.hasPrefix("archived.unknown") } == false)
    }
}
