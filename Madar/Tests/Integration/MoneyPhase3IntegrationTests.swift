import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarCommands
@testable import Madar

/// Phase 3 (owner, 11 Nov 2026): «يتكرر», instalment and statement dues, the refund's purchase, and fees on a movement. Invented data only.
@MainActor final class MoneyPhase3IntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_141_200) // 2026-10-16 09:00 UTC, midday in Riyadh
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    private func makeSession() throws -> (AppSession, ModelContext, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Phase3-" + UUID().uuidString)
        let container = try MadarContainerFactory.makeLocal(at: root)
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        return (app, ModelContext(container), root)
    }
    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    @discardableResult private func movement(_ context: ModelContext, kind: String = "expense", merchant: String, amount: Int, at: Date, bank: Bool = true) -> MoneyTransaction {
        let row = MoneyTransaction(); row.kind = kind; row.source = bank ? "bank" : "manual"; row.reviewState = "ok"; row.method = "transfer"
        if kind == "salary" { row.counterparty = merchant } else { row.merchant = merchant }
        row.amountMinor = amount; row.homeAmountMinor = amount; row.currency = "SAR"; row.homeCurrency = "SAR"
        row.eventAt = at; row.dayKey = GregorianDay.containing(at, in: zone).description; row.tzID = zone.identifier; row.dayPolicy = "midnight@1"
        context.insert(row); return row
    }
    private func message(_ context: ModelContext, kind: String, _ fields: [String: Any]) -> BankMessage {
        let m = BankMessage(); m.sender = "بنك الاختبار"; m.kind = kind; m.status = "ok"; m.receivedAt = now
        m.parsedJSON = try? JSONSerialization.data(withJSONObject: fields.merging(["v": 1, "kind": kind]) { a, _ in a }); context.insert(m); return m
    }

    func testRecurringListsSalaryFirstThenSubscriptionsWithOnlyTrueNotes() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        for days in [92.0, 61, 31] { movement(context, kind: "salary", merchant: "جهة العمل", amount: 1_500_000, at: ago(days)) }
        // Price rose on the last charge; the next one is due in a few days.
        for (days, amount) in [(86.0, 39_900), (56.0, 39_900), (26.0, 49_900)] { movement(context, merchant: "منصة شاهد", amount: amount, at: ago(days)) }
        // Flat price, one charge overdue by two days.
        for days in [92.0, 62, 32] { movement(context, merchant: "نادي الاختبار", amount: 15_000, at: ago(days)) }
        try context.save()
        let lines = try AppMoneyService(app: app).loadBankInsights(at: now).recurring
        XCTAssertEqual(lines.first?.isSalary, true, "the salary line comes first")
        let shahid = try XCTUnwrap(lines.first { $0.name == "منصة شاهد" })
        XCTAssertEqual(shahid.amountMinor, 49_900)
        XCTAssertEqual(shahid.notes, [.priceChange(fromMinor: 39_900, toMinor: 49_900)])
        let club = try XCTUnwrap(lines.first { $0.name == "نادي الاختبار" })
        XCTAssertEqual(club.notes.count, 1)
        guard case .late(let lateDays) = try XCTUnwrap(club.notes.first) else { return XCTFail("an overdue charge is noted as late") }
        XCTAssertTrue((1...3).contains(lateDays), "overdue by one to three days (the next date follows the month pattern)")
        XCTAssertTrue(try XCTUnwrap(lines.first).notes.isEmpty, "a steady salary carries no note")
        XCTAssertEqual(MoneyBankInsightsCopy.priceChangeSentence(rose: true, from: "٣٩٩", to: "٤٩٩"), "ارتفع من ٣٩٩ إلى ٤٩٩")
    }

    func testNoRecurringWithoutThreeCharges() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        for days in [60.0, 30] { movement(context, merchant: "اشتراك ناقص", amount: 10_000, at: ago(days)) }
        try context.save()
        XCTAssertTrue(try AppMoneyService(app: app).loadBankInsights(at: now).recurring.isEmpty)
    }

    func testDueRowsCarryInstalmentAndStatementFields() throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = message(context, kind: "bnplInstalment", ["merchant": "متجر الأدوات", "instalmentNumber": 2, "instalmentCount": 4, "remainingMinor": 80_000])
        let instalment = UpcomingDue(); instalment.payee = "Tamara"; instalment.kind = "bnpl"; instalment.amountMinor = 40_000; instalment.currency = "SAR"
        instalment.dueAt = now.addingTimeInterval(6 * 86_400); instalment.sourceMessageID = plan.id; context.insert(instalment)
        let statement = message(context, kind: "statement", ["last4": "8844", "minimumDueMinor": 21_300])
        let bill = UpcomingDue(); bill.payee = "بطاقة المشتريات"; bill.kind = "bill"; bill.amountMinor = 425_000; bill.currency = "SAR"
        bill.dueAt = now.addingTimeInterval(9 * 86_400); bill.sourceMessageID = statement.id; context.insert(bill)
        try context.save()
        let dues = try AppMoneyService(app: app).loadBankInsights(at: now).dues
        let first = try XCTUnwrap(dues.first { $0.payee == "Tamara" }), second = try XCTUnwrap(dues.first { $0.isStatement })
        let digits = MadarNumberFormatter(style: .hindi)
        XCTAssertEqual(MoneyBankInsightsCopy.instalmentPhrase(number: first.instalmentNumber, count: first.instalmentCount, digits: digits), "القسط ٢ من ٤")
        XCTAssertEqual(first.remainingMinor, 80_000); XCTAssertEqual(first.merchant, "متجر الأدوات")
        XCTAssertEqual(second.minimumDueMinor, 21_300)
        XCTAssertEqual(MoneyBankInsightsCopy.statementTitle(last4: second.cardLast4, digits: digits), "كشف بطاقة \u{200E}…٨٨٤٤")
        XCTAssertNil(MoneyBankInsightsCopy.instalmentPhrase(number: nil, count: 4, digits: digits), "no number printed, no phrase")
        XCTAssertFalse(MoneyBankInsightsCopy.statementTitle(last4: "8844", digits: digits).contains("·"))
    }

    func testRefundLinkSuggestsTheOnlyPurchaseAndOffersChoiceWhenSeveral() throws {
        let (_, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = MoneyRepository(context: context)
        let single = movement(context, merchant: "متجر الأدوات", amount: 23_000, at: ago(5))
        let refund = movement(context, kind: "refund", merchant: "متجر الأدوات", amount: 23_000, at: ago(0.1)); refund.reviewState = "needsLook"
        try context.save()
        let one = try XCTUnwrap(MoneyPhase3Reader.refundLink(for: refund, repo: repo, zone: zone))
        XCTAssertEqual(one.linked, single.id); XCTAssertEqual(one.originals.count, 1); XCTAssertEqual(one.linkedOriginal?.name, "متجر الأدوات")
        let other = movement(context, merchant: "متجر الأدوات", amount: 23_000, at: ago(3)); try context.save()
        let two = try XCTUnwrap(MoneyPhase3Reader.refundLink(for: refund, repo: repo, zone: zone))
        XCTAssertNil(two.linked, "two equal purchases: nothing is linked without a choice"); XCTAssertEqual(Set(two.originals.map(\.id)), [single.id, other.id])
        let draft = MoneyMessageDraft(id: refund.id, sender: "", title: "t", kindLabel: "", amountMinor: 23_000, currency: "SAR", direction: .incoming, possibleDuplicate: false, note: nil, clear: false, at: now, refund: two)
        XCTAssertNil(MoneyPhase3Reader.confirmPayload(draft, choice: nil)["relatedTransactionID"])
        XCTAssertEqual(MoneyPhase3Reader.confirmPayload(draft, choice: other.id)["relatedTransactionID"], .string(other.id.uuidString))
    }

    func testChosenPurchaseTravelsWithConfirmationAndNetsTheRefund() async throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let account = Account(); account.name = "حساب الاختبار"; account.balanceMinor = 1_000_000; context.insert(account)
        let first = movement(context, merchant: "متجر الأدوات", amount: 23_000, at: ago(5)); first.fromAccountID = account.id
        let refund = movement(context, kind: "refund", merchant: "متجر الأدوات", amount: 23_000, at: ago(0.1)); refund.reviewState = "needsLook"; refund.toAccountID = account.id
        try context.save()
        let draft = MoneyMessageDraft(id: refund.id, sender: "", title: "t", kindLabel: "", amountMinor: 23_000, currency: "SAR", direction: .incoming, possibleDuplicate: false, note: nil, clear: false, at: now)
        try await app.executeMoneyCommand("money.confirmTransaction", payload: MoneyPhase3Reader.confirmPayload(draft, choice: first.id))
        let fresh = ModelContext(app.container)
        let stored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == refund.id })
        XCTAssertEqual(stored.relatedTransactionID, first.id); XCTAssertEqual(stored.reviewState, "ok")
    }

    func testChargeLinesShowFeesAndTheForeignFigures() async throws {
        let (app, context, root) = try makeSession(); defer { try? FileManager.default.removeItem(at: root) }
        let m = message(context, kind: "purchase", ["feeMinor": 500, "vatMinor": 75, "foreignFeeMinor": 1_125, "exchangeRate": "3.75"])
        let foreign = movement(context, merchant: "متجر خارجي", amount: 10_000, at: ago(0.2)); foreign.currency = "USD"; foreign.homeAmountMinor = 37_500; foreign.rateAtTime = "3.7"; foreign.messageID = m.id
        let plain = movement(context, merchant: "متجر عادي", amount: 5_000, at: ago(0.3))
        try context.save()
        let service = AppMoneyService(app: app)
        let loaded = await service.loadChargeLines(transactionID: foreign.id)
        let lines = try XCTUnwrap(loaded)
        XCTAssertEqual(lines.feeMinor, 500); XCTAssertEqual(lines.vatMinor, 75); XCTAssertEqual(lines.foreignFeeMinor, 1_125)
        XCTAssertTrue(lines.isForeign); XCTAssertEqual(lines.originalCurrency, "USD"); XCTAssertEqual(lines.originalAmountMinor, 10_000)
        XCTAssertEqual(lines.chargeCurrency, "SAR", "banks bill the markup in the home currency")
        XCTAssertEqual(lines.rate, "3.75", "the printed rate wins over Madar's own")
        let none = await service.loadChargeLines(transactionID: plain.id)
        XCTAssertNil(none, "nothing printed, nothing drawn")
    }
}
