import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarInbox
@testable import MadarCommands

@MainActor private final class MoneyFixture {
    let root: URL, container: ModelContainer, bus: CommandBus
    let now = ISO8601DateFormatter().date(from: "2026-10-16T15:00:00+03:00")!
    let bank = UUID(), cash = UUID(), credit = UUID(), debit = UUID()
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MoneyFlow-\(UUID())")
        container = try MadarContainerFactory.makeLocal(at: root)
        bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func run(_ name: String, _ p: [String: MadarCore.JSONValue], id: UUID = UUID(), source: CommandSource = .app, at: Date? = nil) async throws -> CommandOutcome {
        try await bus.execute(.init(commandID: id, name: name, payload: .object(p), source: source, issuedAt: at ?? now), now: now)
    }
    func setup() async throws {
        for (id, kind, balance, last4) in [(bank, "current", 2_000_000, "1111"), (cash, "cash", 10_000, "2222")] {
            #expect(try await run("money.saveAccount", ["id": .string(id.uuidString), "name": .string(kind), "bank": .string("Bank"),
                "kind": .string(kind), "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string(String(balance)),
                "balanceAt": .string("2026-10-14T00:00:00Z"), "last4": .string(last4), "senderIDs": .array([.string("Bank")])]).status == .applied)
        }
        for (id, kind, last4) in [(credit, "credit", "4444"), (debit, "debit", "3333")] {
            #expect(try await run("money.saveCard", ["id": .string(id.uuidString), "name": .string(kind), "bank": .string("Bank"),
                "kind": .string(kind), "last4": .string(last4), "accountID": .string(bank.uuidString)]).status == .applied)
        }
    }
    func ingest(_ text: String, id: UUID = UUID()) async throws -> CommandOutcome {
        try await run("money.ingestBankMessage", ["text": .string(text), "sender": .string("Bank")], id: id, source: .shortcut)
    }
    func transaction(_ id: UUID? = nil) throws -> MoneyTransaction {
        try #require(try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.deletedAt == nil && $0.mergedInto == nil && (id == nil || $0.id == id) })
    }
    func basis() throws -> Basis { try MoneyRepository(context: ModelContext(container)).basis(at: now) }
}

