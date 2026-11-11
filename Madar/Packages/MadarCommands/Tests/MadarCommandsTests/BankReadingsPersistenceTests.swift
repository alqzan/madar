import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

@MainActor private final class ReadingFixture {
    let root: URL, container: ModelContainer, bus: CommandBus
    let now = ISO8601DateFormatter().date(from: "2026-10-16T15:00:00+03:00")!
    let bank = UUID(), wallet = UUID(), debit = UUID(), credit = UUID()
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BankReadings-\(UUID())")
        container = try MadarContainerFactory.makeLocal(at: root)
        bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func run(_ name: String, _ p: [String: MadarCore.JSONValue], id: UUID = UUID(), source: CommandSource = .app) async throws -> CommandOutcome {
        try await bus.execute(.init(commandID: id, name: name, payload: .object(p), source: source, issuedAt: now), now: now)
    }
    func account(_ id: UUID, name: String, bank: String, kind: String, last4: String, balance: Int) async throws {
        #expect(try await run("money.saveAccount", ["id": .string(id.uuidString), "name": .string(name), "bank": .string(bank), "kind": .string(kind),
            "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string(String(balance)), "balanceAt": .string("2026-10-14T00:00:00Z"),
            "last4": .string(last4), "senderIDs": .array([.string(bank)])]).status == .applied)
    }
    func setup() async throws {
        try await account(bank, name: "current", bank: "Bank", kind: "current", last4: "1111", balance: 2_000_000)
        #expect(try await run("money.saveCard", ["id": .string(debit.uuidString), "name": .string("debit"), "bank": .string("Bank"), "kind": .string("debit"),
            "last4": .string("3333"), "accountID": .string(bank.uuidString)]).status == .applied)
    }
    func ingest(_ text: String, sender: String = "Bank") async throws {
        #expect(try await run("money.ingestBankMessage", ["text": .string(text), "sender": .string(sender)], source: .shortcut).status == .applied)
    }
    var context: ModelContext { ModelContext(container) }
    var repo: MoneyRepository { MoneyRepository(context: context) }
}

@MainActor struct BankReadingsPersistenceTests {
    let purchase = "شراء مدى\nبطاقة: 3333*\nمبلغ: 50.00 SAR\nلدى: مطعم وهمي\nالرصيد: 19900.00 SAR\n2026-10-16 12:00"

    @Test func parsedFieldsArePersistedAndOldRowsStillDecode() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(purchase)
        let message = try #require(try f.context.fetch(FetchDescriptor<BankMessage>()).first)
        let fields = try JSONDecoder().decode(MoneyParsedFields.self, from: try #require(message.parsedJSON))
        #expect(fields.balanceMinor == 1_990_000); #expect(fields.last4 == "3333")
        let old = Data(#"{"v":1,"kind":"purchase","amountMinor":5000}"#.utf8)
        let decoded = try JSONDecoder().decode(MoneyParsedFields.self, from: old)
        #expect(decoded.accountLast4 == nil && decoded.availableLimitMinor == nil && decoded.messageKind == .purchase)
    }

    @Test func aPrintedBalanceIsStoredOnceAndOnlyALaterMessageReplacesIt() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(purchase)
        var reading = try #require(try f.context.fetch(FetchDescriptor<BankReading>()).first)
        #expect(reading.accountID == f.bank); #expect(reading.balanceMinor == 1_990_000)
        // An older message arriving later does not replace it.
        try await f.ingest("شراء مدى\nبطاقة: 3333*\nمبلغ: 10.00 SAR\nلدى: مقهى وهمي\nالرصيد: 20500.00 SAR\n2026-10-15 09:00")
        reading = try #require(try f.context.fetch(FetchDescriptor<BankReading>()).first)
        #expect(reading.balanceMinor == 1_990_000)
        try await f.ingest("شراء مدى\nبطاقة: 3333*\nمبلغ: 10.00 SAR\nلدى: مقهى وهمي\nالرصيد: 19890.00 SAR\n2026-10-16 13:00")
        reading = try #require(try f.context.fetch(FetchDescriptor<BankReading>()).first)
        #expect(reading.balanceMinor == 1_989_000)
    }

