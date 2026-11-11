import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

@MainActor private final class P3Fixture {
    let root: URL, container: ModelContainer, bus: CommandBus
    let now = ISO8601DateFormatter().date(from: "2026-10-16T15:00:00+03:00")!
    let bank = UUID(), debit = UUID()
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "PhaseThree-\(UUID())")
        container = try MadarContainerFactory.makeLocal(at: root)
        bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    @discardableResult func run(_ name: String, _ p: [String: MadarCore.JSONValue], source: CommandSource = .app) async throws -> CommandOutcome {
        try await bus.execute(.init(commandID: UUID(), name: name, payload: .object(p), source: source, issuedAt: now), now: now)
    }
    func setup() async throws {
        #expect(try await run("money.saveAccount", ["id": .string(bank.uuidString), "name": .string("current"), "bank": .string("Bank"), "kind": .string("current"),
            "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string("2000000"), "balanceAt": .string("2026-10-01T00:00:00Z"),
            "last4": .string("1111"), "senderIDs": .array([.string("Bank")])]).status == .applied)
        #expect(try await run("money.saveCard", ["id": .string(debit.uuidString), "name": .string("debit"), "bank": .string("Bank"), "kind": .string("debit"),
            "last4": .string("3333"), "accountID": .string(bank.uuidString)]).status == .applied)
    }
    func ingest(_ text: String, sender: String = "Bank") async throws {
        #expect(try await run("money.ingestBankMessage", ["text": .string(text), "sender": .string(sender)], source: .shortcut).status == .applied)
    }
    var context: ModelContext { ModelContext(container) }
    var repo: MoneyRepository { MoneyRepository(context: context) }
    func rows(_ kind: String) throws -> [MoneyTransaction] { try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.kind == kind }.sorted { $0.eventAt < $1.eventAt } }
    func confirm(_ row: MoneyTransaction) async throws { #expect(try await run("money.confirmTransaction", ["id": .string(row.id.uuidString)]).status == .applied) }
    func purchase(_ merchant: String, _ amount: String, _ when: String) -> String { "شراء مدى\nبطاقة: 3333*\nمبلغ: \(amount) SAR\nلدى: \(merchant)\n\(when)" }
    func refund(_ merchant: String, _ amount: String, _ when: String) -> String { "استرداد مبلغ\nبطاقة *3333\nمبلغ: \(amount) SAR\nمن: \(merchant)\n\(when)" }
}

