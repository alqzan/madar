import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

/// Owner, 22 Nov 2026: a manual rate per currency, editing a confirmed movement, manual income and the user's own categories.
/// Expected values come from the owner's rules (a rate is history and never rewrites a recorded movement; an edit spreads the
/// budget charge over the same targets; income is neutral for the daily budget; a category a confirmed movement carries stays).
@MainActor private final class OwnerMoneyFixture {
    let root: URL, container: ModelContainer, bus: CommandBus
    let now = ISO8601DateFormatter().date(from: "2026-11-20T15:00:00+03:00")!
    let bank = UUID(), cash = UUID(), dollars = UUID(), shared = UUID()
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "OwnerMoney-\(UUID())")
        container = try MadarContainerFactory.makeLocal(at: root)
        bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func run(_ name: String, _ p: [String: MadarCore.JSONValue], id: UUID = UUID(), at: Date? = nil) async throws -> CommandOutcome {
        let instant = at ?? now
        return try await bus.execute(.init(commandID: id, name: name, payload: .object(p), source: .app, issuedAt: instant), now: instant)
    }
    func setup() async throws {
        for (id, kind, currency, balance, ownership, last4) in [(bank, "current", "SAR", 2_000_000, "mine", "1111"), (cash, "cash", "SAR", 10_000, "mine", "2222"),
                                                              (dollars, "savings", "USD", 10_000, "mine", "3333"), (shared, "current", "SAR", 5_000, "notMine", "4444")] {
            #expect(try await run("money.saveAccount", ["id": .string(id.uuidString), "name": .string(kind + currency), "bank": .string("Bank"),
                "kind": .string(kind), "ownership": .string(ownership), "currency": .string(currency), "balanceMinor": .string(String(balance)),
                "balanceAt": .string("2026-11-01T00:00:00Z"), "last4": .string(last4), "senderIDs": .array([.string("Bank")])]).status == .applied)
        }
    }
    var context: ModelContext { ModelContext(container) }
    var repository: MoneyRepository { MoneyRepository(context: context) }
    func transaction(_ id: UUID) throws -> MoneyTransaction {
        try #require(try context.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil })
    }
    func spends(_ id: UUID) throws -> [Int] {
        try context.fetch(FetchDescriptor<Allocation>()).filter { $0.transactionID == id && $0.deletedAt == nil && $0.kind == "spend" }
            .sorted { $0.idempotencyKey < $1.idempotencyKey }.map(\.amountMinor)
    }
    func expense(_ amount: Int, id: UUID = UUID(), extra: [String: MadarCore.JSONValue] = [:]) async throws -> UUID {
        var p: [String: MadarCore.JSONValue] = ["amountMinor": .string(String(amount)), "currency": .string("SAR"), "merchant": .string("بقالة الحي"), "method": .string("transfer"),
                                                "fromAccountID": .string(bank.uuidString),
                                                "eventAt": .string("2026-11-20T10:00:00+03:00")]
        p.merge(extra) { _, new in new }
        #expect(try await run("money.logExpense", p, id: id).status == .applied)
        return id
    }
}

