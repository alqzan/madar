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
    /// F06/F02: 100 halalas split 33/33/34, with 40 then 30 refunded. The stamp
    /// changes budgets only, survives relaunch, restores the split, and is undoable.
    @Test func budgetStampRestoresSplitAndRefundsWithoutChangingCashOrDebt() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), envelope = Envelope(); c.insert(envelope); try c.save()
        _ = try await f.ingest("شراء مدى\n*3333\n1.00 SAR\n2026-10-16 12:00")
        let original = try f.transaction()
        let parts: [MadarCore.JSONValue] = [("daily", 33), ("envelope", 33), ("reserve", 34)].map { target, amount in
            var p: [String: MadarCore.JSONValue] = ["target": .string(target), "amountMinor": .number(Double(amount))]
            if target == "envelope" { p["targetID"] = .string(envelope.id.uuidString) }; return .object(p)
        }
        #expect(try await f.run("money.confirmTransaction", ["id": .string(original.id.uuidString), "allocations": .array(parts)]).status == .applied)
        func refund(_ amount: Int) async throws -> UUID {
            let context = ModelContext(f.container), row = MoneyTransaction()
            row.kind = "refund"; row.amountMinor = amount; row.currency = "SAR"; row.homeCurrency = "SAR"
            row.cardID = f.debit; row.toAccountID = f.bank; row.eventAt = f.now.addingTimeInterval(-Double(amount)); row.dayKey = "2026-10-16"; row.reviewState = "needsLook"
            context.insert(row); try context.save()
            #expect(try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "relatedTransactionID": .string(original.id.uuidString)]).status == .applied)
            return row.id
        }
        _ = try await refund(40)
        let before = try f.basis(), command = UUID()
        func stamp(_ excluded: Bool, expected: Bool, id: UUID = UUID()) async throws -> CommandOutcome {
            try await f.run("money.setBudgetExclusion", ["id": .string(original.id.uuidString), "excluded": .bool(excluded), "expectedExcluded": .bool(expected)], id: id)
        }
        #expect(try await stamp(true, expected: false, id: command).status == .applied)
        #expect(try f.basis().inAccountMinor == before.inAccountMinor)
        #expect(try f.basis().owedMinor == before.owedMinor)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        #expect(try await stamp(true, expected: false, id: command).status == .applied, "Receipt replay")
        #expect(try await stamp(false, expected: false).status == .rejected, "Stale sheet")
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor).sorted() == [-34, -33, -33, 13, 13, 14])
        #expect(try await stamp(true, expected: false).status == .applied)
        let second = try await refund(30)
        #expect(try f.transaction(second).ignoredFromBudget)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().isEmpty)
        let cash = try f.basis().inAccountMinor
        #expect(try await stamp(false, expected: true).status == .applied)
        #expect(try f.basis().inAccountMinor == cash)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor).sorted() == [-34, -33, -33, 10, 10, 10, 13, 13, 14])
        #expect(try await stamp(true, expected: false).status == .applied)
        #expect(try await stamp(false, expected: true).status == .applied, "Repeated lift reuses natural keys")
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Allocation>()).count == 9)
    }
    @Test func liftingIntakeStampUsesDailyDefaultAndRejectsNeutralTransfers() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء مدى\n*3333\n1.00 SAR\n2026-10-16 12:00")
        let row = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "ignoredFromBudget": .bool(true)]).status == .applied)
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(row.id.uuidString), "excluded": .bool(false), "expectedExcluded": .bool(true)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor) == [-100])
        let c = ModelContext(f.container), transfer = MoneyTransaction(); transfer.kind = "transfer"; transfer.fromAccountID = f.bank; transfer.toAccountID = f.cash
        transfer.amountMinor = 100; transfer.homeAmountMinor = 100; c.insert(transfer); try c.save()
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(transfer.id.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false)]).status == .rejected)
        #expect(!MoneyCommandPayload.validate(name: "money.setBudgetExclusion", payload: ["id": .string(row.id.uuidString), "excluded": .bool(true)]))
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(row.id.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false)], source: .shortcut).status != .applied)
    }
    @Test func budgetStampKeepsRepeatedSplitTargetsAndRefusesUndoAfterLaterRefund() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء مدى\n*3333\n1.00 SAR\n2026-10-16 12:00")
        let original = try f.transaction()
        let part: MadarCore.JSONValue = .object(["target": .string("daily"), "amountMinor": .number(50)])
        #expect(try await f.run("money.confirmTransaction", ["id": .string(original.id.uuidString), "allocations": .array([part, part])]).status == .applied)
        func refund(_ amount: Int) async throws {
            let c = ModelContext(f.container), row = MoneyTransaction()
            row.kind = "refund"; row.amountMinor = amount; row.cardID = f.debit; row.toAccountID = f.bank
            row.eventAt = f.now.addingTimeInterval(-Double(amount)); row.dayKey = "2026-10-16"; row.reviewState = "needsLook"; c.insert(row); try c.save()
            #expect(try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString), "relatedTransactionID": .string(original.id.uuidString)]).status == .applied)
        }
        try await refund(40)
        let command = UUID()
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(original.id.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false)], id: command).status == .applied)
        try await refund(20)
        await #expect(throws: MoneyCommandError.undoSuperseded) { try await f.run("system.undo", ["undoToken": .string(command.uuidString)]) }
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(original.id.uuidString), "excluded": .bool(false), "expectedExcluded": .bool(true)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor).sorted() == [-50, -50, 10, 10, 20, 20])
        // A further refund after lifting also honours the two distinct slots for the same target.
        try await refund(20)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().map(\.amountMinor).sorted() == [-50, -50, 10, 10, 10, 10, 20, 20])
    }
    @Test func budgetStampKeepsCreditDebtAndRefusesAClosedCycle() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء بطاقة ائتمانية\n*4444\n1.00 SAR\n2026-10-16 12:00")
        let original = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(original.id.uuidString)]).status == .applied)
        let before = try f.basis()
        #expect(before.owedMinor == 100)
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(original.id.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false)]).status == .applied)
        #expect(try f.basis().owedMinor == before.owedMinor)
        #expect(try f.basis().inAccountMinor == before.inAccountMinor)
        let c = ModelContext(f.container), cycle = Cycle(); cycle.start = f.now.addingTimeInterval(-86400); cycle.end = f.now; cycle.closedAt = f.now; c.insert(cycle)
        let row = try #require(try c.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == original.id }); row.cycleID = cycle.id; try c.save()
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(original.id.uuidString), "excluded": .bool(false), "expectedExcluded": .bool(true)]).status == .rejected)
        #expect(try f.transaction(original.id).ignoredFromBudget)
    }
    @Test func savingEditKeepsRepaymentAndPastAllocationsAndUndoIntact() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let context = ModelContext(f.container), envelope = Envelope(), fund = EnvelopePlan(), repay = EnvelopePlan()
        context.insert(envelope)
        fund.envelopeID = envelope.id; fund.perPaycheckMinor = 50_000; context.insert(fund)
        repay.envelopeID = envelope.id; repay.kind = "repay"; repay.perPaycheckMinor = 50_000; context.insert(repay)
        let allocation = Allocation(); allocation.target = "envelope"; allocation.targetID = envelope.id; allocation.amountMinor = -100_000; allocation.idempotencyKey = "opening"; context.insert(allocation)
        try context.save()
        let command = UUID()
        #expect(try await f.run("money.setEnvelopeSaving", ["id": .string(fund.id.uuidString), "amountMinor": .string("70000"), "expectedMinor": .string("50000")], id: command).status == .applied)
        #expect(try await f.run("money.setEnvelopeSaving", ["id": .string(fund.id.uuidString), "amountMinor": .string("80000"), "expectedMinor": .string("50000")]).status == .rejected)
        let after = try ModelContext(f.container).fetch(FetchDescriptor<EnvelopePlan>())
        #expect(after.first { $0.id == fund.id }?.perPaycheckMinor == 70_000)
        #expect(after.first { $0.id == repay.id }?.perPaycheckMinor == 50_000)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Allocation>()).count == 1)
        #expect(try await f.run("money.setEnvelopeSaving", ["id": .string(repay.id.uuidString), "amountMinor": .string("1"), "expectedMinor": .string("50000")]).status == .rejected)
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<EnvelopePlan>()).first { $0.id == fund.id }?.perPaycheckMinor == 50_000)
    }
    /// L03 / M5-V04: adopting «سدّه على راتبين» stores the debt and count beside, never over, the saving plan.
    @Test func adoptedRepaymentStoresTotalAndCountReplacesOnlyARepayPlanAndUndoes() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let context = ModelContext(f.container), envelope = Envelope(), fund = EnvelopePlan(), oldRepay = EnvelopePlan()
        envelope.name = "سفر"; context.insert(envelope)
        fund.envelopeID = envelope.id; fund.perPaycheckMinor = 50_000; context.insert(fund)
        oldRepay.envelopeID = envelope.id; oldRepay.kind = "repay"; oldRepay.perPaycheckMinor = 10_000; context.insert(oldRepay)
        let allocation = Allocation(); allocation.target = "envelope"; allocation.targetID = envelope.id; allocation.amountMinor = -100_001; allocation.idempotencyKey = "opening"; context.insert(allocation)
        try context.save()
        let id = UUID()
        func payload(_ debt: String, _ salaries: String) -> [String: MadarCore.JSONValue] { ["id": .string(envelope.id.uuidString), "debtMinor": .string(debt), "salaries": .string(salaries)] }
        #expect(try await f.run("money.adoptRepayment", payload("100000", "3")).status == .rejected) // stale debt
        #expect(try await f.run("money.adoptRepayment", payload("100001", "13")).status == .rejected) // beyond maxRepayCycles
        #expect(try await f.run("money.adoptRepayment", payload("100001", "3"), id: id).status == .applied)
        _ = try await f.run("money.adoptRepayment", payload("100001", "3"), id: id)
        let plans = try ModelContext(f.container).fetch(FetchDescriptor<EnvelopePlan>())
        let adopted = try #require(plans.first { $0.id == id })
        // 100001 / 3 = 33333 each; the stored total lets the last salary pay 33335.
        #expect(adopted.kind == "repay" && adopted.source == "salary" && adopted.envelopeID == envelope.id && adopted.deletedAt == nil)
        #expect(adopted.perPaycheckMinor == 33_333 && adopted.repaymentTotalMinor == 100_001 && adopted.repaymentPaychecks == 3)
        #expect(plans.first { $0.id == oldRepay.id }?.deletedAt != nil)
        let savings = try #require(plans.first { $0.id == fund.id })
        #expect(savings.deletedAt == nil && savings.perPaycheckMinor == 50_000 && savings.repaymentTotalMinor == nil)
        #expect(plans.filter { $0.deletedAt == nil }.count == 2)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil }.count == 1)
        #expect(try await f.run("system.undo", ["undoToken": .string(id.uuidString)]).status == .applied)
        let undone = try ModelContext(f.container).fetch(FetchDescriptor<EnvelopePlan>())
        #expect(undone.first { $0.id == id }?.deletedAt != nil)
        #expect(undone.first { $0.id == oldRepay.id }?.deletedAt == nil && undone.first { $0.id == oldRepay.id }?.perPaycheckMinor == 10_000)
        #expect(undone.first { $0.id == fund.id }?.perPaycheckMinor == 50_000)
        // Once a salary paid into an adopted plan, undoing the adoption is refused rather than orphaning the payment.
        let second = UUID()
        #expect(try await f.run("money.adoptRepayment", payload("100001", "2"), id: second).status == .applied)
        let paid = ModelContext(f.container), drop = Allocation(); drop.target = "envelope"; drop.targetID = envelope.id; drop.amountMinor = 50_000; drop.kind = "repay"; drop.idempotencyKey = "fund:c1:" + second.uuidString
        paid.insert(drop); try paid.save()
        let undoAfterSalary = try? await f.run("system.undo", ["undoToken": .string(second.uuidString)])
        #expect(undoAfterSalary?.status != .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<EnvelopePlan>()).first { $0.id == second }?.deletedAt == nil)
    }
    @Test func debtMoveIsBalancedReplayableAndUndoableWithoutTouchingSavings() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let context = ModelContext(f.container), envelope = Envelope(), plan = EnvelopePlan()
        envelope.name = "سفر"; context.insert(envelope)
        plan.envelopeID = envelope.id; plan.perPaycheckMinor = 50_000; context.insert(plan)
        for (target, targetID, amount) in [("envelope", Optional(envelope.id), -100_000), ("surplus", nil, 200_000)] {
            let row = Allocation(); row.target = target; row.targetID = targetID; row.amountMinor = amount; row.kind = "adjust"; row.idempotencyKey = UUID().uuidString; context.insert(row)
        }
        try context.save()
        let id = UUID(), payload: [String: MadarCore.JSONValue] = ["id": .string(envelope.id.uuidString), "source": .string("surplus"), "debtMinor": .string("100000")]
        #expect(try await f.run("money.repayEnvelopeNow", payload, id: id).status == .applied)
        _ = try await f.run("money.repayEnvelopeNow", payload, id: id)
        let read = ModelContext(f.container), rows = try read.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil }
        #expect(rows.count == 4); #expect(rows.reduce(0) { $0 + $1.amountMinor } == 100_000)
        #expect(rows.filter { $0.targetID == envelope.id }.reduce(0) { $0 + $1.amountMinor } == 0)
        #expect(try read.fetch(FetchDescriptor<EnvelopePlan>()).first?.perPaycheckMinor == 50_000)
        #expect(try await f.run("system.undo", ["undoToken": .string(id.uuidString)]).status == .applied)
        let undone = try ModelContext(f.container).fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil }
        #expect(undone.count == 2); #expect(undone.filter { $0.targetID == envelope.id }.reduce(0) { $0 + $1.amountMinor } == -100_000)
        #expect(try await f.run("money.repayEnvelopeNow", ["id": .string(envelope.id.uuidString), "source": .string("reserve"), "debtMinor": .string("100000")]).status == .rejected)
    }
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
        #expect(try await f.run("money.ingestBankMessage", ["text": .string("")], source: .shortcut).status != .applied)
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
    /// RM8: both ten-minute boundaries are inclusive, in either receive order.
    @Test(arguments: [-601, -600, 600, 601])
    func nearDuplicateIntakeKeepsTheTenMinuteBoundary(offset: Int) async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), original = MoneyTransaction()
        original.source = "manual"; original.kind = "expense"; original.reviewState = "ok"
        original.cardID = f.debit; original.fromAccountID = f.bank; original.method = "card"
        original.amountMinor = 4200; original.homeAmountMinor = 4200; original.merchant = "Coffee"
        original.eventAt = ISO8601DateFormatter().date(from: "2026-10-16T10:05:00Z")!.addingTimeInterval(Double(offset))
        original.dayKey = "2026-10-16"; context.insert(original); try context.save()
        #expect(try await f.ingest("شراء مدى\n*3333\n42.00 SAR\nلدى: Coffee\n2026-10-16 13:05").status == .applied)
        let message = try #require(try ModelContext(f.container).fetch(FetchDescriptor<BankMessage>()).first)
        #expect(message.status == (abs(offset) == 600 ? "possibleDuplicate" : "needsLook"))
        let draft = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.messageID == message.id })
        #expect(draft.reviewState == message.status)
        #expect(try f.transaction(original.id).reviewState == "ok", "Import never changes the confirmed original")
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

    /// F07: a statement message updates its card once, keyed by (card, estimated close day); a second message within
    /// five days with the same amount updates the same row, a different amount stays in review, an unknown card is refused.
    @Test func statementMessageUpdatesItsCardOnceAndUndoReturnsItToReview() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let text = "كشف حساب البطاقة *4444\nالمبلغ المستحق: 6,800.00 SAR\nالحد الأدنى: 340.00 SAR\nتاريخ الاستحقاق: 2026-11-05"
        let earlier = f.now.addingTimeInterval(-3 * 86_400)
        _ = try await f.run("money.ingestBankMessage", ["text": .string(text), "sender": .string("Bank")], source: .shortcut, at: earlier)
        func message(_ kind: String = "statement", status: String? = nil) throws -> [BankMessage] {
            try ModelContext(f.container).fetch(FetchDescriptor<BankMessage>()).filter { $0.kind == kind && (status == nil || $0.status == status) }.sorted { $0.receivedAt < $1.receivedAt }
        }
        let first = try #require(try message().first); #expect(first.status == "needsLook")
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<MoneyTransaction>()) == 0, "A statement is not a movement")
        let apply = UUID()
        #expect(try await f.run("money.applyStatement", ["id": .string(first.id.uuidString)], id: apply).status == .applied)
        var statements = try ModelContext(f.container).fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil }
        #expect(statements.count == 1); let row = try #require(statements.first)
        #expect(row.cardID == f.credit); #expect(row.statementMinor == 680_000); #expect(row.minimumDueMinor == 34_000)
        #expect(row.closeDateSource == "estimated"); #expect(row.closeDate == ISO8601DateFormatter().date(from: "2026-10-13T00:00:00+03:00"))
        #expect(row.dueDate != nil); #expect(row.messageID == first.id)
        #expect(try message(status: "ok").count == 1)
        // Same amount three days later (within five of the estimated close): the same statement row, not a second.
        _ = try await f.run("money.ingestBankMessage", ["text": .string(text + "\n "), "sender": .string("Bank")], source: .shortcut)
        let second = try #require(try message(status: "needsLook").first)
        #expect(try await f.run("money.applyStatement", ["id": .string(second.id.uuidString)]).status == .applied)
        statements = try ModelContext(f.container).fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil }
        #expect(statements.count == 1); #expect(statements.first?.messageID == second.id)
        // A different amount inside the window stays for review.
        _ = try await f.run("money.ingestBankMessage", ["text": .string(text.replacingOccurrences(of: "6,800.00", with: "6,900.00")), "sender": .string("Bank")], source: .shortcut)
        let third = try #require(try message(status: "needsLook").first)
        #expect(try await f.run("money.applyStatement", ["id": .string(third.id.uuidString)]).status == .rejected)
        #expect(try message(status: "needsLook").count == 1)
        // Unknown last four: never a silent card.
        _ = try await f.run("money.ingestBankMessage", ["text": .string(text.replacingOccurrences(of: "*4444", with: "*9999")), "sender": .string("Bank")], source: .shortcut)
        let unknown = try #require(try message(status: "needsLook").first { $0.text.contains("9999") })
        #expect(try await f.run("money.applyStatement", ["id": .string(unknown.id.uuidString)]).status == .rejected)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Card>()) == 2)
        // Ignore removes it from review; undo brings it back.
        let ignore = UUID()
        #expect(try await f.run("money.ignoreMessage", ["id": .string(unknown.id.uuidString)], id: ignore).status == .applied)
        #expect(try message().first { $0.id == unknown.id }?.status == "ignored")
        #expect(try await f.run("system.undo", ["undoToken": .string(ignore.uuidString)]).status == .applied)
        #expect(try message().first { $0.id == unknown.id }?.status == "needsLook")
    }
    /// Each purchase keeps its own manual category. Old category rules remain stored but do not prefill new purchases;
    /// three confirmed manual choices produce a changeable learned suggestion.
    @Test func merchantCategoriesStayPerPurchaseAndLearnAfterThreeConfirmedChoices() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), cafe = MadarData.Category(), grocery = MadarData.Category()
        cafe.name = "مطاعم"; grocery.name = "بقالة"; c.insert(cafe); c.insert(grocery); try c.save()
        #expect(MoneyCommandPayload.validate(name: "money.categorize", payload: ["id": .string(UUID().uuidString), "categoryID": .string(cafe.id.uuidString)]))
        #expect(MoneyCommandPayload.validate(name: "money.categorize", payload: ["id": .string(UUID().uuidString), "categoryID": .string(cafe.id.uuidString), "categorySource": .string("rule")]))
        #expect(MoneyCommandPayload.validate(name: "money.categorize", payload: ["id": .string(UUID().uuidString), "categoryID": .string(cafe.id.uuidString), "remember": .bool(true)]))
        #expect(!MoneyCommandPayload.validate(name: "money.categorize", payload: ["id": .string(UUID().uuidString), "categoryID": .string(cafe.id.uuidString), "categorySource": .string("other")]))
        // The expense sheet sends the category's origin with a hand-logged purchase.
        for source in ["manual", "learned"] {
            let logged = try await f.run("money.logExpense", ["amountMinor": .string("900"), "currency": .string("SAR"), "fromAccountID": .string(f.cash.uuidString),
                "merchant": .string("مقهى " + source), "categoryID": .string(cafe.id.uuidString), "categorySource": .string(source)])
            #expect(logged.status == .applied, "Unexpected expense result: \(logged.reason ?? "no reason")")
            let row = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.merchant == "مقهى " + source })
            #expect(row.categoryID == cafe.id && row.categorySource == source)
        }
        let withoutCategory: [String: MadarCore.JSONValue] = ["amountMinor": .string("900"), "currency": .string("SAR"), "categorySource": .string("manual")]
        #expect(!MoneyCommandPayload.validate(name: "money.logExpense", payload: withoutCategory))
        let beforeOrphan = try ModelContext(f.container).fetchCount(FetchDescriptor<MoneyTransaction>())
        #expect(try await f.run("money.logExpense", withoutCategory).status == .rejected)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<MoneyTransaction>()) == beforeOrphan)
        #expect(!MoneyCommandPayload.validate(name: "money.logExpense", payload: ["amountMinor": .string("900"), "currency": .string("SAR"), "categorySource": .string("rule")]))
        #expect(try await f.run("money.saveMerchantRule", ["merchant": .string("coffee corner"), "categoryID": .string(grocery.id.uuidString), "ignore": .bool(false)]).status == .applied)
        func purchase(_ amount: Int, _ minute: Int) async throws -> MoneyTransaction {
            let clock = String(format: "09:%02d", minute)
            _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n\(amount).00 SAR\nلدى: Coffee  Corner\n2026-10-16 \(clock)")
            return try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == amount * 100 })
        }
        for minute in 1...3 {
            let row = try await purchase(20 + minute, minute)
            #expect(row.categoryID == nil, "A stored merchant category does not force a different purchase")
            let categoryChoice = try await f.run("money.categorize", ["id": .string(row.id.uuidString), "categoryID": .string(cafe.id.uuidString)])
            #expect(categoryChoice.status == .applied, "Unexpected categorization result: \(categoryChoice.reason ?? "no reason")")
            #expect(try f.transaction(row.id).categorySource == "manual")
            #expect(try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString)]).status == .applied)
        }
        let suggested = try await purchase(30, 10)
        #expect(suggested.categoryID == cafe.id && suggested.categorySource == "learned")
        #expect(suggested.reviewState == "needsLook", "A learned category remains an editable draft")
        #expect(try await f.run("money.categorize", ["id": .string(suggested.id.uuidString), "categoryID": .string(grocery.id.uuidString)]).status == .applied)
        #expect(try f.transaction(suggested.id).categoryID == grocery.id)
        #expect(try f.transaction(suggested.id).categorySource == "manual")
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MerchantRule>()).filter { $0.deletedAt == nil }.count == 1,
                "Existing merchant data stays stored")

        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n17.00 SAR\nلدى: Old Cafe\n2026-10-16 10:00")
        let migrated = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.merchant == "Old Cafe" })
        #expect(try await f.run("money.categorize", ["id": .string(migrated.id.uuidString),
            "categoryID": .string(cafe.id.uuidString), "categorySource": .string("rule")]).status == .applied)
        #expect(try f.transaction(migrated.id).categorySource == "rule")
        #expect(try await f.run("money.confirmTransaction", ["id": .string(migrated.id.uuidString)]).status == .applied)
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n18.00 SAR\nلدى: Old Cafe\n2026-10-16 10:01")
        let nextOldCafe = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.merchant == "Old Cafe" && $0.amountMinor == 1_800 })
        #expect(nextOldCafe.categoryID == nil, "An automatic migration choice must not train a future suggestion")
    }
    /// M5-V08 «نزل الراتب»: one command closes the cycle (L02 offset), opens the next with a frozen policy, moves the
    /// salary day's movement, fills the surplus to its cap then the reserve, and undo stands only until the new cycle is used.
    @Test func confirmSalaryClosesOpensAndUndoesUntilTheNewCycleIsUsed() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), zone = ActivePlace.riyadh.timeZone, start = try GregorianDay("2026-09-26")
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight")])
        let old = Cycle(); old.start = start.date(in: zone); old.expectedEnd = start.adding(days: 30).date(in: zone); old.dailyAllowanceMinor = 20_000; c.insert(old)
        let seed = Allocation(); seed.target = "surplus"; seed.amountMinor = 500_000; seed.idempotencyKey = "opening-surplus"; c.insert(seed); try c.save()
        // 20 days × 20000 = 400000 accrued before the salary day; 4420.00 spent → «لك الآن» −42000 (L02).
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n4420.00 SAR\nلدى: Furniture\n2026-10-01 10:00")
        let expense = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == 442_000 })
        #expect(try await f.run("money.confirmTransaction", ["id": .string(expense.id.uuidString)]).status == .applied)
        _ = try await f.ingest("راتب\n*1111\n15000.00 SAR\n2026-10-16 12:00")
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n50.00 SAR\nلدى: Bakery\n2026-10-16 13:00")
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>())
        let salary = try #require(rows.first { $0.kind == "salary" }), sameDay = try #require(rows.first { $0.amountMinor == 5_000 })
        #expect(try await f.run("money.confirmTransaction", ["id": .string(sameDay.id.uuidString)]).status == .applied)
        #expect(try f.transaction(sameDay.id).cycleID == old.id)

        let preview = try MoneyRepository(context: ModelContext(f.container)).salaryOpening(salaryID: salary.id, newCycleID: UUID())
        #expect(preview.input.closing?.availableNowMinor == -42_000)
        #expect(preview.endDay == (try GregorianDay("2026-11-16")))
        // New cycle: 1500000 − 31 × 20000 = 880000; the surplus (500000 − 42000 offset) fills to 1000000, 338000 to the reserve.
        #expect(preview.plan.leftoverMinor == 880_000)

        let command = UUID()
        #expect(try await f.run("money.confirmSalary", ["id": .string(salary.id.uuidString)], id: command).status == .applied)
        let read = ModelContext(f.container)
        let cycles = try read.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil }
        let closed = try #require(cycles.first { $0.id == old.id }), opened = try #require(cycles.first { $0.id == command })
        #expect(closed.closedAt != nil); #expect(closed.end == salary.eventAt); #expect(closed.reportVersion == 1)
        let report = try JSONDecoder().decode(SalaryCloseReport.self, from: try #require(closed.closedReportJSON))
        #expect(report.carriedMinor == -42_000); #expect(report.offsetMinor == 42_000); #expect(report.carryMinor == 0)
        #expect(opened.incomeMinor == 1_500_000); #expect(opened.carryAdjustMinor == 0); #expect(opened.salaryTransactionID == salary.id)
        let policy = try #require(try read.fetch(FetchDescriptor<CyclePolicy>()).first { $0.cycleID == command })
        #expect(policy.effectiveFromDayKey == "2026-10-16"); #expect(policy.dailyRateMinor == 20_000)
        let allocations = try read.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil }
        #expect(allocations.filter { $0.target == "surplus" }.reduce(0) { $0 + $1.amountMinor } == 1_000_000)
        #expect(allocations.filter { $0.target == "reserve" }.reduce(0) { $0 + $1.amountMinor } == 338_000)
        #expect(try f.transaction(salary.id).reviewState == "ok"); #expect(try f.transaction(salary.id).cycleID == command)
        #expect(try f.transaction(sameDay.id).cycleID == command, "The salary day belongs to the new cycle")
        #expect(try MoneyRepository(context: read).cycle(at: f.now)?.id == command)
        #expect(try await f.run("money.confirmSalary", ["id": .string(salary.id.uuidString)]).status == .rejected)

        // Undo returns the open cycle, the draft salary and the balances.
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        let back = ModelContext(f.container)
        #expect(try back.fetch(FetchDescriptor<Cycle>()).first { $0.id == old.id }?.closedAt == nil)
        #expect(try back.fetch(FetchDescriptor<Cycle>()).first { $0.id == command }?.deletedAt != nil)
        #expect(try f.transaction(salary.id).reviewState != "ok"); #expect(try f.transaction(sameDay.id).cycleID == old.id)
        #expect(try back.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.target == "surplus" }.reduce(0) { $0 + $1.amountMinor } == 500_000)

        // Once a movement is filed in the new cycle, its undo is refused.
        let again = UUID()
        #expect(try await f.run("money.confirmSalary", ["id": .string(salary.id.uuidString)], id: again).status == .applied)
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n12.00 SAR\nلدى: Water\n2026-10-16 14:00")
        let water = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == 1_200 })
        #expect(try await f.run("money.confirmTransaction", ["id": .string(water.id.uuidString)]).status == .applied)
        #expect(try f.transaction(water.id).cycleID == again)
        await #expect(throws: MoneyCommandError.undoSuperseded) { try await f.run("system.undo", ["undoToken": .string(again.uuidString)]) }
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Cycle>()).first { $0.id == again }?.deletedAt == nil)
        // A salary dated before the open cycle never opens a second cycle beside it.
        _ = try await f.ingest("راتب\n*1111\n15000.00 SAR\n2026-10-10 12:00")
        let late = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.kind == "salary" && $0.reviewState != "ok" })
        #expect(try await f.run("money.confirmSalary", ["id": .string(late.id.uuidString)]).status == .rejected)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.closedAt == nil }.count == 1)
        #expect(!MoneyCommandPayload.validate(name: "money.confirmSalary", payload: ["id": .string(salary.id.uuidString), "remainderTo": .string("goal")]))
    }
    /// M5-V27: an incoming transfer becomes a learned salary source only after the owner opens and confirms the salary flow.
    @Test func confirmingIncomingTransferLearnsSourceAndUndoRemovesIt() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), zone = ActivePlace.riyadh.timeZone, start = try GregorianDay("2026-10-10")
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight")])
        let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = start.adding(days: 30).date(in: zone); cycle.dailyAllowanceMinor = 20_000; c.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.allowanceMinor = 20_000; policy.dailyRateMinor = 20_000; c.insert(policy); try c.save()

        _ = try await f.ingest("حوالة واردة\nإلى: *1111\nمن: شركة المدار\n15000.00 SAR\n2026-10-16 12:00")
        let incoming = try f.transaction()
        #expect(incoming.kind == "transfer" && incoming.reviewState == "needsLook")
        let preview = try MoneyRepository(context: ModelContext(f.container)).salaryOpening(salaryID: incoming.id, newCycleID: UUID())
        #expect(preview.salaryMinor == 1_500_000)

        let command = UUID()
        #expect(try await f.run("money.confirmSalary", ["id": .string(incoming.id.uuidString)], id: command).status == .applied)
        let confirmed = try f.transaction(incoming.id)
        #expect(confirmed.kind == "salary" && confirmed.reviewState == "ok")

        _ = try await f.ingest("حوالة واردة\nإلى: *1111\nمن: شركة المدار\n18000.00 SAR\n2026-10-16 13:00")
        let later = try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.amountMinor == 1_800_000 }
        #expect(later?.reviewState == "needsLook")
        #expect(SalarySourceMatcher.matches(later?.counterparty, learnedKeys: ["شركة المدار"]))

        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        let undone = try f.transaction(incoming.id)
        #expect(undone.kind == "transfer" && undone.reviewState != "ok")
        let learned = Set(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>())
            .filter { $0.kind == "salary" && $0.reviewState == "ok" }.compactMap { SalarySourceMatcher.key($0.counterparty) })
        #expect(!SalarySourceMatcher.matches(later?.counterparty, learnedKeys: learned))
    }
    /// M5-V09: a bill is one row on its day; a loan writes its equal monthly instalments; undo removes both.
    @Test func saveObligationWritesInstalmentsAndUndoesThem() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        #expect(try await f.run("money.saveObligation", ["kind": .string("bill"), "name": .string("الكهرباء"), "amountMinor": .string("22000"), "dueDay": .number(12)]).status == .applied)
        let loan = UUID()
        #expect(try await f.run("money.saveObligation", ["kind": .string("loan"), "name": .string("قسط القرض"), "amountMinor": .string("285000"), "count": .number(3), "firstDue": .string("2026-11-05")], id: loan).status == .applied)
        let c = ModelContext(f.container)
        let items = try c.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.obligationID == loan && $0.deletedAt == nil }.sorted { $0.seq < $1.seq }
        #expect(items.map(\.amountMinor) == [285_000, 285_000, 285_000])
        let zone = ActivePlace.riyadh.timeZone
        #expect(items.map { GregorianDay.containing($0.dueDate, in: zone).description } == ["2026-11-05", "2026-12-05", "2027-01-05"])
        #expect(try c.fetch(FetchDescriptor<Obligation>()).first { $0.id == loan }?.totalMinor == 855_000)
        #expect(try await f.run("system.undo", ["undoToken": .string(loan.uuidString)]).status == .applied)
        let back = ModelContext(f.container)
        #expect(try back.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.obligationID == loan && $0.deletedAt == nil }.isEmpty)
        #expect(try back.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil }.map(\.name) == ["الكهرباء"])
        #expect(!MoneyCommandPayload.validate(name: "money.saveObligation", payload: ["kind": .string("bill"), "name": .string("x"), "amountMinor": .string("1"), "dueDay": .number(32)]))
        #expect(!MoneyCommandPayload.validate(name: "money.saveObligation", payload: ["kind": .string("loan"), "name": .string("x"), "amountMinor": .string("1"), "count": .number(0), "firstDue": .string("2026-11-05")]))
    }
    /// M5-X00 (owner 16 Oct): a subscription on a free interval and first due day; the owner's rent every 6 months, first
    /// due 18 Feb 2027, is not reserved in October 2026, while a monthly one due on 20 Oct is. Undo removes it.
    @Test func flexibleSubscriptionStoresItsScheduleReservesOnlyItsDueDaysAndUndoes() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let rent = UUID()
        #expect(try await f.run("money.saveObligation", ["kind": .string("subscription"), "name": .string("الإيجار"), "amountMinor": .string("1500000"),
            "repeatEvery": .number(6), "repeatUnit": .string("month"), "firstDue": .string("2027-02-18")], id: rent).status == .applied)
        let stored = try #require(try ModelContext(f.container).fetch(FetchDescriptor<Obligation>()).first { $0.id == rent })
        #expect(stored.kind == "subscription" && stored.repeatEvery == 6 && stored.repeatUnit == "month" && stored.firstDueDayKey == "2027-02-18")
        #expect(stored.dueDay == nil && stored.totalMinor == 1_500_000 && stored.amountMinor == 1_500_000)
        #expect(stored.recurrence?.preview(from: try GregorianDay("2026-10-16")).map(\.description) == ["2027-02-18", "2027-08-18", "2028-02-18"])
        #expect(try MoneyRepository(context: ModelContext(f.container)).basisInput(at: f.now).billsDueMinor == 0)
        #expect(try await f.run("money.saveObligation", ["kind": .string("subscription"), "name": .string("النادي"), "amountMinor": .string("15000"),
            "repeatEvery": .number(1), "repeatUnit": .string("month"), "firstDue": .string("2026-10-20")]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(f.container)).basisInput(at: f.now).billsDueMinor == 15_000)
        #expect(try await f.run("system.undo", ["undoToken": .string(rent.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil }.map(\.name) == ["النادي"])
        // Validation: a subscription needs its interval; units, limits and mixed shapes are refused.
        let base: [String: MadarCore.JSONValue] = ["kind": .string("subscription"), "name": .string("x"), "amountMinor": .string("1")]
        func valid(_ extra: [String: MadarCore.JSONValue]) -> Bool { MoneyCommandPayload.validate(name: "money.saveObligation", payload: base.merging(extra) { $1 }) }
        #expect(valid(["repeatEvery": .number(2), "repeatUnit": .string("week"), "firstDue": .string("2026-10-01")]))
        #expect(!valid([:]))
        #expect(!valid(["dueDay": .number(5)]))
        #expect(!valid(["repeatEvery": .number(0), "repeatUnit": .string("month"), "firstDue": .string("2026-10-01")]))
        #expect(!valid(["repeatEvery": .number(11), "repeatUnit": .string("year"), "firstDue": .string("2026-10-01")]))
        #expect(!valid(["repeatEvery": .number(1), "repeatUnit": .string("fortnight"), "firstDue": .string("2026-10-01")]))
        #expect(!valid(["repeatEvery": .number(1), "firstDue": .string("2026-10-01")]))
        #expect(!valid(["repeatEvery": .number(1), "repeatUnit": .string("month"), "firstDue": .string("2026-10-01"), "dueDay": .number(1)]))
        #expect(!valid(["repeatEvery": .number(1), "repeatUnit": .string("month"), "firstDue": .string("2026-10-01"), "count": .number(3)]))
        #expect(MoneyCommandPayload.validate(name: "money.saveObligation", payload: ["kind": .string("bill"), "name": .string("x"), "amountMinor": .string("1"),
            "repeatEvery": .number(3), "repeatUnit": .string("month"), "firstDue": .string("2026-12-31")]))
    }
    /// M5-X00: instalments every two weeks from a first day; the first is on that day and each next one 14 days on.
    @Test func instalmentsTakeAFreeInterval() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let plan = UUID()
        #expect(try await f.run("money.saveObligation", ["kind": .string("installment"), "name": .string("تقسيط الجوال"), "amountMinor": .string("25000"), "count": .number(3),
            "firstDue": .string("2026-11-01"), "repeatEvery": .number(2), "repeatUnit": .string("week")], id: plan).status == .applied)
        let c = ModelContext(f.container), zone = ActivePlace.riyadh.timeZone
        let items = try c.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.obligationID == plan && $0.deletedAt == nil }.sorted { $0.seq < $1.seq }
        #expect(items.map { GregorianDay.containing($0.dueDate, in: zone).description } == ["2026-11-01", "2026-11-15", "2026-11-29"])
        let row = try #require(try c.fetch(FetchDescriptor<Obligation>()).first { $0.id == plan })
        #expect(row.dueDay == nil && row.repeatUnit == "week" && row.repeatEvery == 2 && row.totalMinor == 75_000)
    }
    /// M5-X00: a new cycle counts each flexible due day inside it once; a six-month rent outside it counts nothing.
    @Test func salaryOpeningCountsFlexibleDueDaysInsideTheNewCycle() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container)
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "mal.dailyAllowance": .object(["mode": .string("fixed"), "amountMinor": .number(20_000), "percentBp": .null])])
        try c.save()
        for (name, amount, every, unit, first) in [("الإيجار", "1500000", 6, "month", "2027-02-18"), ("النادي", "15000", 2, "week", "2026-10-10"), ("الماء", "8000", 1, "month", "2026-10-16")] {
            #expect(try await f.run("money.saveObligation", ["kind": .string("subscription"), "name": .string(name), "amountMinor": .string(amount),
                "repeatEvery": .number(Double(every)), "repeatUnit": .string(unit), "firstDue": .string(first)]).status == .applied)
        }
        _ = try await f.ingest("راتب\n*1111\n15000.00 SAR\n2026-10-16 12:00")
        let salary = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.kind == "salary" })
        let preview = try MoneyRepository(context: ModelContext(f.container)).salaryOpening(salaryID: salary.id, newCycleID: UUID())
        #expect(preview.startDay.description == "2026-10-16" && preview.endDay.description == "2026-11-16")
        // النادي on 24 Oct and 7 Nov (2 × 15000) and الماء on 16 Oct (8000); the rent's first due day is in February.
        #expect(preview.input.obligationsMinor == 38_000)
    }
    /// M5-X00 (owner 16 Oct): the stamp keeps an optional reason; lifting clears it and undo of the lift brings it back.
    @Test func budgetStampKeepsAnOptionalReason() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء مدى\n*3333\n120.00 SAR\n2026-10-16 12:00")
        let row = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(row.id.uuidString)]).status == .applied)
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(row.id.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false), "reason": .string("  هدية لأخي ")]).status == .applied)
        #expect(try f.transaction(row.id).budgetIgnoreReason == "هدية لأخي")
        let lift = UUID()
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(row.id.uuidString), "excluded": .bool(false), "expectedExcluded": .bool(true)], id: lift).status == .applied)
        let lifted = try f.transaction(row.id); #expect(lifted.budgetIgnoreReason == nil && !lifted.ignoredFromBudget)
        #expect(try await f.run("system.undo", ["undoToken": .string(lift.uuidString)]).status == .applied)
        let restored = try f.transaction(row.id); #expect(restored.budgetIgnoreReason == "هدية لأخي" && restored.ignoredFromBudget)
        let id: MadarCore.JSONValue = .string(row.id.uuidString)
        #expect(!MoneyCommandPayload.validate(name: "money.setBudgetExclusion", payload: ["id": id, "excluded": .bool(false), "expectedExcluded": .bool(true), "reason": .string("x")]))
        #expect(!MoneyCommandPayload.validate(name: "money.setBudgetExclusion", payload: ["id": id, "excluded": .bool(true), "expectedExcluded": .bool(false), "reason": .string(String(repeating: "س", count: 121))]))
        #expect(MoneyCommandPayload.validate(name: "money.setBudgetExclusion", payload: ["id": id, "excluded": .bool(true), "expectedExcluded": .bool(false), "reason": .string("")]))
    }
    /// M5-V10: one live limit per category; fixed, percent and none round-trip, and undo restores the previous limit.
    @Test func setCategoryLimitKeepsOneRowAndUndoes() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let c = ModelContext(f.container), food = MadarData.Category(); food.name = "مطاعم"; c.insert(food); try c.save()
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(food.id.uuidString), "mode": .string("fixed"), "limitMinor": .string("240000")]).status == .applied)
        let change = UUID()
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(food.id.uuidString), "mode": .string("percent"), "percentBp": .number(600), "base": .string("income")], id: change).status == .applied)
        var limits = try ModelContext(f.container).fetch(FetchDescriptor<CategoryLimit>()).filter { $0.deletedAt == nil }
        #expect(limits.count == 1); #expect(limits.first?.mode == "percent"); #expect(limits.first?.percentBp == 600); #expect(limits.first?.limitMinor == 0)
        #expect(try await f.run("system.undo", ["undoToken": .string(change.uuidString)]).status == .applied)
        limits = try ModelContext(f.container).fetch(FetchDescriptor<CategoryLimit>()).filter { $0.deletedAt == nil }
        #expect(limits.first?.mode == "fixed"); #expect(limits.first?.limitMinor == 240_000)
        #expect(!MoneyCommandPayload.validate(name: "money.setCategoryLimit", payload: ["categoryID": .string(food.id.uuidString), "mode": .string("percent"), "percentBp": .number(0), "base": .string("income")]))
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(UUID().uuidString), "mode": .string("none")]).status == .rejected)
        // Review: a first limit set, undone, then set again gets a new row; the next command still reads the store.
        let fuel = MadarData.Category(); fuel.name = "بنزين"; let c2 = ModelContext(f.container); c2.insert(fuel); try c2.save()
        let first = UUID()
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(fuel.id.uuidString), "mode": .string("fixed"), "limitMinor": .string("100000")], id: first).status == .applied)
        #expect(try await f.run("system.undo", ["undoToken": .string(first.uuidString)]).status == .applied)
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(fuel.id.uuidString), "mode": .string("fixed"), "limitMinor": .string("120000")]).status == .applied)
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(fuel.id.uuidString), "mode": .string("fixed"), "limitMinor": .string("130000")]).status == .applied)
        let fuelLimits = try ModelContext(f.container).fetch(FetchDescriptor<CategoryLimit>()).filter { $0.categoryID == fuel.id && $0.deletedAt == nil }
        #expect(fuelLimits.count == 1); #expect(fuelLimits.first?.limitMinor == 130_000)
    }
    /// M5-V16: the cashback rate entered by hand, marked «entered», back to unknown with null, and undone.
    @Test func setCardCashbackEntersTheRateAndUndoes() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let c = ModelContext(f.container), card = Card(); card.name = "بطاقة"; card.last4 = "1111"
        card.fieldSourcesJSON = try JSONSerialization.data(withJSONObject: ["limitMinor": "message"]); c.insert(card); try c.save()
        let id: MadarCore.JSONValue = .string(card.id.uuidString), change = UUID()
        #expect(try await f.run("money.setCardCashback", ["id": id, "cashbackBp": .number(125)], id: change).status == .applied)
        var row = try #require(try ModelContext(f.container).fetch(FetchDescriptor<Card>()).first { $0.id == card.id })
        var sources = try #require(try JSONSerialization.jsonObject(with: row.fieldSourcesJSON) as? [String: String])
        #expect(row.cashbackBp == 125); #expect(sources == ["limitMinor": "message", "cashbackBp": "entered"])
        #expect(try await f.run("money.setCardCashback", ["id": id, "cashbackBp": .null]).status == .applied)
        row = try #require(try ModelContext(f.container).fetch(FetchDescriptor<Card>()).first { $0.id == card.id })
        sources = try #require(try JSONSerialization.jsonObject(with: row.fieldSourcesJSON) as? [String: String])
        #expect(row.cashbackBp == nil); #expect(sources == ["limitMinor": "message"])
        #expect(!MoneyCommandPayload.validate(name: "money.setCardCashback", payload: ["id": id, "cashbackBp": .number(10_001)]))
        #expect(!MoneyCommandPayload.validate(name: "money.setCardCashback", payload: ["id": id]))
        #expect(try await f.run("money.setCardCashback", ["id": .string(UUID().uuidString), "cashbackBp": .number(50)]).status == .rejected)
        // Undo of the first change restores the rate the card had before it: unknown.
        #expect(try await f.run("money.setCardCashback", ["id": id, "cashbackBp": .number(200)]).status == .applied)
        let third = UUID()
        #expect(try await f.run("money.setCardCashback", ["id": id, "cashbackBp": .number(300)], id: third).status == .applied)
        #expect(try await f.run("system.undo", ["undoToken": .string(third.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Card>()).first { $0.id == card.id }?.cashbackBp == 200)
    }
    /// M5-V16: the preferred credit card is optional, app-only, scoped to one live category, and undoable.
    @Test func categoryPreferredCardGuidesFutureExpensesAndCanBeCleared() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let c = ModelContext(f.container), category = MadarData.Category(), credit = Card(), debit = Card()
        category.name = "بقالة"; credit.name = "بطاقة السفر"; credit.kind = "credit"; debit.name = "مدى"; debit.kind = "debit"
        c.insert(category); c.insert(credit); c.insert(debit); try c.save()
        let payload: [String: MadarCore.JSONValue] = ["categoryID": .string(category.id.uuidString), "cardID": .string(credit.id.uuidString)]
        let change = UUID()
        #expect(MoneyCommandPayload.validate(name: "money.setCategoryPreferredCard", payload: payload))
        #expect(!MoneyCommandPayload.validate(name: "money.setCategoryPreferredCard", payload: ["categoryID": .string(category.id.uuidString)]))
        #expect(!MoneyCommandPayload.validate(name: "money.setCategoryPreferredCard", payload: ["categoryID": .string("bad"), "cardID": .null]))
        #expect(try await f.run("money.setCategoryPreferredCard", payload, source: .shortcut).status != .applied)
        #expect(try await f.run("money.setCategoryPreferredCard", payload, id: change).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == category.id }?.preferredCardID == credit.id)
        #expect(try await f.run("system.undo", ["undoToken": .string(change.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == category.id }?.preferredCardID == nil)
        #expect(try await f.run("money.setCategoryPreferredCard", ["categoryID": .string(category.id.uuidString), "cardID": .string(debit.id.uuidString)]).status == .rejected)
        #expect(try await f.run("money.setCategoryPreferredCard", payload).status == .applied)
        #expect(try await f.run("money.setCategoryPreferredCard", ["categoryID": .string(category.id.uuidString), "cardID": .null]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == category.id }?.preferredCardID == nil)
        #expect(try await f.run("money.setCategoryPreferredCard", ["categoryID": .string(UUID().uuidString), "cardID": .null]).status == .rejected)
    }
    /// «منذ آخر زيارة»: the visit marker is one device row, updated in place, with no undo.
    /// §11 seeded rows: the design's six categories, UUIDv5(seedNS, "Category:<slug>") worked out with Python's uuid5.
    @Test func defaultCategoriesSeedOnceIntoAnEmptyStoreOnly() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        #expect(try await f.run("money.seedCategories", [:]).status == .applied)
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<MadarData.Category>()).sorted { $0.order < $1.order }
        #expect(rows.map(\.name) == ["مطاعم وقهوة", "بقالة", "بنزين", "تسوق", "اشتراكات", "أخرى"])
        #expect(rows.map(\.id.uuidString) == ["B568F315-2139-5DFF-B10F-F2F89052F257", "26B8632C-9AA9-5CE0-AEDE-4760AE674D04",
            "D2CB3CF3-C553-504F-9343-3A75C7C63FAA", "A679403D-BB8C-55BD-9640-E8CD0CFD1BF2", "B2EAF182-D412-5031-93A2-A876545B6290",
            "DAA1D930-CBC1-5926-B244-6C858570F75D"])
        // Seeds are stamped at the epoch so a real edit or tombstone of the same id always wins the merge.
        #expect(rows.allSatisfy { $0.deletedAt == nil && $0.updatedAt == Date(timeIntervalSince1970: 0) })
        // A second run (another command id) adds nothing.
        #expect(try await f.run("money.seedCategories", [:]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MadarData.Category>()).count == 6)
        #expect(!MoneyCommandPayload.validate(name: "money.seedCategories", payload: ["name": .string("x")]))

        // A store that already has a category, even a deleted one, is never seeded.
        let g = try MoneyFixture(); defer { g.clean() }
        let context = ModelContext(g.container), own = MadarData.Category()
        own.name = "مصروفات البيت"; own.deletedAt = g.now; context.insert(own); try context.save()
        #expect(try await g.run("money.seedCategories", [:]).status == .applied)
        #expect(try ModelContext(g.container).fetch(FetchDescriptor<MadarData.Category>()).map(\.name) == ["مصروفات البيت"])
    }

    @Test func markVisitKeepsOneDeviceRowAtTheCommandTime() async throws {
        let f = try MoneyFixture(); defer { f.clean() }
        let first = try await f.run("money.markVisit", [:]); #expect(first.status == .applied); #expect(first.undoToken == nil)
        #expect(try await f.run("money.markVisit", [:]).status == .applied)
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == "sys.moneyLastVisit" && $0.deletedAt == nil }
        #expect(rows.count == 1)
        #expect(try JSONDecoder().decode(String.self, from: try #require(rows.first).valueJSON) == ISO8601DateFormatter().string(from: f.now))
        #expect(!MoneyCommandPayload.validate(name: "money.markVisit", payload: ["at": .string("x")]))
    }
    /// «اعتمد الواضح»: one receipt confirms every listed draft and one undo returns all; one bad id rejects all.
    @Test func confirmClearIsAtomicWithOneUndo() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n42.00 SAR\nلدى: Coffee\n2026-10-16 13:05")
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n18.50 SAR\nلدى: Bakery\n2026-10-16 14:10")
        _ = try await f.ingest("راتب\n*1111\n15000.00 SAR\n2026-10-16 12:00")
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>())
        let purchases = rows.filter { $0.kind == "expense" }.map { MadarCore.JSONValue.string($0.id.uuidString) }
        let salary = try #require(rows.first { $0.kind == "salary" })
        #expect(purchases.count == 2)
        let ids = rows.map(\.id), dry = MoneyMutationHandler.confirmableAsRead(ids, container: f.container, now: f.now)
        #expect(dry == Set(rows.filter { $0.kind == "expense" }.map(\.id)), "The dry run accepts the purchases, never the salary")
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).allSatisfy { $0.reviewState != "ok" }, "The dry run writes nothing")
        #expect(try await f.run("money.confirmClear", ["ids": .array(purchases + [.string(salary.id.uuidString)])]).status == .rejected)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.reviewState == "ok" }.isEmpty, "Atomic: nothing confirmed")
        let command = UUID()
        #expect(try await f.run("money.confirmClear", ["ids": .array(purchases)], id: command).status == .applied)
        #expect(try f.basis().inAccountMinor == 2_010_000 - 4200 - 1850)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<BankMessage>()).filter { $0.status == "ok" }.count == 2)
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.reviewState == "ok" }.isEmpty)
        #expect(!MoneyCommandPayload.validate(name: "money.confirmClear", payload: ["ids": .array([.string(salary.id.uuidString), .string(salary.id.uuidString)])]))
    }

    @Test func reserveTargetUndoPreservesLaterSpendingAndNeverMovesMoney() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let c = ModelContext(f.container), reserve = Envelope(); reserve.role = "reserve"; reserve.name = "احتياطي"; c.insert(reserve)
        let funding = Allocation(); funding.target = "reserve"; funding.amountMinor = 100000; funding.idempotencyKey = "opening"; c.insert(funding); try c.save()
        let goal = UUID(), p: [String: MadarCore.JSONValue] = ["targetMinor": .number(200000)]
        let first = try await f.run("money.setReserveGoal", p, id: goal)
        let replay = try await f.run("money.setReserveGoal", p, id: goal)
        #expect(first.undoToken == goal); #expect(replay == first)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Allocation>()) == 1)
        _ = try await f.ingest("شراء مدى\n*3333\n5.00 SAR\n2026-10-16 12:00")
        let tx = try f.transaction()
        _ = try await f.run("money.confirmTransaction", ["id": .string(tx.id.uuidString), "allocations": .array([.object(["target": .string("reserve"), "amountMinor": .number(500)])])])
        _ = try await f.run("system.undo", ["undoToken": .string(goal.uuidString)])
        let updated = try #require(try ModelContext(f.container).fetch(FetchDescriptor<Envelope>()).first { $0.id == reserve.id })
        #expect(updated.targetMinor == nil); #expect(updated.balanceMinor == 99500)
        #expect(try MoneyRepository(context: ModelContext(f.container)).allocationRows().count == 2)
        #expect(try f.basis().inAccountMinor == 2_009_500)
    }


    /// M5-V15 / F03: one «محضر» of three lines in one command — a missed spend on the account, an unexplained card
    /// difference and a match — then a stale replay, one undo, a left difference and a refused surplus «spend».
    @Test func reconciliationWritesOneAdjustmentPerNamedDifferenceWithOneUndo() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.ingest("شراء بطاقة ائتمان\n*4444\n100.00 SAR\n2026-10-16 12:00")
        _ = try await f.run("money.confirmTransaction", ["id": .string(try f.transaction().id.uuidString)])
        let c = ModelContext(f.container), cycle = Cycle(); cycle.start = f.now.addingTimeInterval(-2 * 86400); cycle.expectedEnd = f.now.addingTimeInterval(28 * 86400); cycle.dailyAllowanceMinor = 40_000; c.insert(cycle)
        let other = MadarData.Category(); other.name = "أخرى"; c.insert(other); try c.save()
        #expect(try f.basis().inAccountMinor == 2_010_000); #expect(try f.basis().owedMinor == 10_000); #expect(try f.basis().netMinor == 2_000_000)
        func line(_ key: String, _ id: UUID, _ expected: Int, _ observed: Int, _ name: String? = nil) -> MadarCore.JSONValue {
            var row: [String: MadarCore.JSONValue] = [key: .string(id.uuidString), "expectedMinor": .string(String(expected)), "observedMinor": .string(String(observed))]
            if let name { row["name"] = .string(name) }
            return .object(row)
        }
        let rows: MadarCore.JSONValue = .array([line("accountID", f.bank, 2_000_000, 1_968_000, "missedSpend"), line("cardID", f.credit, 10_000, 22_000, "unexplained"), line("accountID", f.cash, 10_000, 10_000)])
        let command = UUID()
        let first = try await f.run("money.reconcile", ["rows": rows], id: command)
        #expect(first.status == .applied); #expect(first.undoToken == command)
        #expect(try await f.run("money.reconcile", ["rows": rows], id: command) == first, "A replay writes nothing")
        // Cash −320.00, debt +120.00: «لك فعلًا» falls by 440.00 (2000000 − 44000).
        #expect(try f.basis().inAccountMinor == 1_978_000); #expect(try f.basis().owedMinor == 22_000); #expect(try f.basis().netMinor == 1_956_000)
        let read = ModelContext(f.container)
        let records = try read.fetch(FetchDescriptor<Reconciliation>()).filter { $0.deletedAt == nil }
        #expect(records.count == 3)
        let bankRecord = try #require(records.first { $0.accountID == f.bank })
        #expect(bankRecord.expectedMinor == 2_000_000); #expect(bankRecord.observedMinor == 1_968_000); #expect(bankRecord.deltaMinor == -32_000)
        #expect(bankRecord.resolution == "unrecordedSpend")
        #expect(records.first { $0.cardID == f.credit }?.resolution == "adjust")
        let cashRecord = try #require(records.first { $0.accountID == f.cash })
        #expect(cashRecord.resolution == "adjust" && cashRecord.adjustmentTransactionID == nil, "A match is recorded without a movement")
        let adjustments = try read.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.kind == "adjustment" }
        #expect(adjustments.count == 2)
        let missed = try #require(adjustments.first { $0.fromAccountID == f.bank })
        #expect(missed.amountMinor == 32_000); #expect(missed.categoryID == other.id); #expect(missed.cycleID == cycle.id)
        let repo = MoneyRepository(context: read)
        let missedEffect = try repo.effect(of: missed), cardEffect = try repo.effect(of: try #require(adjustments.first { $0.cardID == f.credit }))
        #expect(missedEffect.cashMinor == -32_000); #expect(missedEffect.debtMinor == 0); #expect(missedEffect.budgetChargeMinor == 32_000)
        #expect(cardEffect.cashMinor == 0); #expect(cardEffect.debtMinor == 12_000); #expect(cardEffect.budgetChargeMinor == 0)
        // «مصروف لم يُسجَّل» is one daily spend allocation in the open cycle; the unexplained card difference has none.
        let spend = try repo.allocationRows(transactionID: missed.id)
        #expect(spend.count == 1); #expect(spend.first?.target == .daily); #expect(spend.first?.amountMinor == -32_000); #expect(spend.first?.cycleID == cycle.id.uuidString)
        #expect(try repo.cycle(at: f.now)?.headline.todaySpentMinor == 32_000)
        // The book moved: the same lines again are stale and write nothing.
        #expect(try await f.run("money.reconcile", ["rows": rows]).status == .rejected)
        // One undo returns the cash, the debt and every record.
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try f.basis().inAccountMinor == 2_010_000); #expect(try f.basis().owedMinor == 10_000)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Reconciliation>()).allSatisfy { $0.deletedAt != nil })
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.kind == "adjustment" }.allSatisfy { $0.deletedAt != nil })
        // No name leaves the difference open: a record, no movement, the book unchanged.
        #expect(try await f.run("money.reconcile", ["rows": .array([line("accountID", f.bank, 2_000_000, 1_990_000)])]).status == .applied)
        #expect(try f.basis().inAccountMinor == 2_010_000)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Reconciliation>()).first { $0.deletedAt == nil }?.resolution == "leave")
        // A surplus is never spending; one bad line rejects the whole command.
        #expect(try await f.run("money.reconcile", ["rows": .array([line("accountID", f.bank, 2_000_000, 2_100_000, "missedSpend")])]).status == .rejected)
        #expect(!MoneyCommandPayload.validate(name: "money.reconcile", payload: ["rows": .array([line("accountID", f.bank, 1, 1), line("accountID", f.bank, 1, 2)])]))
        #expect(!MoneyCommandPayload.validate(name: "money.reconcile", payload: ["rows": .array([.object(["accountID": .string(f.bank.uuidString), "cardID": .string(f.credit.uuidString), "expectedMinor": .string("1"), "observedMinor": .string("1")])])]))
        #expect(!MoneyCommandPayload.validate(name: "money.reconcile", payload: ["rows": .array([line("accountID", f.bank, 1, -1)])]))
    }

    @Test func installmentReconciliationLinksProviderCheckWithoutChangingScheduleOrSpending() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), obligation = Obligation()
        obligation.kind = "installment"; obligation.name = "synthetic purchase"; obligation.provider = "Tamara"
        obligation.currency = "SAR"; obligation.totalMinor = 120_000; context.insert(obligation)
        for (index, amount, paid) in [(1, 40_000, 10_000), (2, 40_000, 0), (3, 40_000, 0)] {
            let item = InstallmentItem(); item.obligationID = obligation.id; item.seq = index
            item.amountMinor = amount; item.paidMinor = paid; item.dueDate = f.now.addingTimeInterval(Double(index * 86_400)); context.insert(item)
        }
        try context.save()
        let row: MadarCore.JSONValue = .object([
            "obligationID": .string(obligation.id.uuidString),
            "expectedMinor": .string("110000"), "observedMinor": .string("125000")
        ])
        let command = UUID()
        #expect(try await f.run("money.reconcile", ["rows": .array([row])], id: command).status == .applied)
        let read = ModelContext(f.container)
        let reconciliation = try #require(read.fetch(FetchDescriptor<Reconciliation>()).first { $0.deletedAt == nil })
        #expect(reconciliation.obligationID == obligation.id && reconciliation.accountID == nil && reconciliation.cardID == nil)
        #expect(reconciliation.expectedMinor == 110_000 && reconciliation.observedMinor == 125_000 && reconciliation.deltaMinor == 15_000)
        #expect(reconciliation.resolution == "leave" && reconciliation.adjustmentTransactionID == nil)
        #expect(try read.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.kind == "adjustment" }.isEmpty)
        #expect(try read.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.obligationID == obligation.id }.map(\.paidMinor).sorted() == [0, 0, 10_000])
        let falseSpend: MadarCore.JSONValue = .object([
            "obligationID": .string(obligation.id.uuidString), "expectedMinor": .string("110000"),
            "observedMinor": .string("125000"), "name": .string("missedSpend")
        ])
        #expect(try await f.run("money.reconcile", ["rows": .array([falseSpend])]).status == .rejected)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Reconciliation>()).filter { $0.deletedAt == nil }.count == 1)
        #expect(try await f.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Reconciliation>()).allSatisfy { $0.deletedAt != nil })
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<InstallmentItem>()).filter { $0.obligationID == obligation.id }.map(\.paidMinor).sorted() == [0, 0, 10_000])
    }
    /// M5-V19 «الحسابات»: F06 (an account that is not mine stays out of «لك فعلًا», its messages kept as ignored), RM5
    /// (last 4 tells accounts of one bank apart) and the frozen checkpoint once movements refer to an account.
    @Test func accountsOwnershipLast4AndCheckpoint() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        func account(_ id: UUID, name: String = "حساب الوالدة", bank: String = "Bank", kind: String = "current", ownership: String = "notMine", last4: String = "9999",
                     balance: Int = 1_420_000, at: String = "2026-10-14T00:00:00Z") -> [String: MadarCore.JSONValue] {
            ["id": .string(id.uuidString), "name": .string(name), "bank": .string(bank), "kind": .string(kind), "ownership": .string(ownership),
             "currency": .string("SAR"), "balanceMinor": .string(String(balance)), "balanceAt": .string(at), "last4": .string(last4)]
        }
        let mother = UUID(), before = try f.basis()
        #expect(try await f.run("money.saveAccount", account(mother)).status == .applied)
        #expect(try f.basis() == before, "Not mine: out of cash and «لك فعلًا»")
        // Its message is kept as ignored and writes no movement; the shared rule still attributes it to the account.
        _ = try await f.ingest("حوالة واردة\nإلى: 9999*\nمن: سالم\nمبلغ: 120 SAR\n2026-10-16 11:40")
        let c = ModelContext(f.container)
        let message = try #require(try c.fetch(FetchDescriptor<BankMessage>()).first { $0.text.contains("9999") })
        #expect(message.status == "ignored"); #expect(try c.fetch(FetchDescriptor<MoneyTransaction>()).isEmpty)
        let parsed = try JSONDecoder().decode(MoneyParsedFields.self, from: try #require(message.parsedJSON))
        let row = try #require(try c.fetch(FetchDescriptor<Account>()).first { $0.id == mother })
        #expect(MoneyAccountRules.matches(row, sender: message.sender, last4: parsed.last4))
        #expect(!MoneyAccountRules.matches(row, sender: "Other bank", last4: parsed.last4))
        // No movement refers to it, so it may become mine (earlier ignored messages stay ignored).
        #expect(try await f.run("money.saveAccount", account(mother, ownership: "mine")).status == .applied)
        #expect(try f.basis().inAccountMinor == before.inAccountMinor + 1_420_000)
        #expect(try c.fetch(FetchDescriptor<BankMessage>()).first { $0.id == message.id }?.status == "ignored")

        // RM5: the same last 4 at the same bank is refused; at another bank it is a different account.
        #expect(try await f.run("money.saveAccount", account(UUID(), name: "نسخة", last4: "9999")).status == .rejected)
        #expect(try await f.run("money.saveAccount", account(UUID(), name: "بنك آخر", bank: "Other", last4: "9999")).status == .applied)

        // The current account has movements through its cards: ownership, kind and the opening balance are fixed; a new name is fine.
        _ = try await f.ingest("شراء مدى Apple Pay\nبطاقة *3333\n42.00 SAR\nلدى: مقهى\n2026-10-16 09:05")
        let current = account(f.bank, name: "current", ownership: "mine", last4: "1111", balance: 2_000_000)
        #expect(try MoneyAccountRules.hasMovements(f.bank, in: ModelContext(f.container)))
        var flip = current; flip["ownership"] = .string("notMine")
        var kind = current; kind["kind"] = .string("savings")
        var rebased = current; rebased["balanceMinor"] = .string("1")
        for payload in [flip, kind, rebased] { #expect(try await f.run("money.saveAccount", payload).status == .rejected) }
        var renamed = current; renamed["name"] = .string("الراجحي الجاري")
        #expect(try await f.run("money.saveAccount", renamed).status == .applied)
        let referenced = try #require(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).first)
        #expect(try await f.run("money.deleteTransaction", ["id": .string(referenced.id.uuidString)]).status == .applied)
        #expect(try MoneyAccountRules.hasMovements(f.bank, in: ModelContext(f.container)), "An undoable tombstone still fixes the checkpoint")
        #expect(try await f.run("money.saveAccount", kind).status == .rejected)
        let legacyContext = ModelContext(f.container)
        let legacy = try #require(try legacyContext.fetch(FetchDescriptor<Account>()).first { $0.id == f.bank })
        legacy.balanceAt = nil; try legacyContext.save()
        #expect(try await f.run("money.saveAccount", renamed).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Account>()).first { $0.id == f.bank }?.balanceAt == nil, "Renaming a legacy account never invents a checkpoint")
    }
    /// Item 34 / M5-V19: an account entered by mistake can be removed, only while nothing ever referred to it; one undo
    /// brings it back. Its card, a movement (even an undoable tombstone), a reconciliation or a sub-account keep it.
    @Test func removingAnUnusedAccountOnly() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        func account(_ id: UUID, last4: String) -> [String: MadarCore.JSONValue] {
            ["id": .string(id.uuidString), "name": .string("حساب زائد"), "bank": .string("Bank"), "kind": .string("savings"),
                "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string("50000"), "balanceAt": .string("2026-10-14T00:00:00Z"), "last4": .string(last4)]
        }
        let spare = UUID(), before = try f.basis()
        #expect(try await f.run("money.saveAccount", account(spare, last4: "7777")).status == .applied)
        #expect(try f.basis().inAccountMinor == before.inAccountMinor + 50_000)
        #expect(try await f.run("money.removeAccount", ["id": .string(spare.uuidString)], source: .shortcut).status != .applied, "App only")
        let removal = UUID()
        #expect(try await f.run("money.removeAccount", ["id": .string(spare.uuidString)], id: removal).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Account>()).first { $0.id == spare }?.deletedAt != nil, "A tombstone, not a hard delete")
        #expect(try f.basis() == before, "Its opening balance leaves «لك فعلًا»")
        #expect(try await f.run("money.removeAccount", ["id": .string(spare.uuidString)]).status == .rejected, "Already removed")
        #expect(try await f.run("system.undo", ["undoToken": .string(removal.uuidString)]).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Account>()).first { $0.id == spare }?.deletedAt == nil)
        #expect(try f.basis().inAccountMinor == before.inAccountMinor + 50_000)

        // Removed, then a new account takes the same bank and last 4: the undo is refused rather than leave two matches.
        let second = UUID()
        #expect(try await f.run("money.removeAccount", ["id": .string(spare.uuidString)], id: second).status == .applied)
        #expect(try await f.run("money.saveAccount", account(UUID(), last4: "7777")).status == .applied)
        let refused = try? await f.run("system.undo", ["undoToken": .string(second.uuidString)])
        #expect(refused?.status != .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Account>()).first { $0.id == spare }?.deletedAt != nil)

        // The fixture's current account carries cards; the cash wallet gains a movement: both stay.
        #expect(try await f.run("money.removeAccount", ["id": .string(f.bank.uuidString)]).status == .rejected, "Cards refer to it")
        #expect(try MoneyAccountRules.removable(f.cash, in: ModelContext(f.container)))
        #expect(try await f.run("money.logExpense", ["amountMinor": .string("1500"), "currency": .string("SAR"), "fromAccountID": .string(f.cash.uuidString), "merchant": .string("مخبز")]).status == .applied)
        #expect(try MoneyAccountRules.hasMovements(f.cash, in: ModelContext(f.container)))
        #expect(try await f.run("money.removeAccount", ["id": .string(f.cash.uuidString)]).status == .rejected, "A movement refers to it")
        #expect(!MoneyCommandPayload.validate(name: "money.removeAccount", payload: ["id": .string(spare.uuidString), "force": .bool(true)]))
        #expect(!MoneyCommandPayload.validate(name: "money.removeAccount", payload: ["id": .string("not-a-uuid")]))
    }

    @Test func trackedWalletTopUpLinksBothSidesWhileUntrackedTopUpStaysSpending() async throws {
        let tracked = try MoneyFixture(); defer { tracked.clean() }; try await tracked.setup()
        let walletID = UUID(), context = ModelContext(tracked.container), wallet = Account()
        wallet.id = walletID; wallet.name = "محفظة برق"; wallet.bank = "برق"; wallet.kind = "wallet"; wallet.ownership = "mine"; wallet.tracked = true
        context.insert(wallet); try context.save()

        let text = "شراء إنترنت\nبطاقة:3333 ;مدى\nمبلغ:20.00 SAR\nلدى:barq\nفي:2026-10-16 14:00"
        #expect(try await tracked.ingest(text).status == .applied)
        let transfer = try tracked.transaction()
        #expect(transfer.kind == "transfer" && transfer.reviewState == "needsLook")
        #expect(transfer.fromAccountID == tracked.bank && transfer.toAccountID == walletID)
        #expect(transfer.counterparty == "barq")

        let untracked = try MoneyFixture(); defer { untracked.clean() }; try await untracked.setup()
        let other = Account(); other.name = "محفظة دراهم"; other.bank = "دراهم"; other.kind = "wallet"; other.ownership = "mine"; other.tracked = false
        let untrackedContext = ModelContext(untracked.container); untrackedContext.insert(other); try untrackedContext.save()
        #expect(try await untracked.ingest("شراء إنترنت\nبطاقة:3333 ;مدى\nمبلغ:20.00 SAR\nلدى:Drahim\nفي:2026-10-16 14:00").status == .applied)
        let expense = try untracked.transaction()
        #expect(expense.kind == "expense" && expense.reviewState == "needsLook")
        #expect(expense.fromAccountID == untracked.bank && expense.toAccountID == nil)
    }

    @Test func addFundsMessageStaysANeutralTransferAndMatchesConfiguredBankAlias() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == f.bank })
        account.bank = "مصرف الراجحي"; try context.save()
        #expect(MoneyAccountRules.matches(account, sender: "AlRajhiBank", last4: "1111"))

        let text = "Money added to account\nTo:1111*\nAmount:25.00 SAR\n2026-10-16 14:10"
        #expect(try await f.run("money.ingestBankMessage", ["text": .string(text), "sender": .string("AlRajhiBank")], source: .shortcut).status == .applied)
        let row = try f.transaction()
        #expect(row.kind == "transfer" && row.toAccountID == f.bank && row.reviewState == "needsLook")
    }

    @Test func explicitTransferDestinationImportsAsUnconfirmedDraft() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let balanceBefore = try f.basis().inAccountMinor
        let text = "تحويل 235.50 ريال إلى مستفيد تجريبي\n2026-10-16 14:10"
        #expect(try await f.ingest(text).status == .applied)

        let context = ModelContext(f.container)
        let message = try #require(try context.fetch(FetchDescriptor<BankMessage>()).first)
        let draft = try f.transaction()
        #expect(message.kind == BankMessageKind.transferOut.rawValue && message.status == "needsLook")
        #expect(draft.kind == "transfer" && draft.reviewState == "needsLook")
        #expect(draft.amountMinor == 23_550 && draft.currency == "SAR")
        #expect(draft.counterparty == "مستفيد تجريبي" && draft.toAccountID == nil)
        #expect(try f.basis().inAccountMinor == balanceBefore, "Parsing a transfer never changes the balance before confirmation")
    }

    @Test func depositedCashbackRoutesToChosenEnvelopeAndUndoRestoresDraft() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), envelope = Envelope(); envelope.name = "رحلة قادمة"; context.insert(envelope); try context.save()
        #expect(try await f.run("settings.set", ["settings": .object(["mal.cashbackDestination": .string(envelope.id.uuidString)])]).status == .applied)
        let before = try f.basis().inAccountMinor
        #expect(try await f.ingest("استرداد نقدي\nمبلغ: 35.00 SAR\n2026-10-16 13:00").status == .applied)
        let draft = try f.transaction(); #expect(draft.kind == "cashback"); #expect(draft.reviewState == "needsLook")
        let confirmation = UUID()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(draft.id.uuidString), "toAccountID": .string(f.bank.uuidString)], id: confirmation).status == .applied)
        let reader = ModelContext(f.container), landed = try #require(try reader.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == draft.id })
        #expect(landed.reviewState == "ok" && landed.toAccountID == f.bank)
        #expect(try f.basis().inAccountMinor == before + 3_500)
        let allocations = try MoneyRepository(context: reader).allocationRows(transactionID: draft.id)
        #expect(allocations.count == 1)
        #expect(allocations.contains { $0.target == .envelope(envelope.id.uuidString) && $0.amountMinor == 3_500 })
        let redeemed = try #require(reader.fetch(FetchDescriptor<CashbackEntry>()).first { $0.transactionID == draft.id && $0.kind == "redeemed" && $0.deletedAt == nil })
        #expect(redeemed.cardID == nil && redeemed.amountMinor == 3_500)
        #expect(try await f.run("system.undo", ["undoToken": .string(confirmation.uuidString)]).status == .applied)
        let restored = ModelContext(f.container)
        #expect(try f.transaction(draft.id).reviewState == "needsLook")
        #expect(try MoneyRepository(context: restored).allocationRows(transactionID: draft.id).isEmpty)
        #expect(try restored.fetch(FetchDescriptor<CashbackEntry>()).first { $0.id == redeemed.id }?.deletedAt != nil)
        #expect(try f.basis().inAccountMinor == before)
    }

    @Test func creditCardCashbackReducesDebtWithoutFundingAnEnvelope() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), envelope = Envelope(); envelope.name = "هدف"; context.insert(envelope); try context.save()
        #expect(try await f.run("settings.set", ["settings": .object(["mal.cashbackDestination": .string(envelope.id.uuidString)])]).status == .applied)
        #expect(try await f.ingest("استرداد نقدي بطاقة ائتمانية *4444\nمبلغ: 35.00 SAR\n2026-10-16 13:00").status == .applied)
        let draft = try f.transaction()
        #expect(draft.kind == "cashback" && draft.cardID == f.credit)
        #expect(try await f.run("money.confirmTransaction", ["id": .string(draft.id.uuidString)]).status == .applied)
        let reader = ModelContext(f.container), landed = try #require(try reader.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == draft.id })
        #expect(landed.toAccountID == nil)
        #expect(try MoneyRepository(context: reader).effect(of: landed).debtMinor == -3_500)
        #expect(try MoneyRepository(context: reader).allocationRows(transactionID: draft.id).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<CashbackEntry>()).contains { $0.transactionID == draft.id && $0.kind == "redeemed" && $0.deletedAt == nil })
    }

    @Test func depositedCashbackDefaultsToSurplus() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        #expect(try await f.ingest("استرداد نقدي\nمبلغ: 12.00 SAR\n2026-10-16 14:00").status == .applied)
        let draft = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(draft.id.uuidString), "toAccountID": .string(f.bank.uuidString)]).status == .applied)
        let reader = ModelContext(f.container), allocations = try MoneyRepository(context: reader).allocationRows(transactionID: draft.id)
        #expect(allocations.count == 1 && allocations[0].target == .surplus && allocations[0].amountMinor == 1_200)
    }

    @Test func depositedCashbackCanRouteToReserve() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container), reserve = Envelope(); reserve.name = "الاحتياطي"; reserve.role = "reserve"; context.insert(reserve); try context.save()
        #expect(try await f.run("settings.set", ["settings": .object(["mal.cashbackDestination": .string(reserve.id.uuidString)])]).status == .applied)
        #expect(try await f.ingest("استرداد نقدي\nمبلغ: 12.00 SAR\n2026-10-16 14:00").status == .applied)
        let draft = try f.transaction()
        #expect(try await f.run("money.confirmTransaction", ["id": .string(draft.id.uuidString), "toAccountID": .string(f.bank.uuidString)]).status == .applied)
        let reader = ModelContext(f.container), allocations = try MoneyRepository(context: reader).allocationRows(transactionID: draft.id)
        #expect(allocations.count == 1 && allocations[0].target == .reserve && allocations[0].amountMinor == 1_200)
    }
}

