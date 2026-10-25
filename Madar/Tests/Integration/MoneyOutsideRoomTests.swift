import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarSnapshots
@testable import Madar

@MainActor final class MoneyOutsideRoomTests: XCTestCase {
    func testSnapshotRedactionAndDiaryFactUseTheOwningMovement() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyOutside-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight"), "notes.widgetContent": .bool(true), "core.faceIDLock": .string("none")])
        XCTAssertTrue(app.moneyWidgetPayload(hidden: true, at: app.prayerNow()).rows.isEmpty, "First day has no invented zero balances")
        let now = app.prayerNow(), today = AppBahwService(session: app).today, c = ModelContext(container)
        let account = Account(); account.balanceMinor = 500037; account.balanceAt = now.addingTimeInterval(-86400); c.insert(account)
        let cycle = Cycle(); cycle.start = today.adding(days: -5).date(in: app.activePlace.timeZone); cycle.expectedEnd = today.adding(days: 25).date(in: app.activePlace.timeZone); cycle.dailyAllowanceMinor = 40000; c.insert(cycle)
        let expense = MoneyTransaction(); expense.amountMinor = 1800; expense.homeAmountMinor = 1800; expense.reviewState = "ok"; expense.fromAccountID = account.id; expense.dayKey = today.description; expense.eventAt = now; expense.showInDiary = true; c.insert(expense)
        let spend = Allocation(); spend.transactionID = expense.id; spend.cycleID = cycle.id; spend.target = "daily"; spend.amountMinor = -1800; spend.kind = "spend"; spend.idempotencyKey = "fixture-spend"; c.insert(spend)
        let pending = MoneyTransaction(); pending.amountMinor = 9900; pending.homeAmountMinor = 9900; pending.dayKey = today.description; pending.eventAt = now; pending.reviewState = "pending"; c.insert(pending)
        let payment = MoneyTransaction(); payment.kind = "cardPayment"; payment.amountMinor = 10000; payment.homeAmountMinor = 10000; payment.dayKey = today.description; payment.eventAt = now; payment.reviewState = "ok"; c.insert(payment)
        try c.save()
        let facts = try DiaryLineRenderer.live(day: today, context: ModelContext(container)).filter { $0.kind == "mal" }
        XCTAssertEqual(facts.count, 1); XCTAssertEqual(facts.first?.id, "mal." + expense.id.uuidString); XCTAssertTrue(facts.first?.text.contains("١٨٫٠٠") == true)
        try app.publishRoomWidgetSnapshots(at: now)
        let hidden = try XCTUnwrap(app.snapshotStore.read("money", as: RoomWidgetSnapshot.self, now: now))
        XCTAssertTrue(hidden.privacy.moneyHidden); XCTAssertTrue(hidden.payload.periods.isEmpty); XCTAssertTrue(hidden.payload.rows.allSatisfy { $0.value == "•••" && $0.share == 0 })
        try await app.applySettingsAndWait(["core.hideMoneyOutside": .bool(false)])
        let shown = try XCTUnwrap(app.snapshotStore.read("money", as: RoomWidgetSnapshot.self, now: app.prayerNow()))
        XCTAssertFalse(shown.privacy.moneyHidden); XCTAssertTrue(shown.payload.rows.contains { $0.id == "daily" && String($0.value.filter { $0.isNumber }) == "٤٠٠" }); XCTAssertFalse(shown.payload.periods.isEmpty)
        XCTAssertTrue(app.moneyWidgetPayload(hidden: false, locked: true, at: now).rows.isEmpty)
        // Pinning does not copy financial text into a diary widget when money is hidden outside.
        let pin = Entry(); pin.text = "صرفت ١٨ ريالًا"; pin.dayKey = today.description; pin.eventAt = now; pin.source = "autoPinned"; pin.pinnedEventKind = "mal"; pin.pinnedEventID = expense.id; c.insert(pin); try c.save()
        try await app.applySettingsAndWait(["core.hideMoneyOutside": .bool(true)])
        XCTAssertFalse(app.diaryWidgetRows(today: today).contains { $0.value.contains("١٨") })
        XCTAssertTrue(try DiaryLineRenderer.live(day: today, context: ModelContext(container)).filter { $0.kind == "mal" }.isEmpty, "Pinned fact is not duplicated")
    }
}
