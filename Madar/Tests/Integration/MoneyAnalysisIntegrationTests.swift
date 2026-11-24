import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import Madar

/// Expected values are worked by hand from the store below (M5-V14 DECISIONS), never read back from the loader.
@MainActor final class MoneyAnalysisIntegrationTests: XCTestCase {
    func testSafeCategoryMathKeepsExtremeMinorUnitsRepresentable() {
        XCTAssertEqual(MoneySafeArithmetic.ratio(Int.max, multiplier: 16, over: 30), 4_919_131_752_989_213_763)
        XCTAssertEqual(MoneySafeArithmetic.sum([Int.max, 1]), Int.max)
        XCTAssertEqual(MoneySafeArithmetic.percent(Int.max, of: 1), Int.max)
        XCTAssertEqual(MoneySafeArithmetic.percent(Int.max, of: Int.max, rounded: false), 100)
    }

    func testHomeAndShelvesAgreeOnCycleSpendingAndRecognizeCategoryProvenance() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyCategories-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T12:00:00+03:00"))
        let category = MadarData.Category()
        category.name = "مطاعم"
        context.insert(category)
        let limit = CategoryLimit()
        limit.categoryID = category.id
        limit.mode = "fixed"
        limit.limitMinor = 2_000
        limit.updatedAt = now
        context.insert(limit)
        let olderLimit = CategoryLimit()
        olderLimit.categoryID = category.id
        olderLimit.limitMinor = 500
        olderLimit.updatedAt = now.addingTimeInterval(-60)
        context.insert(olderLimit)
        let rule = MerchantRule()
        rule.pattern = BankDedupe.normalize("مقهى")
        rule.categoryID = category.id
        context.insert(rule)

        let inputs: [(String?, String, Int)] = [("learned", "مطعم", 100), ("manual", "مقهى", 200), (nil, "مقهى", 300)]
        let records = inputs.map { source, merchant, amount in
            let movement = MoneyTransaction()
            movement.eventAt = now
            movement.dayKey = "2026-10-16"
            movement.categoryID = category.id
            movement.categorySource = source
            movement.merchant = merchant
            movement.amountMinor = amount
            movement.homeAmountMinor = amount
            context.insert(movement)
            let allocation = Allocation()
            allocation.transactionID = movement.id
            allocation.kind = "spend"
            allocation.amountMinor = -amount
            allocation.idempotencyKey = UUID().uuidString
            context.insert(allocation)
            return (movement, allocation)
        }
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppMoneyService(app: app)
        XCTAssertEqual(try service.load(at: now).limits.first?.spentMinor, 0)
        XCTAssertEqual(try service.loadCategories(at: now).shelves.first?.spentMinor, 0)

        let cycle = Cycle()
        cycle.start = now.addingTimeInterval(-86_400)
        cycle.expectedEnd = now.addingTimeInterval(29 * 86_400)
        context.insert(cycle)
        let policy = CyclePolicy()
        policy.cycleID = cycle.id
        policy.effectiveFromDayKey = "2026-10-15"
        policy.allowanceMinor = 30_000
        policy.dailyRateMinor = 1_000
        context.insert(policy)
        for (movement, allocation) in records {
            movement.cycleID = cycle.id
            allocation.cycleID = cycle.id
        }
        try context.save()
        let shelf = try service.loadCategories(at: now)
        let currentLimits = try service.load(at: now).limits
        XCTAssertEqual(currentLimits.map(\.spentMinor), [600])
        XCTAssertEqual(currentLimits.map(\.limitMinor), [2_000])
        XCTAssertEqual(shelf.shelves.first?.spentMinor, 600)
        XCTAssertEqual(shelf.autoCategorized, 2, "Learned and legacy matching rows are automatic. A manual match stays manual.")