@MainActor struct MoneyPersistenceTests {
    @Test func madaDraftConfirmationReplayAndUndoKeepCashAndDebtSeparate() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let intake = UUID(), confirm = UUID()
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n42.00 SAR\nلدى: Coffee\n2026-10-16 13:05", id: intake)
        let row = try f.transaction(); #expect(row.cardID == f.debit); #expect(row.reviewState == "needsLook")
        #expect(try f.basis().inAccountMinor == 2_010_000)
        let p: [String: MadarCore.JSONValue] = ["id": .string(row.id.uuidString)]
        #expect(try await f.run("money.confirmTransaction", p, id: confirm).status == .applied)
        #expect(try f.basis().inAccountMinor == 2_005_800); #expect(try f.basis().owedMinor == 0)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor) == [-4200])
        _ = try await f.run("money.confirmTransaction", p, id: confirm)
        #expect(try f.basis().inAccountMinor == 2_005_800)
        let undo = try await f.run("system.undo", ["undoToken": .string(confirm.uuidString)])
        #expect(undo.status == .applied); #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        _ = try await f.run("money.confirmTransaction", p, id: confirm)
        #expect(try f.transaction().reviewState == "needsLook", "Receipt replay after undo must not post the purchase again")
    }
    @Test func creditPurchaseAndPaymentAffectEachAxisOnce() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء بطاقة ائتمان\n*4444\n100.00 SAR\n2026-10-16 12:00")
        let purchase = try f.transaction()
        _ = try await f.run("money.confirmTransaction", ["id": .string(purchase.id.uuidString)])
        #expect(try f.basis().inAccountMinor == 2_010_000); #expect(try f.basis().owedMinor == 10_000)
        _ = try await f.ingest("سداد بطاقة\n*4444\n40.00 SAR\n2026-10-16 13:00")
        let payment = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.kind == "cardPayment" })
        _ = try await f.run("money.confirmTransaction", ["id": .string(payment.id.uuidString), "fromAccountID": .string(f.bank.uuidString)])
        #expect(try f.basis().inAccountMinor == 2_006_000); #expect(try f.basis().owedMinor == 6000)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().count == 1)
    }
    @Test func sensitiveMessagesLeaveNoSpoolRowsFingerprintOrReceipt() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let inbox = PendingInbox(directory: f.root.appending(path: "Inbox"))
        let otp = "رمز التحقق 987654 لا تشارك الرمز"
        #expect(try MoneyInboxCommandWriter.ingest(inbox: inbox, text: otp) == nil)
        #expect(!FileManager.default.fileExists(atPath: inbox.directory.path))
        _ = try await f.ingest(otp); _ = try await f.ingest("عرض حصري اشترك الآن")
        let context = ModelContext(f.container)
        #expect(try context.fetchCount(FetchDescriptor<BankMessage>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MoneyTransaction>()) == 0)
        #expect(try await f.run("money.ingestBankMessage", ["text": .string("")], source: .shortcut).status == .rejected)
    }
    @Test func bulkReplayAndLiveOccurrencesPreserveTwoIdenticalPurchases() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let text = "شراء مدى\n*3333\n18.00 SAR\nلدى: Coffee\n2026-10-16 12:00"
        _ = try await f.ingest(text); _ = try await f.ingest(text)
        let message: MadarCore.JSONValue = .object(["text": .string(text), "sender": .string("Bank")])
        let p: [String: MadarCore.JSONValue] = ["messages": .array([message, message])]
        _ = try await f.run("money.pasteBankMessages", p); _ = try await f.run("money.pasteBankMessages", p)
        let context = ModelContext(f.container), rows = try context.fetch(FetchDescriptor<BankMessage>())
        #expect(rows.count == 2); #expect(rows.map(\.occurrence).sorted() == [1, 2])
        #expect(rows.filter { $0.status == "possibleDuplicate" }.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<ImportBatch>()) == 1)
    }
    @Test func timelessBulkIsPreviewedAndBatchReplayDoesNotCreateMoreRows() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let text = "شراء مدى\n*3333\n18.00 SAR\nلدى: Coffee"
        _ = try await f.ingest(text)
        let p: [String: MadarCore.JSONValue] = ["messages": .array([.object(["text": .string(text), "sender": .string("Bank")])])]
        _ = try await f.run("money.pasteBankMessages", p); _ = try await f.run("money.pasteBankMessages", p)
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<BankMessage>())
        #expect(rows.count == 2); #expect(rows.filter { $0.channel == "bulk" }.first?.status == "possibleDuplicate")
    }
    @Test func splitDeleteAndUndoAreAtomicAndExactToTheHalala() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), envelope = Envelope(); envelope.name = "هدف"; context.insert(envelope); try context.save()
        _ = try await f.ingest("شراء مدى\n*3333\n1.00 SAR\n2026-10-16 12:00")
        let row = try f.transaction()
        func split(_ target: String, _ amount: Int, id: UUID? = nil) -> MadarCore.JSONValue {
            var p: [String: MadarCore.JSONValue] = ["target": .string(target), "amountMinor": .number(Double(amount))]
            if let id { p["targetID"] = .string(id.uuidString) }; return .object(p)
        }
        let bad = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "allocations": .array([split("daily", 99)])])
        #expect(bad.status == .rejected); #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        _ = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "allocations": .array([split("daily", 33), split("envelope", 33, id: envelope.id), split("reserve", 34)])])
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor).sorted() == [-34, -33, -33])
        let deletion = UUID(); _ = try await f.run("money.deleteTransaction", ["id": .string(row.id.uuidString)], id: deletion)
        #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        _ = try await f.run("system.undo", ["undoToken": .string(deletion.uuidString)])
        #expect(try f.basis().inAccountMinor == 2_009_900)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().count == 3)
    }
    @Test func twoOwnTransferMessagesBecomeOneNeutralMovement() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("حوالة صادرة\n*1111\n100.00 SAR\n2026-10-16 12:00")
        _ = try await f.ingest("حوالة واردة\n*2222\n100.00 SAR\n2026-10-16 12:01")
        let row = try f.transaction(); #expect(row.fromAccountID == f.bank); #expect(row.toAccountID == f.cash)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.mergedInto == nil }.count == 1)
        _ = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString)])
        #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
    }
    @Test func unknownMadaCardCannotBecomeCreditAndNoSilentCardIsCreated() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء مدى\n*5555\n12.00 SAR\n2026-10-16 12:00")
        let row = try f.transaction(); #expect(row.cardID == nil)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Card>()) == 2)
        let result = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "cardID": .string(f.credit.uuidString)])
        #expect(result.status == .rejected); #expect(result.reason == "cardKindRequired")
        #expect(try f.basis().owedMinor == 0)
    }
    @Test func delayedInboxUsesMessageTimeAndFrozenDayAfterPolicyChanges() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let issued = ISO8601DateFormatter().date(from: "2026-10-15T04:30:00+03:00")!
        _ = try await f.run("money.ingestBankMessage", ["text": .string("شراء مدى\n*3333\n12.00 SAR"), "sender": .string("Bank")], source: .shortcut, at: issued)
        let row = try f.transaction(), key = row.dayKey
        #expect(row.eventAt == issued); #expect(key == "2026-10-14"); #expect(row.dayPolicy == "fajr@1")
        _ = try await f.run("settings.set", ["settings": .object(["core.dayStart": .string("midnight")])])
        #expect(try f.transaction().dayKey == key)
    }
    @Test func foreignOwnedAccountBalancesAreConvertedAndUntrackedWalletStaysOut() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        for (code, tracked, amount) in [("USD", true, 12_34), ("SAR", false, 999_99)] {
            _ = try await f.run("money.saveAccount", ["id": .string(UUID().uuidString), "name": .string("محفظة"), "kind": .string("wallet"),
                "ownership": .string("mine"), "currency": .string(code), "tracked": .bool(tracked), "balanceMinor": .number(Double(amount)), "balanceAt": .string("2026-10-14T00:00:00Z")])
        }
        let repo = MoneyRepository(context: ModelContext(f.container))
        #expect(throws: MoneyCommandError.missingRate) { try repo.basis(at: f.now) }
        #expect(try repo.basis(at: f.now, rates: ["USD": "3.75"]).inAccountMinor == 2_014_628)
        #expect(try repo.zakatAccounts(at: f.now, rates: ["USD": "3.75"]).reduce(0) { $0 + $1.balanceMinor } == 2_014_628)
    }
    @Test func salaryAndUnresolvedExpenseStayDraftAndAppCommandsRejectTransport() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("راتب\n*1111\n15000.00 SAR\n2026-10-16 12:00")
        let salary = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(salary.id.uuidString)]).reason == "salaryNeedsCycleConfirmation")
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Cycle>()) == 0)
        #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try await f.run("money.deleteTransaction", ["id": .string(salary.id.uuidString)], source: .shortcut).status == .needsApp)
        #expect(MoneyCommandPayload.integer(.number(9_007_199_254_740_992)) == nil)
        #expect(MoneyCommandPayload.integer(.string("9007199254740993")) == nil)
    }
    @Test func partialRefundsReturnEveryOriginalAllocationAndHomeHalala() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), envelope = Envelope(); envelope.name = "هدف"; context.insert(envelope); try context.save()
        _ = try await f.ingest("شراء مدى\n*3333\n1.00 SAR\n2026-10-16 11:00")
        let original = try f.transaction()
        let parts: [MadarCore.JSONValue] = [
            .object(["target": .string("daily"), "amountMinor": .number(33)]),
            .object(["target": .string("envelope"), "targetID": .string(envelope.id.uuidString), "amountMinor": .number(33)]),
            .object(["target": .string("reserve"), "amountMinor": .number(34)])]
        _ = try await f.run("money.confirmTransaction", ["id": .string(original.id.uuidString), "allocations": .array(parts)])
        for minute in [10, 20] {
            _ = try await f.ingest("استرداد مدى\n*3333\n0.50 SAR\n2026-10-16 12:\(minute)")
            let refund = try #require(try MoneyRepository(context: ModelContext(f.container)).pendingTransactions().first)
            #expect(try await f.run("money.confirmTransaction", ["id": .string(refund.id.uuidString), "relatedTransactionID": .string(original.id.uuidString)]).status == .applied)
        }
        let repo = MoneyRepository(context: ModelContext(f.container)), allocations = try repo.allocationRows()
        for target in [AllocationTarget.daily, .envelope(envelope.id.uuidString), .reserve] {
            #expect(allocations.filter { $0.target == target }.reduce(0) { $0 + $1.amountMinor } == 0)
        }
        #expect(try repo.basis(at: f.now).inAccountMinor == 2_010_000)
        #expect(try await f.run("money.deleteTransaction", ["id": .string(original.id.uuidString)]).status == .rejected)
    }
    @Test func deletingAnInstalmentPaymentRestoresPaidAndDebtThenUndoRestoresBoth() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), obligation = Obligation(), item = InstallmentItem()
        obligation.kind = "installment"; obligation.provider = "Tamara"; obligation.totalMinor = 120_000
        item.obligationID = obligation.id; item.amountMinor = 40_000; item.dueDate = f.now
        context.insert(obligation); context.insert(item); try context.save()
        _ = try await f.ingest("تمارا قسط\n*1111\n200.00 SAR\n2026-10-16 12:00")
        let row = try f.transaction()
        _ = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "installmentID": .string(item.id.uuidString)])
        #expect(try f.basis().owedMinor == 20_000); #expect(try f.basis().inAccountMinor == 1_990_000)
        let deletion = UUID(); _ = try await f.run("money.deleteTransaction", ["id": .string(row.id.uuidString)], id: deletion)
        #expect(try f.basis().owedMinor == 40_000); #expect(try f.basis().inAccountMinor == 2_010_000)
        _ = try await f.run("system.undo", ["undoToken": .string(deletion.uuidString)])
        #expect(try f.basis().owedMinor == 20_000); #expect(try f.basis().inAccountMinor == 1_990_000)
    }
    @Test func obligationsAreReservedBeforeDueAndPaymentIsBudgetNeutral() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), bill = Obligation(), loan = Obligation(), item = InstallmentItem()
        bill.kind = "bill"; bill.amountMinor = 41_000; bill.dueDay = 25; bill.provider = "001"
        loan.kind = "loan"; loan.amountMinor = 285_000; item.obligationID = loan.id; item.amountMinor = 285_000
        item.dueDate = f.now.addingTimeInterval(2 * 86400)
        context.insert(bill); context.insert(loan); context.insert(item); try context.save()
        #expect(try f.basis().reservedMinor == 326_000); #expect(try f.basis().owedMinor == 0)
        _ = try await f.ingest("سداد فاتورة\n*1111\n410.00 SAR\nالمفوتر: 001\n2026-10-16 12:00")
        let row = try f.transaction(); #expect(row.obligationID == bill.id)
        _ = try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString)])
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        #expect(try f.basis().reservedMinor == 285_000)
    }
    @Test func foreignTransactionDoesNotAffectUnrelatedAccountAndCheckpointCannotBeRebased() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.run("money.logExpense", ["amountMinor": .number(1234), "currency": .string("USD"), "method": .string("card"),
            "cardID": .string(f.debit.uuidString), "rateAtTime": .string("3.75")])
        #expect(try f.basis().inAccountMinor == 2_005_372)
        #expect(try await f.run("settings.set", ["settings": .object(["core.currency": .string("USD")])]).reason == "currencyRequiresMigration")
        let result = try await f.run("money.saveAccount", ["id": .string(f.bank.uuidString), "name": .string("جاري"), "bank": .string("Bank"),
            "kind": .string("current"), "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .number(0), "balanceAt": .string("2026-10-14T00:00:00Z")])
        #expect(result.status == .rejected); #expect(try f.basis().inAccountMinor == 2_005_372)
    }
    @Test func delayedSpoolDrainsOnlyInAppAndReplayDoesNotDuplicateDraft() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let inbox = PendingInbox(directory: f.root.appending(path: "Inbox")), generation = InboxGeneration(generationID: UUID(), acceptsUnstampedDeliveries: true)
        try inbox.publishGeneration(generation)
        let id = UUID(), issued = f.now.addingTimeInterval(-3600)
        try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "شراء مدى\n*3333\n18.00 SAR", sender: "Bank", commandID: id, issuedAt: issued)
        try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "شراء مدى\n*3333\n18.00 SAR", sender: "Bank", commandID: id, issuedAt: issued)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<BankMessage>()) == 0)
        let drainer = InboxDrainer(inbox: inbox, bus: f.bus, generation: { generation }, hasReceipt: { _ in false }, refresh: {})
        #expect(try await drainer.drain(now: f.now))
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<BankMessage>()) == 1)
        #expect(try f.transaction().eventAt == issued)
        #expect(try f.basis().inAccountMinor == 2_010_000)
    }

    @Test func c0BasisUsesSourceRowsWithoutCountingEnvelopesOrLoanTwice() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == f.bank })
        account.balanceMinor = 12_850_000
        let cash = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == f.cash }); cash.balanceMinor = 0
        let statement = Statement(); statement.cardID = f.credit; statement.statementMinor = 680_000
        statement.closeDate = f.now.addingTimeInterval(-86400)
        let unbilled = MoneyTransaction(); unbilled.kind = "expense"; unbilled.method = "card"; unbilled.cardID = f.credit
        unbilled.amountMinor = 180_000; unbilled.homeAmountMinor = 180_000; unbilled.eventAt = f.now; unbilled.reviewState = "ok"
        let bnpl = Obligation(); bnpl.kind = "installment"
        let bnplItem = InstallmentItem(); bnplItem.obligationID = bnpl.id; bnplItem.amountMinor = 120_000
        let loan = Obligation(); loan.kind = "loan"
        let loanItem = InstallmentItem(); loanItem.obligationID = loan.id; loanItem.amountMinor = 285_000; loanItem.dueDate = f.now.addingTimeInterval(86400)
        let bill = Obligation(); bill.kind = "bill"; bill.amountMinor = 41_000; bill.dueDay = 25
        let reserved = Allocation(); reserved.target = "reserve"; reserved.amountMinor = 10_296_000
        context.insert(statement); context.insert(unbilled); context.insert(bnpl); context.insert(bnplItem)
        context.insert(loan); context.insert(loanItem); context.insert(bill); context.insert(reserved); try context.save()
        let basis = try f.basis()
        #expect(basis.inAccountMinor == 12_850_000); #expect(basis.owedMinor == 980_000)
        #expect(basis.netMinor == 11_870_000); #expect(basis.reservedMinor == 10_622_000)
        #expect(basis.unallocatedMinor == 1_248_000)
    }

    @Test func statementRefundAndExcessPaymentShareTheSameDebtSourceTotals() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), statement = Statement()
        statement.cardID = f.credit; statement.statementMinor = 680000; statement.closeDate = f.now.addingTimeInterval(-86400); statement.closeDateSource = "estimated"; c.insert(statement)
        let original = MoneyTransaction(); original.cardID = f.credit; original.kind = "expense"; original.method = "card"; original.amountMinor = 180000; original.homeAmountMinor = 180000; original.eventAt = f.now.addingTimeInterval(-3600); c.insert(original)
        let refund = MoneyTransaction(); refund.cardID = f.credit; refund.kind = "refund"; refund.method = "card"; refund.relatedTransactionID = original.id; refund.amountMinor = 80000; refund.homeAmountMinor = 80000; refund.eventAt = f.now.addingTimeInterval(-1800); c.insert(refund)
        let payment = MoneyTransaction(); payment.cardID = f.credit; payment.kind = "cardPayment"; payment.fromAccountID = f.bank; payment.amountMinor = 700000; payment.homeAmountMinor = 700000; payment.eventAt = f.now; c.insert(payment); try c.save()
        let repo = MoneyRepository(context: ModelContext(f.container)), card = try #require(try repo.cardDebts(at: f.now).first)
        // Statement 680000 covered; overpayment 20000 lowers unbilled 180000 − refund 80000.
        #expect(card.statementLeftMinor == 0); #expect(card.unbilledLeftMinor == 80000); #expect(card.estimatedClose)
        #expect(try repo.basis(at: f.now).owedMinor == 80000)
    }

}
