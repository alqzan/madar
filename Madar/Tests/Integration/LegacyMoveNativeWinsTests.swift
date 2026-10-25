import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar

/// Item 24 «انقل من مدار القديم» against a store that already holds the owner's own records: what the owner logged here
/// wins, a prayer logged here is never owed again as qada (RP1), an earlier tracking start stays, and a second move adds nothing.
@MainActor final class LegacyMoveNativeWinsTests: XCTestCase {
    func testOwnerPrayerRecordsWinOverTheOldBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMoveNative-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let context = ModelContext(store.container)
        func native(_ prayer: String, _ status: String) { let row = PrayerLog(); row.dayKey = "2026-07-02"; row.prayer = prayer; row.status = status; row.tzID = "Asia/Riyadh"; row.dayPolicy = "fajr@1"; context.insert(row) }
        native("fajr", "alone"); native("asr", "jamaah")
        let settings = try SettingsStore(context: context)
        _ = try settings.stage(["salah.trackingStart": .object(["dayKey": .string("2026-06-01"), "edits": .number(0)])])
        try context.save()
        // Old: Fajr in congregation, Asr «فائتة» (would be owed), Maghrib «قضاء», Isha «لم».
        let backup = try JSONSerialization.data(withJSONObject: ["prayerLogs": [["date": "2026-07-02", "prayers": ["الفجر": "جماعة", "الظهر": "منفردة", "العصر": "فائتة", "المغرب": "قضاء", "العشاء": "لم"], "prayerUpdatedAt": ["المغرب": 1783090800000]]]])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T12:00:00+03:00"))
        let counts = try session.importLegacyPrayer(backup, now: now)
        XCTAssertEqual(counts["logs.keptNative"], 2); XCTAssertEqual(counts["qada.keptNative"], 1)
        let check = ModelContext(store.container)
        let logs = try check.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == "2026-07-02" && $0.deletedAt == nil }
        XCTAssertEqual(Dictionary(logs.map { ($0.prayer, $0.status) }, uniquingKeysWith: { a, b in a + "+" + b }),
                       ["fajr": "alone", "dhuhr": "alone", "asr": "jamaah", "maghrib": "qada", "isha": "unrecordedHistory"])
        let qada = try check.fetch(FetchDescriptor<QadaItem>()).filter { $0.deletedAt == nil }
        XCTAssertEqual(qada.map(\.prayer), ["maghrib"], "Asr was prayed here in congregation; it must not be owed")
        XCTAssertEqual(try SettingsStore(context: check).value(for: "salah.trackingStart").object?["dayKey"]?.string, "2026-06-01")
        let before = try RecordBridge.all(check).count
        let again = try session.importLegacyPrayer(backup, now: now.addingTimeInterval(60))
        XCTAssertNil(again["logs.created"]); XCTAssertNil(again["qada.created"])
        XCTAssertEqual(try RecordBridge.all(ModelContext(store.container)).count, before)
    }
}
