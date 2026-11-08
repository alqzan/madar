import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import CryptoKit
@testable import Madar

/// Item 24 «انقل من مدار القديم» against a store that already holds the owner's own records: what the owner logged here
/// wins, a prayer logged here is never owed again as qada (RP1), an earlier tracking start stays, and a second move adds nothing.
@MainActor final class LegacyMoveNativeWinsTests: XCTestCase {
    func testMoneySettingsReplayWithAnAlreadyDefaultCalendarNeedsNoNewCommand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveSettingsReplay-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppLegacyMoveService(app: app)
        let data = Data(#"{"dailyBudget":{"amount":80},"salaryDay":27}"#.utf8)
        let preview = LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data))
        _ = try await service.commit(preview, progress: { _ in })
        let settings = try SettingsStore(context: ModelContext(store.container))
        XCTAssertEqual(try settings.value(for: "mal.salaryDay"), .number(27))
        XCTAssertEqual(try settings.value(for: "mal.cycleCalendar"), .string("gregorian"))
        XCTAssertEqual(try settings.value(for: "mal.dailyAllowance"), .object(["mode": .string("fixed"), "amountMinor": .number(8000), "percentBp": .null]))
        func rows() throws -> [DataRecord] { try RecordBridge.all(ModelContext(store.container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) } }
        let before = try rows()
        let replay = try await service.commit(preview, progress: { _ in })
        XCTAssertTrue(replay.outcomes.allSatisfy { $0.failed == nil }, "Matching settings are not an incomplete move")
        XCTAssertEqual(try rows(), before)
    }

    func testMovementProgressFinishesForBothNewAndAlreadyPresentMovements() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveProgress-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppLegacyMoveService(app: app)
        let data = Data(#"{"transactions":[{"id":"p1","date":"2026-07-03","amount":12.3},{"id":"p2","date":"2026-07-04","amount":45}]}"#.utf8)
        let preview = LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data))
        for expectedAdded in [true, false] {
            var reports: [(Int, Int)] = []
            let result = try await service.commit(preview, progress: { _ in }, movementProgress: { reports.append(($0, $1)) })
            XCTAssertEqual(result.added > 0, expectedAdded)
            XCTAssertEqual(reports.last?.0, 2); XCTAssertEqual(reports.last?.1, 2)
            XCTAssertTrue(reports.allSatisfy { $0.0 > 0 && $0.0 <= $0.1 && $0.1 == 2 })
        }
    }

    /// Item 24 + B-01: all five old-app rooms, a native diary memory and its attachment cross a real encrypted restore.
    func testEveryRoomMoveReopensRestoresAndReplaysWithoutGrowth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EveryRoomRestore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source"), store = try ManagedDataStore(root: sourceRoot)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: sourceRoot)
        app.authorizeProtectedData()
        let service = AppLegacyMoveService(app: app)
        let data = Data(#"""
        {"prayerLogs":[{"date":"2026-07-02","prayers":{"الفجر":"جماعة","الظهر":"منفردة","العصر":"فائتة"}}],
        "quranHifz":{"plan":{"intensity":"intense","unit":"quarter","createdAt":"2026-07-19","amount":1,"reviewWindowPages":10,"startId":1},"frontierId":5,"planId":"l:1:2026-07-19","planUpdatedAt":1784988142570,"sessions":[{"id":"s-1","date":"2026-07-19","fromId":1,"toId":5,"rating":3}]},
        "habits":[{"id":"h","name":"عادة اصطناعية","logs":["2026-10-21"]}],
        "futureLetters":[{"id":"l","content":"رسالة اصطناعية مغلقة","writtenDate":"2026-10-01","deliveryDate":"2030-11-19","opened":false}],
        "countdownEvents":[{"id":"d","title":"موعد اصطناعي","date":"2026-07-01","countUpAfter":true}],
        "categories":[{"id":"c","label":"تصنيف اصطناعي"}],"merchantRules":{"synthetic shop":"c"},
        "accounts":[{"id":"a","kind":"account","last4":"9999","bank":"sab"},{"id":"card","kind":"card","last4":"1234","bank":"sab","fundingKind":"credit"}],"transactions":[{"id":"t","date":"2026-07-03","amount":12.3,"category":"c"}]}
        """#.utf8)
        let moved = try await service.commit(LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data)), progress: { _ in })
        XCTAssertEqual(Set(moved.outcomes.filter { $0.added > 0 && $0.failed == nil }.map(\.id)), Set(["prayer", "quran", "habits", "personal", "money"]))
        let context = ModelContext(store.container)
        let entry = Entry(); entry.dayKey = "2026-10-21"; entry.text = "ذكرى اصطناعية"; context.insert(entry)
        let media = Media(), bytes = Data("synthetic attached media".utf8)
        media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        context.insert(media); entry.mediaID = media.id
        let time = try XCTUnwrap(context.fetch(FetchDescriptor<HabitEvent>()).first); time.entryID = entry.id
        // Native edits must still win after restoration removed the device's command receipts.
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first)
        account.name = "اسم حساب محلي"; account.balanceMinor = 12345; account.balanceAt = Date()
        let card = try XCTUnwrap(context.fetch(FetchDescriptor<Card>()).first); card.name = "اسم بطاقة محلي"
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<MerchantRule>()).first); rule.ignore = true; rule.categoryID = nil
        let movement = try XCTUnwrap(context.fetch(FetchDescriptor<MoneyTransaction>()).first)
        XCTAssertEqual(movement.categorySource, "rule", "Legacy-moved categories use rule provenance.")
        movement.amountMinor = 4567
        try context.save()
        func fingerprint(_ container: ModelContainer) throws -> String {
            let rows = try RecordBridge.all(ModelContext(container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return SHA256.hash(data: try encoder.encode(rows)).map { String(format: "%02x", $0) }.joined()
        }
        let expected = try fingerprint(store.container)
        let reopened = try ManagedDataStore(root: sourceRoot)
        XCTAssertEqual(try fingerprint(reopened.container), expected)
        let password = "synthetic all room password"
        let backup = BackupCoordinator(store: reopened, backupDirectory: root.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        try await backup.configurePassphrase(password)
        let receipt = try await backup.export(kind: .automatic)
        XCTAssertEqual(receipt.fileURL.pathExtension, "madarbackupset")
        let targetRoot = root.appendingPathComponent("Target"), target = try ManagedDataStore(root: targetRoot)
        let restore = BackupCoordinator(store: target, backupDirectory: root.appendingPathComponent("Safety"), keyStore: MemoryBackupKeyStore())
        try await restore.configurePassphrase(password)
        let preview = try await restore.preview(file: receipt.fileURL, passphrase: password)
        _ = try await restore.restore(preview: preview, mode: .merge)
        let restored = try ManagedDataStore(root: targetRoot)
        XCTAssertEqual(try fingerprint(restored.container), expected)
        let check = ModelContext(restored.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<HabitEvent>()).first?.entryID, entry.id)
        XCTAssertEqual(try check.fetch(FetchDescriptor<UpcomingDay>()).first?.countUpAfter, true)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Letter>()).first?.state, "sealed")
        XCTAssertEqual(try check.fetch(FetchDescriptor<MoneyTransaction>()).map(\.amountMinor), [4567])
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<CommandReceipt>()), 0)
        let targetApp = try AppSession(container: restored.container, managedStore: restored, groupDirectory: targetRoot)
        targetApp.authorizeProtectedData()
        let targetService = AppLegacyMoveService(app: targetApp)
        let beforeReplay = try fingerprint(restored.container)
        let beforeRows = try RecordBridge.all(ModelContext(restored.container))
        let replay = try await targetService.commit(LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: targetService.preview(data)), progress: { _ in })
        XCTAssertEqual(replay.added, 0); XCTAssertTrue(replay.outcomes.allSatisfy { $0.failed == nil })
        let afterRows = try RecordBridge.all(ModelContext(restored.container))
        let changes = beforeRows.compactMap { old -> String? in
            guard let new = afterRows.first(where: { $0.model == old.model && $0.id == old.id }), new != old else { return nil }
            return old.model + ": " + Set(old.fields.keys).union(new.fields.keys).filter { old.fields[$0] != new.fields[$0] }.sorted().joined(separator: ",")
        }
        XCTAssertEqual(try fingerprint(restored.container), beforeReplay, changes.joined(separator: "; "))
    }

    func testReplayUndoKeepsMemoryWrittenBetweenMoves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveReplayUndo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        session.authorizeProtectedData()
        let service = AppLegacyMoveService(app: session)
        let data = Data(#"{"habits":[{"id":"h","name":"عادة اصطناعية","logs":["2026-10-21"]}]}"#.utf8)
        let preview = LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data))
        let first = try await service.commit(preview, progress: { _ in })
        XCTAssertGreaterThan(first.added, 0)
        let context = ModelContext(store.container)
        let memory = Entry(); memory.dayKey = "2026-10-25"; memory.text = "كتابة بعد النقل"; context.insert(memory); try context.save()
        let memoryID = memory.id
        let replay = try await service.commit(preview, progress: { _ in })
        XCTAssertEqual(replay.added, 0)
        let undo = try await service.undo()
        XCTAssertFalse(undo.isPartial)
        let check = ModelContext(store.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Entry>()).first { $0.id == memoryID }?.text, "كتابة بعد النقل")
        XCTAssertTrue(try check.fetch(FetchDescriptor<Habit>()).isEmpty)
        let again = try await service.commit(preview, progress: { _ in })
        XCTAssertEqual(again.added, first.added)
    }

    func testInterruptedUndoKeepsMemoryWrittenAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveInterruptedUndo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        session.authorizeProtectedData()
        let context = ModelContext(store.container)
        let habit = Habit(); habit.name = "نقل محفوظ"; context.insert(habit); try context.save()
        let imported = try RecordBridge.all(context, syncedOnly: false)
        struct Journal: Codable { let receipt: LegacyMoveReceipt; let before: [DataRecord]; let after: [DataRecord]; let complete: Bool?; let version: Int }
        let folder = root.appendingPathComponent("LegacyMove")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let receipt = LegacyMoveReceipt(at: Date(), fileName: "synthetic.json", outcomes: [], undoneAt: nil)
        try JSONEncoder().encode(Journal(receipt: receipt, before: [], after: imported, complete: nil, version: 2)).write(to: folder.appendingPathComponent("undo.json"))
        // A later launch allows new native writes. They were never part of the interrupted move.
        let memory = Entry(); memory.dayKey = "2026-10-25"; memory.text = "كتابة بعد الانقطاع"; context.insert(memory)
        let uncheckpointed = Habit(); uncheckpointed.name = "جزء لم يُحفظ في سجل النقل"; context.insert(uncheckpointed); try context.save()
        let service = AppLegacyMoveService(app: session)
        let undo = try await service.undo()
        XCTAssertTrue(undo.isPartial)
        let check = ModelContext(store.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Entry>()).first { $0.id == memory.id }?.text, "كتابة بعد الانقطاع")
        XCTAssertEqual(try check.fetch(FetchDescriptor<Habit>()).map(\.id), [uncheckpointed.id], "Only checkpointed changes can safely be undone")
    }

    func testLegacyUndoReceiptCannotDeleteUnprovenNativeRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveOldReceipt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        session.authorizeProtectedData()
        let context = ModelContext(store.container)
        let memory = Entry(); memory.text = "كتابة أصلية في سجل قديم"; context.insert(memory); try context.save()
        struct OldJournal: Codable { let receipt: LegacyMoveReceipt; let before: [DataRecord]; let after: [DataRecord]; let complete: Bool }
        let folder = root.appendingPathComponent("LegacyMove")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let receipt = LegacyMoveReceipt(at: Date(), fileName: "old.json", outcomes: [], undoneAt: nil)
        let rows = try RecordBridge.all(context, syncedOnly: false)
        try JSONEncoder().encode(OldJournal(receipt: receipt, before: [], after: rows, complete: true)).write(to: folder.appendingPathComponent("undo.json"))
        let result = try await AppLegacyMoveService(app: session).undo()
        XCTAssertTrue(result.isPartial); XCTAssertEqual(result.plan.removed, 0)
        XCTAssertEqual(try ModelContext(store.container).fetch(FetchDescriptor<Entry>()).first?.text, memory.text)
    }

    func testUndoKeepsRulesForAnImportedHabitUsedAfterTheMove() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveUsedHabit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        session.authorizeProtectedData()
        let service = AppLegacyMoveService(app: session)
        let data = Data(#"{"habits":[{"id":"h","name":"عادة مستخدمة","logs":["2026-10-21"]}]}"#.utf8)
        _ = try await service.commit(LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data)), progress: { _ in })
        let context = ModelContext(store.container), habit = try XCTUnwrap(context.fetch(FetchDescriptor<Habit>()).first)
        let day = GregorianDay.containing(session.prayerNow(), in: session.activePlace.timeZone)
        let event = HabitEvent(); event.habitID = habit.id; event.dayKey = day.description; event.periodKey = day.description
        event.delta = 1; event.eventAt = session.prayerNow(); context.insert(event); try context.save()
        _ = try await service.undo()
        let check = ModelContext(store.container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Habit>()).map(\.id), [habit.id])
        XCTAssertEqual(try check.fetch(FetchDescriptor<HabitEvent>()).map(\.id), [event.id])
        XCTAssertEqual(try check.fetch(FetchDescriptor<HabitPolicy>()).first?.frequency, "daily")
        let reading = try XCTUnwrap(HabitRepository(context: check).readings(at: session.prayerNow()).first)
        XCTAssertNotNil(reading.summary.current); XCTAssertEqual(reading.summary.current?.value, 1)
    }

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
        // Old: Fajr in congregation, Asr «فائتة», Maghrib «قضاء», Isha «لم»; only the performed Fajr/Dhuhr import.
        let backup = try JSONSerialization.data(withJSONObject: ["prayerLogs": [["date": "2026-07-02", "prayers": ["الفجر": "جماعة", "الظهر": "منفردة", "العصر": "فائتة", "المغرب": "قضاء", "العشاء": "لم"], "prayerUpdatedAt": ["المغرب": 1783090800000]]]])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T12:00:00+03:00"))
        let counts = try session.importLegacyPrayer(backup, now: now)
        XCTAssertEqual(counts["logs.keptNative"], 1); XCTAssertEqual(counts["logs.created"], 1)
        XCTAssertEqual(counts["prayer.oldQadaSkipped"], 1)
        let check = ModelContext(store.container)
        let logs = try check.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == "2026-07-02" && $0.deletedAt == nil }
        XCTAssertEqual(Dictionary(logs.map { ($0.prayer, $0.status) }, uniquingKeysWith: { a, b in a + "+" + b }),
                       ["fajr": "alone", "dhuhr": "alone", "asr": "jamaah"])
        let qada = try check.fetch(FetchDescriptor<QadaItem>()).filter { $0.deletedAt == nil }
        XCTAssertTrue(qada.isEmpty, "Legacy backlog rows are never reintroduced.")
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

    func testNewMovementUsesTheLiveOwnerOfAMergedSourceAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveAccountAlias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let context = ModelContext(store.container)
        let canonical = Account(); canonical.name = "حسابي الحالي"; canonical.balanceAt = nil; context.insert(canonical)
        let alias = Account(); alias.id = StableIdentity.uuid(for: "LegacyAccount:earlier"); alias.mergedInto = canonical.id; context.insert(alias)
        try context.save()
        let data = Data(#"{"transactions":[{"id":"alias-new","date":"2026-07-03","amount":12.3}]}"#.utf8)
        let service = AppLegacyMoveService(app: app)
        let receipt = try await service.commit(LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data)), progress: { _ in })
        XCTAssertNil(receipt.outcomes.first?.failed)
        let check = ModelContext(store.container)
        let moves = try check.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        XCTAssertEqual(moves.count, 1); XCTAssertEqual(moves.first?.amountMinor, 1230)
        XCTAssertEqual(moves.first?.fromAccountID, canonical.id)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Account>()).first { $0.id == alias.id }?.mergedInto, canonical.id)
    }

    func testDeletedFundingSourceReportsAnIncompleteRoomWithoutResurrectingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoveDeletedAccount-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let context = ModelContext(store.container)
        let account = Account(); account.id = StableIdentity.uuid(for: "LegacyAccount:earlier"); account.deletedAt = Date(); context.insert(account); try context.save()
        let data = Data(#"{"transactions":[{"id":"blocked-new","date":"2026-07-03","amount":12.3}]}"#.utf8)
        let service = AppLegacyMoveService(app: app)
        let receipt = try await service.commit(LegacyMovePreview(fileName: "synthetic.json", data: data, rooms: service.preview(data)), progress: { _ in })
        XCTAssertNotNil(receipt.outcomes.first?.failed); XCTAssertEqual(receipt.added, 0)
        let check = ModelContext(store.container)
        XCTAssertNotNil(try check.fetch(FetchDescriptor<Account>()).first?.deletedAt)
        XCTAssertTrue(try check.fetch(FetchDescriptor<MoneyTransaction>()).isEmpty)
    }
}