@MainActor struct PhaseThreePersistenceTests {
    @Test func aStatementBecomesAnUpcomingDueAndOnlyAFullCardPaymentClosesIt() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest("كشف حساب البطاقة *3333\nالمبلغ المستحق: 6,800.00 SAR\nالحد الأدنى: 340.00 SAR\nتاريخ الاستحقاق: 2026-11-05")
        var dues = try f.repo.upcomingDues()
        let due = try #require(dues.first)
        #expect(dues.count == 1 && due.isStatement && due.payee == "Bank 3333" && due.amountMinor == 680_000)
        #expect(due.minimumDueMinor == 34_000 && due.cardLast4 == "3333" && due.dueAt != nil)
        // The statement message itself stays in review for `money.applyStatement`; it is not a movement.
        #expect(try f.context.fetch(FetchDescriptor<BankMessage>()).first?.status == "needsLook")
        #expect(try f.rows("expense").isEmpty && f.rows("cardPayment").isEmpty)
        try await f.ingest("سداد بطاقة ائتمانية *3333\nمبلغ: 340.00 SAR")
        #expect(try f.repo.upcomingDues().count == 1)   // the minimum leaves it open
        try await f.ingest("سداد بطاقة ائتمانية *3333\nمبلغ: 6,800.00 SAR")
        dues = try f.repo.upcomingDues()
        #expect(dues.isEmpty)
        #expect(try f.repo.upcomingDues(includeClosed: true).first?.closedByTransactionID != nil)
    }

    @Test func aRefundLinksToItsOnePurchaseAndConfirmNetsIt() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("SQ *STARBUCKS 12", "40.00", "2026-10-10 12:00"))
        let purchase = try #require(try f.rows("expense").first); try await f.confirm(purchase)
        try await f.ingest(f.refund("ستاربكس", "40.00", "2026-10-16 12:00"))
        let refund = try #require(try f.rows("refund").first)
        #expect(refund.relatedTransactionID == purchase.id && refund.reviewState != "ok")
        let found = try f.repo.refundOriginals(forRefund: refund.id)
        #expect(found.suggested == purchase.id && found.candidates == [purchase.id])   // the read agrees with the intake link
        try await f.confirm(refund)
        #expect(try f.rows("refund").first?.reviewState == "ok")
    }

    @Test func twoIdenticalPurchasesLeaveARefundUnlinkedWithBothAsCandidates() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Starbucks", "40.00", "2026-10-10 12:00"))
        try await f.ingest(f.purchase("Starbucks #7", "40.00", "2026-10-12 12:00"))
        for row in try f.rows("expense") { try await f.confirm(row) }
        try await f.ingest(f.refund("STARBUCKS", "40.00", "2026-10-16 12:00"))
        let refund = try #require(try f.rows("refund").first)
        #expect(refund.relatedTransactionID == nil)
        let found = try f.repo.refundOriginals(forRefund: refund.id)
        #expect(found.suggested == nil && found.candidates.count == 2)
        let newest = try #require(try f.rows("expense").last)
        #expect(found.candidates.first == newest.id)
    }

    @Test func aRefundStillInReviewDoesNotUseUpThePurchaseForTheNextRefund() async throws {
        // One definition of «already refunded»: confirmed refunds only, in the suggestion as in the confirm path.
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Starbucks", "40.00", "2026-10-10 12:00"))
        let purchase = try #require(try f.rows("expense").first); try await f.confirm(purchase)
        try await f.ingest(f.refund("STARBUCKS", "40.00", "2026-10-15 12:00"))
        try await f.ingest(f.refund("STARBUCKS", "40.00", "2026-10-16 12:00"))
        let refunds = try f.rows("refund")
        #expect(refunds.count == 2 && refunds.allSatisfy { $0.reviewState != "ok" })
        // The first draft is linked but unconfirmed: the second refund can still be the purchase's.
        #expect(try f.repo.refundOriginals(forRefund: refunds[1].id).candidates == [purchase.id])
        try await f.confirm(refunds[0])
        #expect(try f.repo.refundOriginals(forRefund: refunds[1].id).candidates.isEmpty)
    }

    @Test func pastedRelativeRemindersStayUndatedAndInstalmentsOfOneAmountStayApart() async throws {
        // D5: a pasted message has no arrival time, so «غدًا» gets no date; the shortcut's stated arrival time dates it.
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        func reminder(_ n: Int) -> MadarCore.JSONValue {
            .object(["text": .string("دفعة قادمة بقيمة 125.00 ريال لطلبك من متجر وهمي مستحقة غدا\nالقسط \(n) من 4\ntamara"), "sender": .string("Tamara")])
        }
        #expect(try await f.run("money.pasteBankMessages", ["messages": .array([reminder(2), reminder(3)])]).status == .applied)
        var dues = try f.repo.upcomingDues()
        #expect(dues.count == 2 && dues.allSatisfy { $0.dueAt == nil && $0.amountMinor == 12_500 })
        // The same reminder pasted again (another paste) is the same due.
        #expect(try await f.run("money.pasteBankMessages", ["messages": .array([reminder(2), .object(["text": .string("نص آخر لا يخص المال"), "sender": .string("x")])])]).status == .applied)
        #expect(try f.repo.upcomingDues().count == 2)
        // With a stated arrival time the reminder is dated: arrival day + 1.
        #expect(try await f.run("money.ingestBankMessage", ["text": .string("دفعة قادمة بقيمة 90.00 ريال لطلبك من متجر وهمي مستحقة غدا\ntamara"), "sender": .string("Tamara"),
                                                           "receivedAt": .string("2026-10-14T09:00:00+03:00")], source: .shortcut).status == .applied)
        dues = try f.repo.upcomingDues()
        let dated = try #require(dues.first { $0.amountMinor == 9_000 })
        #expect(dated.dueAt == ISO8601DateFormatter().date(from: "2026-10-15T09:00:00+03:00"))
        // The same reminder text pasted later (no sender, no arrival time) is that due, not a second, undated one.
        #expect(try await f.run("money.pasteBankMessages", ["messages": .array([.object(["text": .string("دفعة قادمة بقيمة 90.00 ريال لطلبك من متجر وهمي مستحقة غدا\ntamara"), "sender": .string("Tamara")]),
                                                                              .object(["text": .string("نص ثالث لا يخص المال"), "sender": .string("x")])])]).status == .applied)
        #expect(try f.repo.upcomingDues().filter { $0.amountMinor == 9_000 }.count == 1)
    }

    /// True when the command did not apply, whether it was rejected or threw.
    private func refused(_ f: P3Fixture, _ id: UUID, _ target: UUID?) async -> Bool {
        let payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "relatedTransactionID": target.map { .string($0.uuidString) } ?? .null]
        guard let outcome = try? await f.run("money.linkRefund", payload) else { return true }
        return outcome.status != .applied
    }

    @Test func theChosenPurchaseIsSavedOnTheRefundDraftAndClearable() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Starbucks", "40.00", "2026-10-10 12:00"))
        try await f.ingest(f.purchase("Starbucks #7", "40.00", "2026-10-12 12:00"))
        for row in try f.rows("expense") { try await f.confirm(row) }
        try await f.ingest(f.refund("STARBUCKS", "40.00", "2026-10-16 12:00"))
        let refund = try #require(try f.rows("refund").first)
        let older = try #require(try f.rows("expense").first)
        #expect(refund.relatedTransactionID == nil)   // two identical candidates: nothing chosen yet
        #expect(try await f.run("money.linkRefund", ["id": .string(refund.id.uuidString), "relatedTransactionID": .string(older.id.uuidString)]).status == .applied)
        #expect(try f.rows("refund").first?.relatedTransactionID == older.id && f.rows("refund").first?.reviewState != "ok")
        #expect(try f.repo.refundOriginals(forRefund: refund.id).candidates.contains(older.id))
        // A null value and an omitted key both clear it.
        #expect(try await f.run("money.linkRefund", ["id": .string(refund.id.uuidString), "relatedTransactionID": .null]).status == .applied)
        #expect(try f.rows("refund").first?.relatedTransactionID == nil)
        #expect(try await f.run("money.linkRefund", ["id": .string(refund.id.uuidString), "relatedTransactionID": .string(older.id.uuidString)]).status == .applied)
        #expect(try await f.run("money.linkRefund", ["id": .string(refund.id.uuidString)]).status == .applied)
        #expect(try f.rows("refund").first?.relatedTransactionID == nil)
        // Leaving the screen loses nothing: confirm with no payload uses the saved link.
        #expect(try await f.run("money.linkRefund", ["id": .string(refund.id.uuidString), "relatedTransactionID": .string(older.id.uuidString)]).status == .applied)
        try await f.confirm(refund)
        #expect(try f.rows("refund").first?.reviewState == "ok" && f.rows("refund").first?.relatedTransactionID == older.id)
    }

    @Test func aRefundLinkToAnUnfitTargetOrANonRefundRowIsRefused() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Starbucks", "30.00", "2026-10-10 12:00"))      // smaller than the refund below
        try await f.ingest(f.purchase("Costa", "60.00", "2026-10-11 12:00"))          // stays in review
        try await f.ingest(f.purchase("Gone", "60.00", "2026-10-12 12:00"))           // confirmed, then deleted
        let small = try #require(try f.rows("expense").first { $0.merchant == "Starbucks" })
        let unconfirmed = try #require(try f.rows("expense").first { $0.merchant == "Costa" })
        let deleted = try #require(try f.rows("expense").first { $0.merchant == "Gone" })
        try await f.confirm(small); try await f.confirm(deleted)
        #expect(try await f.run("money.deleteTransaction", ["id": .string(deleted.id.uuidString)]).status == .applied)
        try await f.ingest(f.refund("Starbucks", "40.00", "2026-10-16 12:00"))
        let refund = try #require(try f.rows("refund").first)
        #expect(await refused(f, refund.id, small.id))            // 40.00 is above the 30.00 that is left
        #expect(await refused(f, refund.id, unconfirmed.id))      // not a confirmed expense
        #expect(await refused(f, refund.id, deleted.id))          // deleted
        #expect(await refused(f, refund.id, UUID()))              // unknown
        #expect(await refused(f, refund.id, refund.id))           // itself
        #expect(try f.rows("refund").first?.relatedTransactionID == nil)
        // Only a refund still in review accepts a link.
        #expect(await refused(f, unconfirmed.id, small.id))
        #expect(await refused(f, small.id, nil))
    }

    @Test func aConfirmedRefundKeepsItsLinkAndRefusesAnotherOne() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Starbucks", "40.00", "2026-10-10 12:00"))
        let purchase = try #require(try f.rows("expense").first); try await f.confirm(purchase)
        try await f.ingest(f.refund("Starbucks", "15.00", "2026-10-16 12:00"))
        let refund = try #require(try f.rows("refund").first); try await f.confirm(refund)
        #expect(await refused(f, refund.id, nil))
        #expect(try f.rows("refund").first?.relatedTransactionID == purchase.id)
    }

    @Test func aDifferentMerchantOrCardIsNeverLinked() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(f.purchase("Costa", "40.00", "2026-10-10 12:00"))
        try await f.confirm(try #require(try f.rows("expense").first))
        try await f.ingest(f.refund("Starbucks", "40.00", "2026-10-16 12:00"))
        #expect(try f.rows("refund").first?.relatedTransactionID == nil)
    }

    @Test func feesVatAndForeignDetailsAreExposedPerTransactionAndAsTotals() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest("POS International Purchases:\nVisa card: **3333\nAmount: 10.00 EUR (45.00 SAR)\nExchange Rate ≈ 4.5000\nFX Markup: 1.20 SAR\nAt: EXAMPLE SHOP\nOn: 2026-10-14 10:00")
        try await f.ingest(f.purchase("مقهى وهمي", "50.00", "2026-10-15 12:00"))
        for row in try f.context.fetch(FetchDescriptor<MoneyTransaction>()) { try await f.confirm(row) }
        let foreign = try #require(try f.rows("expense").first { $0.currency == "EUR" })
        let detail = try #require(try f.repo.charges(forTransactions: [foreign.id])[foreign.id])
        #expect(detail.isForeign && detail.originalAmountMinor == 1_000 && detail.originalCurrency == "EUR")
        #expect(detail.homeAmountMinor == 4_500 && detail.homeCurrency == "SAR" && detail.rateAtTime != nil && detail.printedRate == "4.5000")
        #expect(detail.charges.foreignFeeMinor == 120 && detail.charges.totalMinor == 120 && detail.chargeCurrency == "SAR")
        let totals = try f.repo.chargeTotals(from: ISO8601DateFormatter().date(from: "2026-10-01T00:00:00+03:00")!, to: f.now)
        #expect(totals == [.init(currency: "SAR", charges: .init(foreignFeeMinor: 120), transactionCount: 1)])
    }

    @Test func recurringChargesAreDerivedFromConfirmedBankExpenses() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        for day in ["2026-07-17", "2026-08-17", "2026-09-17"] { try await f.ingest(f.purchase("PAYPAL *NETFLIX.COM", "39.00", "\(day) 12:00")) }
        // Another merchant: only two charges, not a pattern.
        for day in ["2026-08-05", "2026-09-05"] { try await f.ingest(f.purchase("Costa", "20.00", "\(day) 12:00")) }
        for row in try f.context.fetch(FetchDescriptor<MoneyTransaction>()) { try await f.confirm(row) }
        let rows = try f.repo.recurringCharges(now: f.now)
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.kind == .subscription && row.series.key == "netflix" && row.series.cadence == .monthly)
        #expect(row.series.amountMinor == 3_900 && row.series.count == 3 && !row.isTracked && row.series.priceChange == nil)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        #expect(row.series.nextExpectedAt == calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)))
        #expect(row.series.status == .upcoming)
    }

    @Test func variantMerchantNamesShareOneRuleAndOneLearnedCategory() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        let cat = MadarData.Category(); cat.name = "قهوة"
        let setup = f.context; setup.insert(cat); try setup.save()
        try await f.run("money.saveMerchantRule", ["merchant": .string("Starbucks"), "categoryID": .string(cat.id.uuidString), "ignore": .bool(false)])
        try await f.run("money.saveMerchantRule", ["merchant": .string("SQ *STARBUCKS #12"), "categoryID": .string(cat.id.uuidString), "ignore": .bool(true)])
        let rules = try f.context.fetch(FetchDescriptor<MerchantRule>()).filter { $0.deletedAt == nil }
        #expect(rules.count == 1 && rules[0].ignore)   // the second save updated the first: one merchant, one rule
        try await f.ingest(f.purchase("ستاربكس", "30.00", "2026-10-15 12:00"))
        #expect(try f.rows("expense").first?.ignoredFromBudget == true)
        #expect(try f.repo.merchantRule(for: "Starbucks 99")?.id == rules[0].id)
    }

    @Test func instalmentPlansReadTheCountOnlyWhereMessagesPrintedIt() async throws {
        let f = try P3Fixture(); defer { f.clean() }; try await f.setup()
        try await f.run("money.ingestBankMessage", ["text": .string("دفعة قادمة بقيمة 125.00 SAR لطلبك من نون مستحقة خلال يومين\nالقسط 2 من 4\nالمبلغ المتبقي: 250.00 SAR"),
                                                    "sender": .string("Tamara"), "receivedAt": .string("2026-10-16T10:00:00+03:00")], source: .shortcut)
        let plans = try f.repo.instalmentPlans(now: f.now)
        let plan = try #require(plans.first)
        #expect(plans.count == 1 && plan.provider == "Tamara" && plan.openCount == 1 && plan.nextAmountMinor == 12_500)
        #expect(plan.printedCount == 4 && plan.remainingMinor == 25_000 && plan.paidCount == 0 && plan.remainingCount == 4)
        let due = try #require(try f.repo.upcomingDues().first)
        #expect(due.instalmentNumber == 2 && due.instalmentCount == 4 && due.remainingMinor == 25_000)
    }
}
