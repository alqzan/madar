import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

/// M5-V16: the jar read from a synthetic store. Months are Umm al-Qura 1448 (Hijri first by default): Muharram starts
/// 16 Jun 2026, Safar 15 Jul, Rabi I 14 Aug, Rabi II 12 Sep, Jumada I 12 Oct (the current month on 16 Oct).
@MainActor final class MoneyCashbackIntegrationTests: XCTestCase {
    func testJarCountsEachNumberOnceFromTheStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyCashback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00+03:00")! }
        let owned = Account(); owned.balanceMinor = 1_000_000; owned.balanceAt = at("2026-06-01"); c.insert(owned)
        let other = Account(); other.ownership = "notMine"; c.insert(other)
        let main = Card(); main.name = "الأساسية"; main.accountID = owned.id; main.cashbackBp = 50; c.insert(main)
        let travel = Card(); travel.name = "السفر"; travel.accountID = owned.id; travel.cashbackBp = 150; c.insert(travel)
        let debit = Card(); debit.name = "مدى"; debit.kind = "debit"; debit.accountID = owned.id; c.insert(debit)
        let theirs = Card(); theirs.name = "ليست لي"; theirs.accountID = other.id; theirs.cashbackBp = 1_000; c.insert(theirs)
        let grocery = MadarData.Category(); grocery.name = "بقالة"; c.insert(grocery)
        let food = MadarData.Category(); food.name = "مطاعم"; c.insert(food)
        @discardableResult func tx(_ card: Card, _ day: String, _ amount: Int, kind: String = "expense", category: MadarData.Category? = nil, related: UUID? = nil) -> MoneyTransaction {
            let t = MoneyTransaction(); t.kind = kind; t.cardID = card.id; t.amountMinor = amount; t.homeAmountMinor = amount; t.dayKey = day; t.eventAt = at(day)
            t.categoryID = category?.id; t.relatedTransactionID = related; t.method = "card"; c.insert(t); return t
        }
        tx(main, "2026-07-01", 200_000, category: grocery)                    // Muharram: 2,000 × 0.5% = 10.00
        let dinner = tx(main, "2026-08-20", 100_000, category: food)          // Rabi I
        tx(main, "2026-09-20", 40_000, kind: "refund", related: dinner.id)    // lands on Rabi I: 600 × 0.5% = 3.00
        tx(main, "2026-07-02", 10_000, kind: "fee")                           // fees earn nothing
        tx(main, "2026-06-10", 500_000, category: grocery)                    // 1447: another year
        tx(travel, "2026-09-15", 50_000)                                      // Rabi II: 500 × 1.5% = 7.50
        tx(debit, "2026-10-14", 30_000)                                       // unknown rate
        tx(theirs, "2026-09-01", 1_000_000)                                   // not mine
        let earned = CashbackEntry(); earned.cardID = travel.id; earned.kind = "earned"; earned.amountMinor = 999; earned.eventAt = at("2026-07-20"); c.insert(earned) // Safar, recorded
        // Landed: a movement with its redeemed row (once), and a redeemed row with no movement.
        let landed = MoneyTransaction(); landed.kind = "cashback"; landed.toAccountID = owned.id; landed.amountMinor = 800; landed.homeAmountMinor = 800; landed.dayKey = "2026-09-01"; landed.eventAt = at("2026-09-01"); c.insert(landed)
        let linked = CashbackEntry(); linked.cardID = main.id; linked.kind = "redeemed"; linked.amountMinor = 800; linked.transactionID = landed.id; linked.eventAt = at("2026-09-01"); c.insert(linked)
        let loose = CashbackEntry(); loose.cardID = travel.id; loose.kind = "redeemed"; loose.amountMinor = 100; loose.eventAt = at("2026-10-01"); c.insert(loose)
        try c.save()
        let before = try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).count
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let r = try XCTUnwrap(try AppMoneyService(app: app).loadCashback(at: at("2026-10-16")))

        XCTAssertEqual(r.months.count, 5, "Muharram to Jumada I 1448")
        XCTAssertTrue(r.yearTitle.hasSuffix("هـ")); XCTAssertTrue(r.yearSecondary.hasSuffix("م"))
        XCTAssertEqual(r.cards.map(\.name), ["الأساسية", "السفر", "مدى"], "Credit cards first; the other owner's card is out")
        XCTAssertEqual(r.jar.monthTotals, [1_000, 999, 300, 750, 0])
        XCTAssertEqual(r.cards.map(\.total.earnedMinor), [1_300, 1_749, nil])
        XCTAssertEqual(r.jar.earnedMinor, 3_049)
        XCTAssertEqual(r.jar.landedMinor, 900, "800 once (movement + its redeemed row) + 100 with no movement")
        XCTAssertEqual(r.jar.accumulatingMinor, 2_149); XCTAssertEqual(r.jar.headlineMinor, 3_049)
        XCTAssertEqual(r.jar.unknownCards, [debit.id.uuidString])
        // 3,049 over four complete months → 762 a month; 30.49 + 7.62 × 8 = 91.45.
        XCTAssertEqual(r.jar.yearEndMinor, 9_145)
        let s = try XCTUnwrap(r.switchSuggestion)
        XCTAssertEqual(s.to.name, "السفر")
        XCTAssertEqual(s.rows.map(\.title), ["بقالة", "مطاعم"])
        XCTAssertEqual(s.rows.map(\.gainMinor), [2_000, 600], "1% more on 2,000 and on 600 after the refund")
        XCTAssertEqual(s.totalMinor, 2_600)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>()).count, before, "Reading writes nothing")
    }
}