    @Test func mismatchWaitsForReviewThenIsOneQuietReadingThatSettlesThroughReconcile() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest(purchase)
        // The own draft (-50.00) is unconfirmed: book 20,000.00 + draft = 19,950.00 ≠ 19,900.00 → not settleable yet.
        var found = try f.repo.balanceMismatches(at: f.now)
        #expect(found.count == 1); #expect(found[0].reading.status == .waitingForReview); #expect(!found[0].isSettleable)
        let draft = try #require(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).first)
        #expect(try await f.run("money.confirmTransaction", ["id": .string(draft.id.uuidString)]).status == .applied)
        found = try f.repo.balanceMismatches(at: f.now)
        let m = try #require(found.first)
        #expect(m.reading.status == .open); #expect(m.reading.expectedMinor == 1_995_000); #expect(m.reading.observedMinor == 1_990_000)
        #expect(m.reading.differenceMinor == -5_000); #expect(m.isSettleable); #expect(m.accountID == f.bank)
        let row: MadarCore.JSONValue = .object(["accountID": .string(m.accountID.uuidString), "expectedMinor": .string(String(m.reading.expectedMinor)),
            "observedMinor": .string(String(m.reading.observedMinor)), "at": .string(ISO8601DateFormatter().string(from: m.reading.at)), "name": .string("unexplained")])
        #expect(try await f.run("money.reconcile", ["rows": .array([row])]).status == .applied)
        #expect(try f.repo.balanceMismatches(at: f.now).isEmpty)
        let book = try f.repo.accountBalance(try #require(try f.context.fetch(FetchDescriptor<Account>()).first { $0.id == f.bank }), at: f.now)
        #expect(book == 1_990_000)
    }

