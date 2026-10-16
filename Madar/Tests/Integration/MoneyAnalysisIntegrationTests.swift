import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import Madar

/// Expected values are worked by hand from the store below (M5-V14 DECISIONS), never read back from the loader.
@MainActor final class MoneyAnalysisIntegrationTests: XCTestCase {
    func testAnalysisReadsTheLogLedgerAndTheShelfDefinition() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyAnalysis-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        func at(_ day: String) -> Date { ISO8601DateFormatter().date(from: day + "T12:00:00+03:00")! }
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "core.faceIDLock": .string("none")])
        let account = Account(); account.balanceMinor = 1_000_000; account.balanceAt = at("2026-10-16"); c.insert(account)
        let envelope = Envelope(); envelope.name = "هدف"; c.insert(envelope)
        // September: 30 days of 100; October: 30 days of 100 from the 1st.
        let september = Cycle(); september.start = at("2026-09-01").addingTimeInterval(-43200); september.end = at("2026-10-01").addingTimeInterval(-43200); september.expectedEnd = september.end; september.closedAt = september.end; c.insert(september)
        let october = Cycle(); october.start = at("2026-10-01").addingTimeInterval(-43200); october.expectedEnd = at("2026-10-31").addingTimeInterval(-43200); october.incomeMinor = 300_000; c.insert(october)
        for (cycle, key) in [(september, "2026-09-01"), (october, "2026-10-01")] {
            let p = CyclePolicy(); p.cycleID = cycle.id; p.effectiveFromDayKey = key; p.allowanceMinor = 10_000; p.dailyRateMinor = 10_000; c.insert(p)
        }
        let food = MadarData.Category(); food.name = "مطاعم"; c.insert(food)
        let limit = CategoryLimit(); limit.categoryID = food.id; limit.mode = "fixed"; limit.limitMinor = 30_000; c.insert(limit)
        func spend(_ day: String, _ cycle: Cycle, daily: Int, envelope part: Int = 0) {
            let row = MoneyTransaction(); row.merchant = "مقهى"; row.categoryID = food.id; row.kind = "expense"; row.amountMinor = daily + part; row.homeAmountMinor = daily + part
            row.dayKey = day; row.eventAt = at(day); row.cycleID = cycle.id; row.fromAccountID = account.id; c.insert(row)
            for (target, amount) in [("daily", daily), ("envelope", part)] where amount > 0 {
                let a = Allocation(); a.transactionID = row.id; a.cycleID = cycle.id; a.target = target; if target == "envelope" { a.targetID = envelope.id }
                a.amountMinor = -amount; a.kind = "spend"; a.idempotencyKey = UUID().uuidString; c.insert(a)
            }
        }
        spend("2026-09-01", september, daily: 20_000); spend("2026-09-10", september, daily: 5_000)
        spend("2026-10-01", october, daily: 12_000); spend("2026-10-10", october, daily: 5_000, envelope: 2_000); spend("2026-10-16", october, daily: 3_000)
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
        XCTAssertEqual(row.spentMinor, 22_000, "V10 shelf definition: every spend allocation, envelope included")
        XCTAssertEqual(row.capMinor, 30_000)
        let shelf = try XCTUnwrap(try service.loadCategories().shelves.first { $0.name == "مطاعم" })
        XCTAssertEqual(row.spentMinor, shelf.spentMinor, "One number, one definition across التحليل and التصنيفات")
        XCTAssertEqual(row.capMinor, shelf.limitMinor)
        XCTAssertEqual(cycle.merchants.first, .init(name: "مقهى", amountMinor: 22_000, count: 3))
        XCTAssertEqual(cycle.metDays, 15); XCTAssertEqual(cycle.judgedDays, 16, "Only Oct 1 (12,000 > 10,000) is over")
        XCTAssertEqual(cycle.pace, .init(averageSpentMinor: 1_250, averageDailyMinor: 10_000, projectedLeftMinor: 262_500), "140,000 left × 30 ÷ 16")
        XCTAssertTrue(cycle.canGoBack)

        let week = try XCTUnwrap(try service.loadAnalysis(period: .week, at: at("2026-10-16")))
        XCTAssertEqual(week.first.description, "2026-10-10", "Saturday-first by default"); XCTAssertEqual(week.last.description, "2026-10-16")
        XCTAssertEqual(week.spentMinor, 8_000); XCTAssertEqual(week.allowanceMinor, 70_000)
        XCTAssertNil(week.comparison, "Oct 3–9 spent nothing: no percent against zero")
        let weekly = try XCTUnwrap(week.categories.first)
        XCTAssertEqual(weekly.spentMinor, 10_000); XCTAssertEqual(weekly.capMinor, 7_000, "30,000 × 16 ÷ 30 − 30,000 × 9 ÷ 30")
        XCTAssertNil(week.pace?.projectedLeftMinor)

        let earlier = try XCTUnwrap(try service.loadAnalysis(period: .cycle, offset: -1, at: at("2026-10-16")))
        XCTAssertEqual(earlier.first.description, "2026-09-01"); XCTAssertEqual(earlier.last.description, "2026-09-30")
        XCTAssertEqual(earlier.spentMinor, 25_000); XCTAssertEqual(earlier.allowanceMinor, 300_000)
        XCTAssertFalse(earlier.running); XCTAssertNil(earlier.comparison); XCTAssertFalse(earlier.canGoBack); XCTAssertNil(earlier.pace?.projectedLeftMinor)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Allocation>()).count, 6, "Reading writes nothing")
    }
}
