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
    /// A Quran plan the owner keeps here stays the plan: the old sessions arrive as history outside it, so they never
    /// move the native frontier, and a second move adds nothing.
    func testOwnerQuranPlanStaysThePlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMoveQuran-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let context = ModelContext(store.container)
        let mine = HifzPlan(); mine.startAyah = 1; mine.unit = "page"; mine.amount = 1; mine.frontierAyah = 300
        mine.activeFrom = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-01T00:00:00+03:00")); context.insert(mine)
        try context.save()
        let backup = try JSONSerialization.data(withJSONObject: ["quranHifz": [
            "plan": ["intensity": "intense", "unit": "quarter", "createdAt": "2026-07-19", "amount": 1, "reviewWindowPages": 10, "startId": 1],
            "frontierId": 12, "planId": "l:1:2026-07-19", "planUpdatedAt": 1784988142570,
            "sessions": [["id": "s-1", "date": "2026-07-19", "fromId": 1, "toId": 5, "rating": 3], ["id": "s-2", "date": "2026-07-20", "fromId": 6, "toId": 7, "rating": 1, "at": 1784530800000]],
        ]])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T12:00:00+03:00"))
        let counts = try session.importLegacyQuran(backup, fileName: "old.json", now: now)
        XCTAssertEqual(counts["plan.keptNative"], 1)
        let check = ModelContext(store.container)
        let plans = try check.fetch(FetchDescriptor<HifzPlan>()).filter { $0.deletedAt == nil }
        XCTAssertEqual(plans.map(\.id), [mine.id]); XCTAssertEqual(plans.first?.frontierAyah, 300)
        let sessions = try check.fetch(FetchDescriptor<HifzSession>()).filter { $0.deletedAt == nil }
        XCTAssertEqual(sessions.count, counts["sessions.created"]); XCTAssertGreaterThanOrEqual(sessions.count, 2); XCTAssertTrue(sessions.allSatisfy { $0.planID == nil }, "Old sessions must stay outside the owner's plan")
        let before = try RecordBridge.all(check).count
        let again = try session.importLegacyQuran(backup, fileName: "old.json", now: now.addingTimeInterval(60))
        XCTAssertNil(again["sessions.created"])
        XCTAssertEqual(try RecordBridge.all(ModelContext(store.container)).count, before)
    }
    /// The same bank account and card the owner already added here are reused, never duplicated, and a second move adds nothing.
    func testOwnerAccountAndCardAreReusedNotDuplicated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMoveMoney-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let context = ModelContext(store.container)
        let account = Account(); account.name = "حسابي"; account.bank = "SAB"; account.last4 = "9999"; context.insert(account)
        let card = Card(); card.name = "بطاقتي"; card.bank = "SAB"; card.last4 = "1234"; context.insert(card)
        try context.save()
        let backup = Data(#"{"accounts":[{"id":"a1","kind":"card","last4":"1234","bank":"sab","fundingKind":"credit"},{"id":"a2","kind":"account","last4":"9999","bank":"sab"}],"transactions":[{"id":"t-man","date":"2026-07-03","amount":12.3}]}"#.utf8)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T12:00:00+03:00"))
        _ = try await session.importLegacyMoney(backup, now: now)
        let check = ModelContext(store.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.last4 == "9999" }.map(\.id), [account.id])
        XCTAssertEqual(try check.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.last4 == "1234" }.map(\.id), [card.id])
        XCTAssertEqual(try check.fetch(FetchDescriptor<Account>()).first { $0.id == account.id }?.name, "حسابي", "The owner's own name stays")
        XCTAssertEqual(try check.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.amountMinor == 1230 }.count, 1, "The old spend must arrive")
        let before = try RecordBridge.all(check).filter { $0.model != "CommandReceipt" }.count
        _ = try await session.importLegacyMoney(backup, now: now.addingTimeInterval(60))
        XCTAssertEqual(try RecordBridge.all(ModelContext(store.container)).filter { $0.model != "CommandReceipt" }.count, before)
    }
}
