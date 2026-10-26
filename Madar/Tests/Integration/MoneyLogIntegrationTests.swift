import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import Madar

@MainActor final class MoneyLogIntegrationTests: XCTestCase {
    func testPastedBankParserKeepsAllBlocksAndReportsOversizedOnes() {
        let valid = "شراء مدى\n*3333\n18.00 SAR\nلدى: Coffee\n2026-10-16 12:00"
        let tooLong = String(repeating: "x", count: 2001)
        let paste = (Array(repeating: valid, count: 501) + [tooLong]).joined(separator: "\n\n")

        let parsed = AppMoneyService.pastedMessages(paste)

        XCTAssertEqual(parsed.messages.count, 501)
        XCTAssertTrue(parsed.messages.allSatisfy { $0 == valid })
        XCTAssertEqual(parsed.oversizedCount, 1)
    }

    func testLogUsesOriginalRefundDayActualDripsAndNeutralPayments() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyLog-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        func at(_ day: String) -> Date { ISO8601DateFormatter().date(from: day + "T12:00:00+03:00")! }
        let now = at("2026-10-16")
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "core.faceIDLock": .string("none")])
        let account = Account(); account.balanceMinor = 100_000; account.balanceAt = now; c.insert(account)
        let debit = Card(); debit.kind = "debit"; debit.accountID = account.id; c.insert(debit)
        let credit = Card(); credit.accountID = account.id; c.insert(credit)
        let envelope = Envelope(); envelope.name = "هدف"; c.insert(envelope)
        let cycle = Cycle(); cycle.start = at("2026-10-01").addingTimeInterval(-43200); cycle.expectedEnd = at("2026-10-31"); c.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = "2026-10-01"; policy.allowanceMinor = 40_000; policy.dailyRateMinor = 40_000; c.insert(policy)
        let zero = CyclePolicy(); zero.cycleID = cycle.id; zero.effectiveFromDayKey = "2026-10-16"; zero.allowanceMinor = 0; zero.dailyRateMinor = 0; c.insert(zero)
        func tx(_ kind: String, _ amount: Int, _ day: String, card: UUID? = nil) -> MoneyTransaction {
            let row = MoneyTransaction(); row.kind = kind; row.amountMinor = amount; row.homeAmountMinor = amount; row.dayKey = day; row.eventAt = at(day); row.cardID = card; row.cycleID = cycle.id
            if kind == "refund" { row.toAccountID = account.id } else { row.fromAccountID = account.id }; c.insert(row); return row
        }
        let original = tx("expense", 100, "2026-10-15", card: debit.id)
        let refund = tx("refund", 40, "2026-10-16", card: debit.id); refund.relatedTransactionID = original.id
        let ignored = tx("expense", 500, "2026-10-15", card: debit.id); ignored.ignoredFromBudget = true
        _ = tx("cardPayment", 1_000, "2026-10-16", card: credit.id)
        let pending = tx("expense", 200, "2026-10-16", card: debit.id); pending.reviewState = "needsLook"
        for (row, target, amount, kind) in [(original, "daily", -60, "spend"), (original, "envelope", -40, "spend"), (refund, "daily", 24, "refund"), (refund, "envelope", 16, "refund")] {
            let a = Allocation(); a.transactionID = row.id; a.cycleID = cycle.id; a.target = target; if target == "envelope" { a.targetID = envelope.id }; a.amountMinor = amount; a.kind = kind; a.idempotencyKey = UUID().uuidString; c.insert(a)
        }
        let plan = UUID()
        for (target, amount, suffix) in [("daily", -1_300, "from"), ("envelope", 1_300, "to")] {
            let a = Allocation(); a.target = target; if target == "envelope" { a.targetID = envelope.id }; a.amountMinor = amount; a.kind = "fund"; a.cycleID = cycle.id; a.idempotencyKey = "daily:\(cycle.id):\(plan):2026-10-15:\(suffix)"; c.insert(a)
        }
        try c.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let reading = try AppMoneyService(app: app).loadLog(at: now)
        let yesterday = try XCTUnwrap(reading.days.first { $0.day.description == "2026-10-15" }), today = try XCTUnwrap(reading.days.first { $0.day.description == "2026-10-16" })
        XCTAssertEqual(yesterday.spentMinor, 36, "60 − 24: refund returns to original day")
        XCTAssertEqual(yesterday.otherMinor, 524, "40 − 16 + 500 ignored")
        XCTAssertEqual(yesterday.cashOutMinor, 600, "100 + 500 actual account outflows")
        XCTAssertEqual(yesterday.dailyMinor, 38_700, "40000 − actual saved drip 1300, even without a live plan")
        XCTAssertEqual(yesterday.within, .met)
        XCTAssertEqual(today.spentMinor, 0, "Payment and pending draft do not spend the daily")
        XCTAssertEqual(today.cashOutMinor, 1_000)
        XCTAssertEqual(reading.neutralTransfersMinor, 1_000, "The card payment is shown once as budget-neutral")
        XCTAssertEqual(today.dailyMinor, 0, "L05: zero is known, not missing")
        XCTAssertEqual(today.within, .pending)
        XCTAssertNil(reading.days.first { $0.day.description == "2026-10-17" }?.dailyMinor)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).count, 5)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Allocation>()).count, 6)
        XCTAssertEqual(original.dayKey, "2026-10-15")
    }
}
