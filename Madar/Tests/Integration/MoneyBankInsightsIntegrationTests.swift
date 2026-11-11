import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarCommands
@testable import Madar

@MainActor final class MoneyBankInsightsIntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_141_200) // 2026-10-16 09:00 UTC, midday in Riyadh

    private func makeSession() throws -> (AppSession, ModelContext, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BankInsights-" + UUID().uuidString)
        let container = try MadarContainerFactory.makeLocal(at: root)
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        return (app, ModelContext(container), root)
    }

    func testDuesAreReadWithDaysUntilAndOpenOnly() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        func due(_ payee: String, days: Double, closed: Bool = false) {
            let row = UpcomingDue(); row.payee = payee; row.amountMinor = 25_000; row.currency = "SAR"; row.dueAt = now.addingTimeInterval(days * 86_400)
            if closed { let payment = MoneyTransaction(); payment.eventAt = now; context.insert(payment); row.closedByTransactionID = payment.id }
            context.insert(row)
        }
        due("فاتورة الاختبار", days: 2); due("قسط متأخر", days: -3); due("بلا مطابقة", days: 5, closed: true)
        try context.save()
        let insights = try AppMoneyService(app: app).loadBankInsights(at: now)
        XCTAssertEqual(insights.dues.map(\.payee), ["قسط متأخر", "فاتورة الاختبار"], "open dues by due date; a due closed by a live payment is not listed")
        XCTAssertEqual(insights.dues.map(\.daysUntil), [-3, 2])
        XCTAssertTrue(insights.mismatches.isEmpty, "no stored bank reading, no mismatch")
    }

    func testMismatchRowOpensForPrintedBalanceBelowBookAndSettlesThroughReconcileShape() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let account = Account(); account.name = "حساب الاختبار"; account.balanceMinor = 100_000; account.balanceAt = now.addingTimeInterval(-2 * 86_400); context.insert(account)
        let reading = BankReading(); reading.accountID = account.id; reading.balanceMinor = 90_000; reading.balanceAt = now.addingTimeInterval(-3600); context.insert(reading)
        try context.save()
        let insights = try AppMoneyService(app: app).loadBankInsights(at: now)
        let row = try XCTUnwrap(insights.mismatches.first)
        XCTAssertEqual(insights.mismatches.count, 1)
        XCTAssertEqual(row.expectedMinor, 100_000); XCTAssertEqual(row.observedMinor, 90_000); XCTAssertEqual(row.differenceMinor, -10_000)
        XCTAssertTrue(row.isSettleable); XCTAssertTrue(row.names.contains(.missedSpend))
        guard case .object(let payload) = MoneyBankInsightsCopy.reconcileRow(row, name: .bankFee) else { return XCTFail("row is an object") }
        XCTAssertEqual(payload["accountID"], .string(account.id.uuidString)); XCTAssertEqual(payload["observedMinor"], .string("90000"))
        XCTAssertEqual(payload["name"], .string("bankFee"))
    }

    func testNegativePrintedBalanceShowsNumbersButIsNotSettleable() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let account = Account(); account.name = "مكشوف"; account.balanceMinor = 5_000; account.balanceAt = now.addingTimeInterval(-86_400); context.insert(account)
        let reading = BankReading(); reading.accountID = account.id; reading.balanceMinor = -2_000; reading.balanceAt = now.addingTimeInterval(-600); context.insert(reading)
        try context.save()
        let row = try XCTUnwrap(try AppMoneyService(app: app).loadBankInsights(at: now).mismatches.first)
        XCTAssertFalse(row.isSettleable)
    }

    func testAttachPayloadUsesAccountOrCardKey() {
        let question = MoneyTailQuestion(tail: "4421", sender: "بنك الاختبار", candidates: [])
        let card = MoneyTailQuestion.Candidate(kind: .card, uuid: UUID(), name: "بطاقة", bank: "بنك الاختبار")
        let account = MoneyTailQuestion.Candidate(kind: .account, uuid: UUID(), name: "جاري", bank: "بنك الاختبار")
        let a = MoneyBankInsightsCopy.attachPayload(question, candidate: card, kind: .applePay)
        XCTAssertEqual(a["cardID"], .string(card.uuid.uuidString)); XCTAssertNil(a["accountID"]); XCTAssertEqual(a["kind"], .string("applePay"))
        let b = MoneyBankInsightsCopy.attachPayload(question, candidate: account, kind: .account)
        XCTAssertEqual(b["accountID"], .string(account.uuid.uuidString)); XCTAssertNil(b["cardID"])
        XCTAssertTrue(MoneyCommandPayload.validate(name: "money.attachTail", payload: a))
    }

    func testDuePhrasesInPlainWords() {
        let d = MadarNumberFormatter(style: .hindi)
        func p(_ n: Int?) -> String { MoneyBankInsightsCopy.duePhrase(daysUntil: n, digits: d) }
        XCTAssertEqual(p(0), "اليوم"); XCTAssertEqual(p(1), "غدًا"); XCTAssertEqual(p(2), "بعد يومين")
        XCTAssertEqual(p(4), "بعد ٤ أيام"); XCTAssertEqual(p(12), "بعد ١٢ يومًا")
        XCTAssertEqual(p(-1), "تأخر يوم"); XCTAssertEqual(p(-3), "تأخر ٣ أيام"); XCTAssertEqual(p(nil), "بلا موعد محدد")
    }
}