        limit.mode = "none"
        try context.save()
        XCTAssertTrue(try service.load(at: now).limits.isEmpty)
        XCTAssertNil(try service.loadCategories(at: now).shelves.first?.limitMinor)
        let analysis = try XCTUnwrap(try service.loadAnalysis(period: .cycle, at: now))
        let analyzedCategory = try XCTUnwrap(analysis.categories.first { $0.name == category.name })
        XCTAssertNil(analyzedCategory.capMinor)
    }

    func testAnalysisReadsTheLogLedgerAndTheShelfDefinition() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyAnalysis-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        func at(_ day: String) -> Date { ISO8601DateFormatter().date(from: day + "T12:00:00+03:00")! }
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian")])
        let account = Account(); account.balanceMinor = 1_000_000; account.balanceAt = at("2026-10-16"); c.insert(account)
        let untrackedAccount = Account(); untrackedAccount.ownership = "other"; untrackedAccount.tracked = false; c.insert(untrackedAccount)
        let envelope = Envelope(); envelope.name = "هدف"; c.insert(envelope)
        // September: 30 days of 100; October: 30 days of 100 from the 1st.
        let september = Cycle(); september.start = at("2026-09-01").addingTimeInterval(-43200); september.end = at("2026-10-01").addingTimeInterval(-43200); september.expectedEnd = september.end; september.closedAt = september.end; c.insert(september)
        let october = Cycle(); october.start = at("2026-10-01").addingTimeInterval(-43200); october.expectedEnd = at("2026-10-31").addingTimeInterval(-43200); october.incomeMinor = 300_000; c.insert(october)
        for (cycle, key) in [(september, "2026-09-01"), (october, "2026-10-01")] {
            let p = CyclePolicy(); p.cycleID = cycle.id; p.effectiveFromDayKey = key; p.allowanceMinor = 10_000; p.dailyRateMinor = 10_000; c.insert(p)
        }
        let food = MadarData.Category(); food.name = "مطاعم"; c.insert(food)
        let limit = CategoryLimit(); limit.categoryID = food.id; limit.mode = "fixed"; limit.limitMinor = 30_000; c.insert(limit)
        func spend(_ day: String, _ cycle: Cycle, daily: Int, envelope part: Int = 0, fromAccountID: UUID? = nil) {
            let row = MoneyTransaction(); row.merchant = "مقهى"; row.categoryID = food.id; row.kind = "expense"; row.amountMinor = daily + part; row.homeAmountMinor = daily + part
            row.dayKey = day; row.eventAt = at(day); row.cycleID = cycle.id; row.fromAccountID = fromAccountID ?? account.id; c.insert(row)
            for (target, amount) in [("daily", daily), ("envelope", part)] where amount > 0 {
                let a = Allocation(); a.transactionID = row.id; a.cycleID = cycle.id; a.target = target; if target == "envelope" { a.targetID = envelope.id }
                a.amountMinor = -amount; a.kind = "spend"; a.idempotencyKey = UUID().uuidString; c.insert(a)
            }
        }
        spend("2026-09-01", september, daily: 20_000); spend("2026-09-10", september, daily: 5_000)
        spend("2026-10-01", october, daily: 12_000); spend("2026-10-10", october, daily: 5_000, envelope: 2_000); spend("2026-10-16", october, daily: 3_000)
        // The analysis definition includes every confirmed transaction, even if the log excludes its untracked account.
        spend("2026-10-16", october, daily: 0, envelope: 4_000, fromAccountID: untrackedAccount.id)
        try c.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let service = AppMoneyService(app: app)

        let cycle = try XCTUnwrap(try service.loadAnalysis(period: .cycle, at: at("2026-10-16")))
        XCTAssertEqual(cycle.first.description, "2026-10-01"); XCTAssertEqual(cycle.last.description, "2026-10-30", "30 expected days from the 1st")
        XCTAssertEqual(cycle.spentMinor, 20_000, "12,000 + 5,000 + 3,000 from «يومك»; the envelope part is not the daily")
        XCTAssertEqual(cycle.allowanceMinor, 160_000, "16 elapsed days × 10,000")
        XCTAssertEqual(cycle.comparison?.percent, -20, "Like for like: Sep 1–16 spent 25,000; (20,000 − 25,000) ÷ 25,000")
        XCTAssertTrue(cycle.comparison?.label.hasPrefix("عن الأيام نفسها") == true)
        let row = try XCTUnwrap(cycle.categories.first { $0.name == "مطاعم" })
        XCTAssertEqual(row.spentMinor, 26_000, "V10 shelf definition: every spend allocation, including an untracked account and envelope funding")
        XCTAssertEqual(row.capMinor, 30_000)
        let shelf = try XCTUnwrap(try service.loadCategories().shelves.first { $0.name == "مطاعم" })
        XCTAssertEqual(row.spentMinor, shelf.spentMinor, "One number, one definition across التحليل and التصنيفات")
        XCTAssertEqual(row.capMinor, shelf.limitMinor)
        XCTAssertEqual(cycle.merchants.first, .init(name: "مقهى", amountMinor: 26_000, count: 4))
        XCTAssertEqual(cycle.metDays, 15); XCTAssertEqual(cycle.judgedDays, 16, "Only Oct 1 (12,000 > 10,000) is over")
        XCTAssertEqual(cycle.pace, .init(averageSpentMinor: 1_250, averageDailyMinor: 10_000, projectedLeftMinor: 262_500), "140,000 left × 30 ÷ 16")
        XCTAssertTrue(cycle.canGoBack)

        let offMainResult = try await service.loadAnalysisOffMain(period: .cycle, at: at("2026-10-16"))
        let offMainCycle = try XCTUnwrap(offMainResult)
        XCTAssertEqual(offMainCycle.first, cycle.first)
        XCTAssertEqual(offMainCycle.last, cycle.last)
        XCTAssertEqual(offMainCycle.spentMinor, cycle.spentMinor)
        XCTAssertEqual(offMainCycle.allowanceMinor, cycle.allowanceMinor)
        XCTAssertEqual(offMainCycle.comparison, cycle.comparison)
        XCTAssertEqual(offMainCycle.categories, cycle.categories)
        XCTAssertEqual(offMainCycle.merchants, cycle.merchants)
        XCTAssertEqual(offMainCycle.pace, cycle.pace)

        let week = try XCTUnwrap(try service.loadAnalysis(period: .week, at: at("2026-10-16")))
        XCTAssertEqual(week.first.description, "2026-10-10", "Saturday-first by default"); XCTAssertEqual(week.last.description, "2026-10-16")
        XCTAssertEqual(week.spentMinor, 8_000); XCTAssertEqual(week.allowanceMinor, 70_000)
        XCTAssertNil(week.comparison, "Oct 3–9 spent nothing: no percent against zero")
        let weekly = try XCTUnwrap(week.categories.first)
        XCTAssertEqual(weekly.spentMinor, 14_000, "Includes the 4,000 envelope spend from the untracked account")
        XCTAssertEqual(weekly.capMinor, 7_000, "30,000 × 16 ÷ 30 − 30,000 × 9 ÷ 30")
        XCTAssertNil(week.pace?.projectedLeftMinor)

        let earlier = try XCTUnwrap(try service.loadAnalysis(period: .cycle, offset: -1, at: at("2026-10-16")))
        XCTAssertEqual(earlier.first.description, "2026-09-01"); XCTAssertEqual(earlier.last.description, "2026-09-30")
        XCTAssertEqual(earlier.spentMinor, 25_000); XCTAssertEqual(earlier.allowanceMinor, 300_000)
        XCTAssertFalse(earlier.running); XCTAssertNil(earlier.comparison); XCTAssertFalse(earlier.canGoBack); XCTAssertNil(earlier.pace?.projectedLeftMinor)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Allocation>()).count, 7, "Reading writes nothing")

        limit.limitMinor = Int.max
        let secondCategory = MadarData.Category(); secondCategory.name = "بقالة"; secondCategory.order = 1; c.insert(secondCategory)
        let secondLimit = CategoryLimit(); secondLimit.categoryID = secondCategory.id; secondLimit.mode = "fixed"; secondLimit.limitMinor = 1; c.insert(secondLimit)
        try c.save()
        let extreme = try service.loadCategories()
        XCTAssertEqual(extreme.totalLimitsMinor, Int.max, "The aggregate clamps at Int.max instead of overflowing")
        let extremeShelf = try XCTUnwrap(extreme.shelves.first { $0.id == food.id })
        XCTAssertEqual(extremeShelf.limitMinor, Int.max)
        XCTAssertGreaterThanOrEqual(extremeShelf.expectedTodayMinor ?? -1, 0)
    }
}