@MainActor struct MoneyOwnerEditsTests {
    @Test func enteredRateIsHistoryAndNeverRewritesARecordedMovement() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        #expect(try f.repository.unratedAccountNames(at: f.now) == ["savingsUSD"])
        #expect(try f.repository.homeAccountBalances(at: f.now, skippingUnrated: true).contains { $0.account.id == f.dollars } == false)
        // The home currency and a malformed rate are refused.
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("SAR"), "rate": .string("1")]).status == .rejected)
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("USD"), "rate": .string("3,75")]).status == .rejected)
        let first = UUID(), earlier = f.now.addingTimeInterval(-86_400)
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("USD"), "rate": .string("3.75")], id: first, at: earlier).status == .applied)
        // 100.00 USD × 3.75 = 375.00 SAR.
        #expect(try f.repository.unratedAccountNames(at: f.now).isEmpty)
        #expect(try f.repository.homeAccountBalances(at: f.now).first { $0.account.id == f.dollars }?.homeMinor == 37_500)
        // A foreign purchase with no trip takes the entered rate and freezes it.
        let purchase = UUID()
        #expect(try await f.run("money.logExpense", ["amountMinor": .string("2000"), "currency": .string("USD"), "method": .string("transfer"),
            "fromAccountID": .string(f.bank.uuidString), "eventAt": .string("2026-11-20T09:00:00+03:00")], id: purchase).status == .applied)
        var row = try f.transaction(purchase)
        #expect(row.rateAtTime == "3.75" && row.rateSource == "manual" && row.homeAmountMinor == 7_500)
        // A later rate wins for later readings only; the purchase keeps its frozen amount, and a reading before it keeps 3.75.
        let second = UUID()
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("USD"), "rate": .string("4")], id: second).status == .applied)
        #expect(try f.repository.homeAccountBalances(at: f.now).first { $0.account.id == f.dollars }?.homeMinor == 40_000)
        #expect(try f.repository.manualRates(at: f.now.addingTimeInterval(-60))["USD"] == "3.75")
        row = try f.transaction(purchase)
        #expect(row.rateAtTime == "3.75" && row.homeAmountMinor == 7_500)
        // Undo removes the rate it added; the older one reads again.
        #expect(try await f.run("system.undo", ["undoToken": .string(second.uuidString)]).status == .applied)
        #expect(try f.repository.enteredRates().map(\.rateToHome) == ["3.75"])
        #expect(try f.repository.homeAccountBalances(at: f.now).first { $0.account.id == f.dollars }?.homeMinor == 37_500)
    }

    @Test func manualIncomeLandsInOneOwnAccountAndIsNeutralForTheDailyBudget() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        let before = try f.repository.homeAccountBalances(at: f.now, skippingUnrated: true).first { $0.account.id == f.bank }!.homeMinor
        let id = UUID()
        #expect(try await f.run("money.logIncome", ["amountMinor": .string("50000"), "toAccountID": .string(f.bank.uuidString), "merchant": .string("  مكافأة  "),
            "eventAt": .string("2026-11-20T11:00:00+03:00")], id: id).status == .applied)
        let row = try f.transaction(id)
        #expect(row.kind == "income" && row.source == "manual" && row.reviewState == "ok" && row.toAccountID == f.bank && row.merchant == "مكافأة" && !row.showInDiary)
        #expect(try f.spends(id).isEmpty)
        #expect(try f.repository.homeAccountBalances(at: f.now, skippingUnrated: true).first { $0.account.id == f.bank }!.homeMinor == before + 50_000)
        // Someone else's account is refused.
        #expect(try await f.run("money.logIncome", ["amountMinor": .string("100"), "toAccountID": .string(f.shared.uuidString)]).status == .rejected)
        #expect(try await f.run("system.undo", ["undoToken": .string(id.uuidString)]).status == .applied)
        #expect(try f.repository.homeAccountBalances(at: f.now, skippingUnrated: true).first { $0.account.id == f.bank }!.homeMinor == before)
    }

    @Test func editingAConfirmedPurchaseSpreadsTheChargeOverTheSameTargetsAndUndoes() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        let plain = try await f.expense(10_000)
        #expect(try f.spends(plain) == [-10_000])
        let edit = UUID()
        #expect(try await f.run("money.editTransaction", ["id": .string(plain.uuidString), "amountMinor": .string("8000")], id: edit).status == .applied)
        #expect(try f.transaction(plain).amountMinor == 8_000 && f.transaction(plain).homeAmountMinor == 8_000)
        #expect(try f.spends(plain) == [-8_000])
        #expect(try await f.run("system.undo", ["undoToken": .string(edit.uuidString)]).status == .applied)
        #expect(try f.transaction(plain).amountMinor == 10_000 && f.spends(plain) == [-10_000])

        // A split purchase keeps its targets in proportion: 30 envelope + 70 daily of 100 become 15 + 35 of 50.
        let c = f.context, envelope = Envelope(); envelope.name = "هدايا"; c.insert(envelope); try c.save()
        let split = try await f.expense(10_000, extra: ["allocations": .array([
            .object(["target": .string("envelope"), "targetID": .string(envelope.id.uuidString), "amountMinor": .number(3_000)]),
            .object(["target": .string("daily"), "amountMinor": .number(7_000)])])])
        #expect(try f.spends(split).sorted() == [-7_000, -3_000])
        #expect(try await f.run("money.editTransaction", ["id": .string(split.uuidString), "amountMinor": .string("5000")]).status == .applied)
        #expect(try f.spends(split).sorted() == [-3_500, -1_500])
        #expect(try f.context.fetch(FetchDescriptor<Envelope>()).first { $0.id == envelope.id }?.balanceMinor == -1_500)
    }

    @Test func editingLabelCategoryAndTimeFollowsTheRules() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.run("money.seedCategories", [:])
        let grocery = MoneyDefaultCategories.id("grocery")
        let id = try await f.expense(2_500)
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "merchant": .string("سوق الخضار"), "categoryID": .string(grocery.uuidString)]).status == .applied)
        var row = try f.transaction(id)
        #expect(row.merchant == "سوق الخضار" && row.categoryID == grocery && row.categorySource == "manual")
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "categoryID": .null]).status == .applied)
        #expect(try f.transaction(id).categoryID == nil)
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "categoryID": .string(UUID().uuidString)]).status == .rejected)
        // The same values again change nothing.
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "merchant": .string("سوق الخضار")]).status == .duplicate)
        // A new time moves the stored day; a time in the future is refused.
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "eventAt": .string("2026-11-19T10:00:00+03:00")]).status == .applied)
        row = try f.transaction(id)
        #expect(row.dayKey == "2026-11-19")
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "eventAt": .string("2026-11-21T10:00:00+03:00")]).status == .rejected)
        // A draft is confirmed, not edited.
        let draft = MoneyTransaction(); draft.kind = "expense"; draft.amountMinor = 100; draft.homeAmountMinor = 100; draft.reviewState = "needsLook"
        let c = f.context; c.insert(draft); try c.save()
        #expect(try await f.run("money.editTransaction", ["id": .string(draft.id.uuidString), "amountMinor": .string("200")]).status == .rejected)
        // An empty edit is refused at the boundary.
        #expect(!MoneyCommandPayload.validate(name: "money.editTransaction", payload: ["id": .string(id.uuidString)]))
    }

    @Test func amountAndTimeStayInsideTheOpenCycleTheyWereFiledIn() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        let iso = ISO8601DateFormatter(), c = f.context
        let previous = Cycle(); previous.start = iso.date(from: "2026-10-27T00:00:00+03:00")!; previous.end = iso.date(from: "2026-11-19T00:00:00+03:00")!
        let current = Cycle(); current.start = previous.end!
        c.insert(previous); c.insert(current); try c.save()
        let id = try await f.expense(4_000)
        #expect(try f.transaction(id).cycleID == current.id)
        // Moving the time into the previous cycle is refused; inside the same cycle it is fine.
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "eventAt": .string("2026-11-18T22:00:00+03:00")]).status == .rejected)
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "eventAt": .string("2026-11-19T08:00:00+03:00")]).status == .applied)
        // A closed cycle keeps its amounts; the label can still be corrected.
        let close = f.context; let open = try #require(try close.fetch(FetchDescriptor<Cycle>()).first { $0.id == current.id }); open.closedAt = f.now; try close.save()
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "amountMinor": .string("3000")]).status == .rejected)
        #expect(try await f.run("money.editTransaction", ["id": .string(id.uuidString), "merchant": .string("صيدلية")]).status == .applied)
        #expect(try f.transaction(id).amountMinor == 4_000 && f.spends(id) == [-4_000])
    }

    @Test func userCategoriesAreNamedOnceAndStayWhileAConfirmedMovementCarriesThem() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.run("money.seedCategories", [:])
        let gifts = UUID()
        #expect(try await f.run("money.saveCategory", ["name": .string(" هدايا ")], id: gifts).status == .applied)
        #expect(try f.context.fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == gifts }?.name == "هدايا")
        // The same name twice is refused, also against a seeded name.
        #expect(try await f.run("money.saveCategory", ["name": .string("هدايا")]).status == .rejected)
        #expect(try await f.run("money.saveCategory", ["name": .string("بقالة")]).status == .rejected)
        #expect(try await f.run("money.saveCategory", ["id": .string(gifts.uuidString), "name": .string("هدايا العائلة")]).status == .applied)
        // A confirmed movement keeps the category alive; an unused one goes with its limit, and undo brings both back.
        let used = try await f.expense(1_000, extra: ["categoryID": .string(gifts.uuidString), "categorySource": .string("manual")])
        #expect(try await f.run("money.removeCategory", ["id": .string(gifts.uuidString)]).status == .rejected)
        #expect(try await f.run("money.deleteTransaction", ["id": .string(used.uuidString)]).status == .applied)
        #expect(try await f.run("money.setCategoryLimit", ["categoryID": .string(gifts.uuidString), "mode": .string("fixed"), "limitMinor": .number(5_000)]).status == .applied)
        let removal = UUID()
        #expect(try await f.run("money.removeCategory", ["id": .string(gifts.uuidString)], id: removal).status == .applied)
        #expect(try f.context.fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == gifts }?.deletedAt != nil)
        #expect(try f.context.fetch(FetchDescriptor<CategoryLimit>()).filter { $0.categoryID == gifts && $0.deletedAt == nil }.isEmpty)
        #expect(try await f.run("system.undo", ["undoToken": .string(removal.uuidString)]).status == .applied)
        #expect(try f.context.fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == gifts }?.deletedAt == nil)
        #expect(try f.context.fetch(FetchDescriptor<CategoryLimit>()).contains { $0.categoryID == gifts && $0.deletedAt == nil })
    }

    // Review fixes (22 Nov 2026).
    @Test func aMovementDatedBeforeTheFirstRateTakesTheLatestRateKnownNow() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        let payload: [String: MadarCore.JSONValue] = ["amountMinor": .string("1000"), "currency": .string("USD"), "method": .string("transfer"),
                                                      "fromAccountID": .string(f.bank.uuidString), "eventAt": .string("2026-11-19T09:00:00+03:00")]
        #expect(try await f.run("money.logExpense", payload).status == .rejected)
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("USD"), "rate": .string("3.75")]).status == .applied)
        let id = UUID()
        #expect(try await f.run("money.logExpense", payload, id: id).status == .applied)
        #expect(try f.transaction(id).rateAtTime == "3.75" && f.transaction(id).homeAmountMinor == 3_750)
        // An absurd rate that would overflow a large balance is refused.
        #expect(try await f.run("money.setCurrencyRate", ["currency": .string("EUR"), "rate": .string("900000000000000")]).status == .rejected)
    }

    @Test func amountsThatOtherFiguresLeanOnStayFixed() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        // Left out of the budget: lifting the stamp needs the recorded figure.
        let excluded = try await f.expense(10_000)
        #expect(try await f.run("money.setBudgetExclusion", ["id": .string(excluded.uuidString), "excluded": .bool(true), "expectedExcluded": .bool(false)]).status == .applied)
        #expect(try await f.run("money.editTransaction", ["id": .string(excluded.uuidString), "amountMinor": .string("8000")]).status == .rejected)
        #expect(try await f.run("money.editTransaction", ["id": .string(excluded.uuidString), "merchant": .string("هدية")]).status == .applied)
        // Spread by a big-expense plan.
        let planned = try await f.expense(9_000), c = f.context
        let plan = EnvelopePlan(); plan.id = planned; plan.kind = "repay"; plan.repaymentTotalMinor = 9_000; c.insert(plan); try c.save()
        #expect(try await f.run("money.editTransaction", ["id": .string(planned.uuidString), "amountMinor": .string("12000")]).status == .rejected)
        // On or before the account's latest reconciliation.
        let squared = try await f.expense(2_000)
        let r = f.context, record = Reconciliation(); record.accountID = f.bank; record.at = f.now.addingTimeInterval(-3_600); r.insert(record); try r.save()
        #expect(try await f.run("money.editTransaction", ["id": .string(squared.uuidString), "amountMinor": .string("2500")]).status == .rejected)
        // Across the account's opening balance date (1 Nov) the balance would change silently.
        let fresh = try OwnerMoneyFixture(); defer { fresh.clean() }; try await fresh.setup()
        let early = try await fresh.expense(1_500, extra: ["eventAt": .string("2026-11-02T10:00:00+03:00")])
        #expect(try await fresh.run("money.editTransaction", ["id": .string(early.uuidString), "eventAt": .string("2026-10-31T10:00:00+03:00")]).status == .rejected)
    }

    @Test func undoingAnEditNeverRewritesWhatCameToLeanOnIt() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        let purchase = try await f.expense(10_000), edit = UUID()
        #expect(try await f.run("money.editTransaction", ["id": .string(purchase.uuidString), "amountMinor": .string("15000")], id: edit).status == .applied)
        let c = f.context, refund = MoneyTransaction(); refund.kind = "refund"; refund.amountMinor = 15_000; refund.homeAmountMinor = 15_000; refund.reviewState = "ok"
        refund.relatedTransactionID = purchase; refund.eventAt = f.now; c.insert(refund); try c.save()
        await #expect(throws: MoneyCommandError.undoSuperseded) { try await f.run("system.undo", ["undoToken": .string(edit.uuidString)]) }
        #expect(try f.transaction(purchase).amountMinor == 15_000)

        // A movement brought back never points at a category removed since.
        _ = try await f.run("money.seedCategories", [:])
        let gifts = UUID()
        #expect(try await f.run("money.saveCategory", ["name": .string("هدايا")], id: gifts).status == .applied)
        let tagged = try await f.expense(1_000, extra: ["categoryID": .string(gifts.uuidString), "categorySource": .string("manual")]), deletion = UUID()
        #expect(try await f.run("money.deleteTransaction", ["id": .string(tagged.uuidString)], id: deletion).status == .applied)
        #expect(try await f.run("money.removeCategory", ["id": .string(gifts.uuidString)]).status == .applied)
        await #expect(throws: MoneyCommandError.undoSuperseded) { try await f.run("system.undo", ["undoToken": .string(deletion.uuidString)]) }
    }

    @Test func aPurchasesRefundsFollowItsNewCategory() async throws {
        let f = try OwnerMoneyFixture(); defer { f.clean() }; try await f.setup()
        _ = try await f.run("money.seedCategories", [:])
        let grocery = MoneyDefaultCategories.id("grocery")
        let purchase = try await f.expense(5_000)
        let c = f.context, refund = MoneyTransaction(); refund.kind = "refund"; refund.amountMinor = 1_000; refund.homeAmountMinor = 1_000; refund.reviewState = "ok"
        refund.relatedTransactionID = purchase; refund.eventAt = f.now; c.insert(refund); try c.save()
        #expect(try await f.run("money.editTransaction", ["id": .string(purchase.uuidString), "categoryID": .string(grocery.uuidString)]).status == .applied)
        #expect(try f.transaction(refund.id).categoryID == grocery)
        #expect(try await f.run("money.editTransaction", ["id": .string(refund.id.uuidString), "categoryID": .null]).status == .rejected)
    }
}
