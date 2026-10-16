import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

@MainActor final class MoneyCardsIntegrationTests: XCTestCase {
    func testCardSourcesForecastAndOwnershipAreReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyCards-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00+03:00")! }
        let now = at("2026-10-01")
        let owned = Account(); owned.balanceMinor = 2_000_000; owned.balanceAt = at("2026-09-01"); c.insert(owned)
        let other = Account(); other.ownership = "notMine"; other.balanceMinor = 10_000_000; c.insert(other)
        let card = Card(); card.name = "بطاقة الاختبار"; card.accountID = owned.id; card.limitMinor = 2_000_000; card.cashbackBp = 50; c.insert(card)
        let notMine = Card(); notMine.name = "حساب ليس لي"; notMine.accountID = other.id; c.insert(notMine)
        for close in ["2026-08-10", "2026-09-10"] {
            let s = Statement(); s.cardID = card.id; s.closeDate = at(close); s.periodStart = at("2026-08-10"); s.dueDate = at("2026-09-20"); s.statementMinor = 680_000; s.minimumDueMinor = 21_300; c.insert(s)
        }
        let purchase = MoneyTransaction(); purchase.cardID = card.id; purchase.amountMinor = 180_000; purchase.homeAmountMinor = 180_000; purchase.eventAt = at("2026-09-20"); purchase.dayKey = "2026-09-20"; purchase.method = "card"; c.insert(purchase)
        let payment = MoneyTransaction(); payment.cardID = card.id; payment.kind = "cardPayment"; payment.fromAccountID = owned.id; payment.amountMinor = 425_000; payment.homeAmountMinor = 425_000; payment.eventAt = at("2026-09-15"); payment.dayKey = "2026-09-15"; c.insert(payment)
        try c.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let reading = try AppMoneyService(app: app).loadCards(at: now)
        XCTAssertEqual(reading.cards.count, 1, "The other owner's card is excluded")
        let result = try XCTUnwrap(reading.cards.first)
        XCTAssertEqual(result.billedMinor, 255_000, "680000 − 425000")
        XCTAssertEqual(result.unbilledMinor, 180_000)
        XCTAssertEqual(result.owedMinor, 435_000)
        XCTAssertEqual(result.nextClose?.description, "2026-10-10")
        XCTAssertEqual(result.purchaseDue?.description, "2026-10-20")
        XCTAssertEqual(result.graceDays, 19)
        XCTAssertEqual(reading.cashMinor, 1_575_000, "Cash loses the confirmed payment once")
        XCTAssertEqual(reading.dues.first?.cashAfterMinor, 1_320_000, "1575000 − 255000")
        XCTAssertNil(result.aprBp, "Unknown interest is not zero")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).count, 2)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Allocation>()).count, 0)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == purchase.id }?.dayKey, "2026-09-20")
    }
}