extension MoneyPersistenceTests {
    @Test func unknownCashIsExcludedUntilExplicitBalanceAndUndoRestoresUnknown() async throws {
        let f = try MoneyFixture(); defer { f.clean() }; try await f.setup()
        let context = ModelContext(f.container)
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == f.bank })
        account.balanceAt = nil; account.balanceMinor = 0; try context.save()
        let movement = MoneyTransaction(); movement.kind = "expense"; movement.reviewState = "ok"
        movement.fromAccountID = f.bank; movement.amountMinor = 4200; movement.homeAmountMinor = 4200
        movement.currency = "SAR"; movement.homeCurrency = "SAR"; movement.eventAt = f.now.addingTimeInterval(-300)
        context.insert(movement); try context.save()
        // Only the known cash wallet (100.00) enters cash; never the fictitious -42.00 account balance.
        #expect(try f.basis().inAccountMinor == 10000)
        var payload: [String: MadarCore.JSONValue] = ["id": .string(f.bank.uuidString), "name": .string("Renamed"), "bank": .string("Bank"), "kind": .string("current"),
            "ownership": .string("mine"), "currency": .string("SAR"), "balanceMinor": .string("0"), "balanceAt": .string(ISO8601DateFormatter().string(from: f.now)), "last4": .string("1111")]
        #expect(try await f.run("money.saveAccount", payload).status == .applied)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<Account>()).first { $0.id == f.bank }?.balanceAt == nil)
        payload["establishBalance"] = .bool(true); payload["balanceMinor"] = .string("9000")
        let result = try await f.run("money.saveAccount", payload)
        #expect(result.status == .applied)
        #expect(try f.basis().inAccountMinor == 19000)
        let token = try #require(result.undoToken)
        #expect(try await f.run("system.undo", ["undoToken": .string(token.uuidString)]).status == .applied)
        #expect(try f.basis().inAccountMinor == 10000)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<MoneyTransaction>()).contains { $0.id == movement.id && $0.deletedAt == nil })
    }
}