    @Test func aDraftThatExplainsTheBalanceIsNotAMismatch() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.ingest("شراء مدى\nبطاقة: 3333*\nمبلغ: 50.00 SAR\nلدى: مطعم وهمي\nالرصيد: 19950.00 SAR\n2026-10-16 12:00")
        #expect(try f.repo.balanceMismatches(at: f.now).isEmpty)
    }

    @Test func anUnknownTailIsAskedOnceAttachedWithUndoAndThenIdentifiesTheDraft() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        for time in ["12:00", "12:30"] { try await f.ingest("شراء مدى Apple Pay\nبطاقة: 7777*\nمبلغ: 20.00 SAR\nلدى: مقهى وهمي\n2026-10-16 \(time)") }
        let questions = try f.repo.unknownTails()
        #expect(questions.count == 1); #expect(questions[0].tail == "7777"); #expect(questions[0].messageIDs.count == 2)
        #expect(questions[0].candidates.contains { $0.id == f.debit && $0.kind == .card })
        #expect(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).allSatisfy { $0.cardID == nil })
        let command = UUID()
        #expect(try await f.run("money.attachTail", ["tail": .string("7777"), "cardID": .string(f.debit.uuidString), "kind": .string("applePay"), "label": .string("iPhone")], id: command).status == .applied)
        #expect(try f.repo.unknownTails().isEmpty)
        let rows = try f.context.fetch(FetchDescriptor<MoneyTransaction>())
        #expect(rows.count == 2 && rows.allSatisfy { $0.cardID == f.debit && $0.fromAccountID == f.bank })
        // A later message of that tail is recognised at intake.
        try await f.ingest("شراء مدى Apple Pay\nبطاقة: 7777*\nمبلغ: 5.00 SAR\nلدى: مخبز وهمي\n2026-10-16 14:00")
        #expect(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.cardID == f.debit }.count == 3)
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try f.context.fetch(FetchDescriptor<AccountTail>()).allSatisfy { $0.deletedAt != nil })
        #expect(try f.repo.unknownTails().count == 1)
    }

    @Test func attachTailRefusesBadOrClashingTails() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        #expect(!MoneyCommandPayload.validate(name: "money.attachTail", payload: ["tail": .string("77"), "cardID": .string(f.debit.uuidString), "kind": .string("card")]))
        #expect(!MoneyCommandPayload.validate(name: "money.attachTail", payload: ["tail": .string("7777"), "kind": .string("card")]))
        #expect(!MoneyCommandPayload.validate(name: "money.attachTail", payload: ["tail": .string("7777"), "cardID": .string(f.debit.uuidString), "accountID": .string(f.bank.uuidString), "kind": .string("card")]))
        #expect(MoneyCommandPayload.validate(name: "money.attachTail", payload: ["tail": .string("7777"), "accountID": .string(f.bank.uuidString), "kind": .string("account")]))
        // The account's own tail, or another subject's tail at the same bank, cannot be attached.
        #expect(try await f.run("money.attachTail", ["tail": .string("1111"), "accountID": .string(f.bank.uuidString), "kind": .string("account")]).status == .rejected)
        #expect(try await f.run("money.attachTail", ["tail": .string("3333"), "accountID": .string(f.bank.uuidString), "kind": .string("account")]).status == .rejected)
        #expect(try await f.run("money.attachTail", ["tail": .string("7777"), "accountID": .string(f.bank.uuidString), "kind": .string("account")]).status == .applied)
        #expect(try await f.run("money.attachTail", ["tail": .string("7777"), "cardID": .string(f.debit.uuidString), "kind": .string("card")]).status == .rejected)
        // An account cannot reuse a tail through saveAccount either.
        #expect(try await f.run("money.saveAccount", ["id": .string(UUID().uuidString), "name": .string("copy"), "bank": .string("Bank"), "kind": .string("current"),
            "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string("0"), "balanceAt": .string("2026-10-14T00:00:00Z"), "last4": .string("7777")]).status == .rejected)
    }

    @Test func aTopUpAndItsDepositAreOneNeutralTransferEvenWhenTheDepositArrivesFirst() async throws {
        for depositFirst in [false, true] {
            let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
            try await f.account(f.wallet, name: "STC Pay", bank: "STC Pay", kind: "wallet", last4: "8888", balance: 0)
            let out = "حوالة داخلية صادرة\nمن1111\nبـSAR 400\nلـ8888;STC Pay\nفي:26-10-16 13:16"
            let deposit = "حوالة محلية واردة\nمبلغ:SAR 400\nالى:8888\nمن:اسم تجريبي\nمن:1111\nفي:26-10-16 13:20"
            if depositFirst { try await f.ingest(deposit, sender: "STC Pay"); try await f.ingest(out) }
            else { try await f.ingest(out); try await f.ingest(deposit, sender: "STC Pay") }
            let live = try f.context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            #expect(live.count == 1)
            let row = try #require(live.first)
            #expect(row.kind == "transfer" && row.fromAccountID == f.bank && row.toAccountID == f.wallet && row.amountMinor == 40_000)
            let pairs = try f.repo.pairedTransfers()
            #expect(pairs.count == 1); #expect(pairs[0].outgoingID == row.id); #expect(pairs[0].toAccountID == f.wallet)
            let basis = try f.repo.basis(at: f.now)
            // Confirmed or not, the move is neutral: only the first pass of the two accounts counts once.
            #expect(basis.inAccountMinor == 2_000_000)
        }
    }

    @Test func aDepositFarFromTheTransferOrOfAnotherAmountStaysSeparate() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.account(f.wallet, name: "STC Pay", bank: "STC Pay", kind: "wallet", last4: "8888", balance: 0)
        try await f.ingest("حوالة داخلية صادرة\nمن1111\nبـSAR 400\nلـ8888;STC Pay\nفي:26-10-16 13:16")
        try await f.ingest("حوالة محلية واردة\nمبلغ:SAR 400\nالى:8888\nمن:اسم تجريبي\nمن:1111\nفي:26-10-16 14:00", sender: "STC Pay")
        try await f.ingest("حوالة محلية واردة\nمبلغ:SAR 401\nالى:8888\nمن:اسم تجريبي\nمن:1111\nفي:26-10-16 13:17", sender: "STC Pay")
        #expect(try f.repo.pairedTransfers().isEmpty)
    }

    @Test func billAndReminderNoticesBecomeDuesSortedByDateAndAPaymentClosesOne() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        func tamara(_ amount: String, _ when: String) async throws {
            #expect(try await f.run("money.ingestBankMessage", ["text": .string("دفعة قادمة بقيمة \(amount) SAR لطلبك من متجر وهمي مستحقة خلال يومين. سددها الحين: https://tmra.pe/abc"), "sender": .string("Tamara"), "receivedAt": .string(when)], source: .shortcut).status == .applied)
        }
        try await tamara("90.00", "2026-10-16T09:00:00+03:00")
        try await tamara("90.00", "2026-10-16T09:05:00+03:00")        // a repeat of the same reminder: one due
        try await tamara("120.00", "2026-10-16T10:00:00+03:00")
        #expect(try await f.run("money.ingestBankMessage", ["text": .string("تم إصدار فاتورتك والمبلغ المطلوب 50.00 ريال\nتاريخ الاستحقاق: 2026-10-20"), "sender": .string("Bills")], source: .shortcut).status == .applied)
        var dues = try f.repo.upcomingDues()
        #expect(dues.count == 3); #expect(dues.map(\.amountMinor) == [9_000, 12_000, 5_000])
        #expect(dues.map(\.payee) == ["Tamara", "Tamara", "Bills"])
        #expect(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).isEmpty, "A due is never an expense")
        // The Tamara payment confirmation for the same amount closes the earlier 90.00 due.
        #expect(try await f.run("money.ingestBankMessage", ["text": .string("تأكيد الدفع\nمن: Example Store\nبقيمة: 90.00 SAR\nفي: 16/10/2026"), "sender": .string("Tamara"), "receivedAt": .string("2026-10-16T14:00:00+03:00")], source: .shortcut).status == .applied)
        dues = try f.repo.upcomingDues()
        #expect(dues.map(\.amountMinor) == [12_000, 5_000])
        let closed = try f.repo.upcomingDues(includeClosed: true).first { $0.amountMinor == 9_000 }
        let payment = try #require(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).first)
        #expect(closed?.closedByTransactionID == payment.id)
        // Deleting that payment draft opens the due again.
        #expect(try await f.run("money.deleteTransaction", ["id": .string(payment.id.uuidString)]).status == .applied)
        #expect(try f.repo.upcomingDues().map(\.amountMinor) == [9_000, 12_000, 5_000])
        // Dismissing is a tombstone and is undoable.
        let command = UUID(), target = try #require(try f.repo.upcomingDues().last)
        #expect(try await f.run("money.dismissDue", ["id": .string(target.id.uuidString)], id: command).status == .applied)
        #expect(try f.repo.upcomingDues().count == 2)
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try f.repo.upcomingDues().count == 3)
    }

    @Test func aStrangersAccountTailNeverBecomesAnOwnTransferButAnUnnamedUniqueOwnedTailLinksUnderReview() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        try await f.account(f.wallet, name: "STC Pay", bank: "STC Pay", kind: "wallet", last4: "8888", balance: 0)
        // The destination tail equals our wallet's, but the printed name is another party's: external, not ours.
        try await f.ingest("حوالة داخلية صادرة\nمن1111\nبـSAR 400\nلـ8888;شخص غريب\nفي:26-10-16 13:16")
        var row = try #require(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).first)
        #expect(row.fromAccountID == f.bank); #expect(row.toAccountID == nil)
        // The wallet's own name matches: linked.
        try await f.ingest("حوالة داخلية صادرة\nمن1111\nبـSAR 300\nلـ8888;STC Pay\nفي:26-10-16 13:30")
        row = try #require(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == 30_000 })
        #expect(row.toAccountID == f.wallet)
        // No printed name at all: one owned account has the tail, so it links, and the draft stays under review.
        try await f.ingest("تحويل بين حساباتي\nبـ:100.00 ر.س\nمن: ***1111\nإلى: ***8888\nفي:16/10/26 14:09")
        row = try #require(try f.context.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == 10_000 })
        #expect(row.toAccountID == f.wallet); #expect(row.reviewState != "ok")
    }

    @Test func aDismissedDueIsNeverRecreatedOrClosedByALaterPayment() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        func tamara(_ text: String, _ when: String) async throws {
            #expect(try await f.run("money.ingestBankMessage", ["text": .string(text), "sender": .string("Tamara"), "receivedAt": .string(when)], source: .shortcut).status == .applied)
        }
        try await tamara("دفعة قادمة بقيمة 90.00 SAR لطلبك من متجر وهمي مستحقة خلال يومين. سددها الحين: https://tmra.pe/abc", "2026-10-14T09:00:00+03:00")
        let due = try #require(try f.repo.upcomingDues().first)
        #expect(try await f.run("money.dismissDue", ["id": .string(due.id.uuidString)]).status == .applied)
        try await tamara("دفعتك بقيمة 90.00 SAR لطلبك من متجر وهمي مستحقة اليوم. ادفع الحين https://tmra.pe/abc", "2026-10-16T09:00:00+03:00")
        try await tamara("تأكيد الدفع\nمن: Example Store\nبقيمة: 90.00 SAR\nفي: 16/10/2026", "2026-10-16T11:00:00+03:00")
        #expect(try f.repo.upcomingDues(includeClosed: true).isEmpty)
        let stored = try f.context.fetch(FetchDescriptor<UpcomingDue>())
        #expect(stored.count == 1); #expect(stored[0].deletedAt != nil); #expect(stored[0].closedByTransactionID == nil)
    }

    @Test func aPaymentWhoseMessageHasOnlyOldParsedFieldsStillClosesAfterIntakeWithoutThrowing() async throws {
        let f = try ReadingFixture(); defer { f.clean() }; try await f.setup()
        let context = f.context
        let announced = f.now.addingTimeInterval(-86_400)
        let notice = BankMessage(); notice.sender = "Bills"; notice.receivedAt = announced; notice.kind = "marketing"; notice.status = "ok"
        context.insert(notice)
        let due = UpcomingDue(); due.payee = "Bills"; due.amountMinor = 5_000; due.currency = "SAR"; due.dueAt = f.now.addingTimeInterval(86_400)
        due.sourceMessageID = notice.id; due.createdAt = announced
        context.insert(due)
        let message = BankMessage(); message.sender = "Bills"; message.receivedAt = f.now.addingTimeInterval(-3_600); message.kind = "billPayment"; message.status = "needsLook"
        message.parsedJSON = Data(#"{"v":1,"kind":"billPayment","amountMinor":5000,"currency":"SAR"}"#.utf8)
        context.insert(message)
        let payment = MoneyTransaction(); payment.kind = "billPayment"; payment.amountMinor = 5_000; payment.homeAmountMinor = 5_000; payment.currency = "SAR"
        payment.messageID = message.id; payment.reviewState = "needsLook"; payment.eventAt = f.now.addingTimeInterval(-3_600); payment.dayKey = "2026-10-16"
        context.insert(payment); try context.save()
        try await f.ingest("شراء مدى\nبطاقة: 3333*\nمبلغ: 5.00 SAR\nلدى: مخبز وهمي\n2026-10-16 14:00")
        #expect(try f.repo.upcomingDues().isEmpty)
        #expect(try f.repo.upcomingDues(includeClosed: true).first?.closedByTransactionID == payment.id)
    }
}
