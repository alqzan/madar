import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands
@testable import Madar

@MainActor final class MoneyFundingProjectionTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private func at(_ day: String) -> Date { ISO8601DateFormatter().date(from: day + "T12:00:00+03:00")! }
    private func run(_ body: (ModelContext, AppSession, AppMoneyService, Cycle) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FundingForecast-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.faceIDLock": .string("none"),
            "mal.dailyAllowance": .object(["mode": .string("fixed"), "amountMinor": .number(40_000), "percentBp": .null]), "mal.salaryDay": .number(27),
            "mal.cycleCalendar": .string("gregorian")])
        let cycle = Cycle(); cycle.start = try GregorianDay("2026-10-01").date(in: zone)
        cycle.expectedEnd = try GregorianDay("2026-10-27").date(in: zone); cycle.incomeMinor = 1_500_000; c.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = "2026-10-01"; policy.allowanceMinor = 40_000; policy.dailyRateMinor = 40_000; c.insert(policy)
        try c.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        try body(c, app, AppMoneyService(app: app), cycle)
    }
    private func project(_ c: ModelContext, _ app: AppSession, _ service: AppMoneyService, today: String = "2026-10-16", surplus: Int = 0) throws -> [UUID: MoneyGoalFundingProjection] {
        let envelopes = try c.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let plans = try c.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let allocations = try c.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let balances = Dictionary(uniqueKeysWithValues: envelopes.map { envelope in (envelope.id, allocations.filter { $0.targetID == envelope.id }.reduce(0) { $0 + $1.amountMinor }) })
        return try service.fundingProjections(cycle: MoneyRepository(context: c).cycle(at: at(today)), today: GregorianDay(today), now: at(today), zone: zone,
            envelopes: envelopes, plans: plans, allocations: allocations, balances: balances, surplus: surplus, reserve: 0)
    }
    private func goal(_ c: ModelContext, balance: Int = 0, target: Int = 60_000) -> Envelope {
        let envelope = Envelope(); envelope.role = "goal"; envelope.name = "هدية"; envelope.targetMinor = target; c.insert(envelope)
        let a = Allocation(); a.target = "envelope"; a.targetID = envelope.id; a.kind = "fund"; a.amountMinor = balance; c.insert(a)
        return envelope
    }
    func testDailyGoalUsesRemainingFundingAndDoesNotWriteForecastAllocations() throws {
        try run { c, app, service, cycle in
            let envelope = goal(c, balance: 25_200)
            let plan = EnvelopePlan(); plan.id = envelope.id; plan.envelopeID = envelope.id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = 1300; plan.startDayKey = "2026-10-01"; c.insert(plan)
            // Sixteen already-accrued drops are part of today's 46,000 balance, not an extra opening deposit.
            let accrued = Allocation(); accrued.target = "envelope"; accrued.targetID = envelope.id; accrued.kind = "fund"
            accrued.cycleID = cycle.id; accrued.idempotencyKey = "daily:" + plan.id.uuidString + ":2026-10-16"; accrued.amountMinor = 20_800; c.insert(accrued)
            try c.save()
            let count = try c.fetchCount(FetchDescriptor<Allocation>())
            let result = try XCTUnwrap(project(c, app, service)[envelope.id])
            XCTAssertEqual(result.balance(on: try .init("2026-10-16")), 46_000)
            XCTAssertEqual(result.balance(on: try .init("2026-10-26")), 59_000)
            XCTAssertEqual(result.balance(on: try .init("2026-10-27")), 60_000)
            XCTAssertEqual(result.balance(on: try .init("2026-12-27")), 60_000)
            XCTAssertEqual(try c.fetchCount(FetchDescriptor<Allocation>()), count)
            XCTAssertEqual(plan.perPaycheckMinor, 1300)
        }
    }
    func testFlexibleSalaryDatesAndInclusivePlanExpiryWithFiniteSurplus() throws {
        try run { c, app, service, cycle in
            cycle.expectedEnd = try GregorianDay("2026-10-20").date(in: zone)
            _ = try SettingsStore(context: c).stage(["mal.salarySchedule": .object(["enabled": .bool(true), "every": .number(2), "unit": .string("week"), "firstDayKey": .string("2026-10-20")])])
            let envelope = goal(c)
            let salary = EnvelopePlan(); salary.envelopeID = envelope.id; salary.perPaycheckMinor = 10_000; salary.untilDate = try GregorianDay("2026-11-03").date(in: zone); c.insert(salary)
            let surplus = EnvelopePlan(); surplus.envelopeID = envelope.id; surplus.source = "surplus"; surplus.perPaycheckMinor = 50_000; c.insert(surplus)
            try c.save()
            let result = try XCTUnwrap(project(c, app, service, surplus: 20_000)[envelope.id])
            let home = try service.load(at: at("2026-10-16"))
            XCTAssertEqual(Array(home.salaryDates.prefix(3)).map(\.description), ["2026-10-20", "2026-11-03", "2026-11-17"])
            XCTAssertEqual(service.salaryForecast(1, home: home)?.description, "2026-11-03", "The repayment sheet uses the same free salary schedule")
            XCTAssertEqual(result.balance(on: try .init("2026-10-19")), 0)
            XCTAssertEqual(result.balance(on: try .init("2026-10-20")), 30_000)
            XCTAssertEqual(result.balance(on: try .init("2026-11-02")), 30_000)
            XCTAssertEqual(result.balance(on: try .init("2026-11-03")), 40_000)
            XCTAssertEqual(result.balance(on: try .init("2026-11-17")), 40_000)
            XCTAssertNil(result.balance(on: try .init("2027-12-01")))
        }
    }
    func testKnownFutureTripPausesTheNextCycleWithoutInventingAnOpenTripReturn() throws {
        try run { c, app, service, _ in
            let envelope = goal(c, target: 1_000_000)
            let plan = EnvelopePlan(); plan.envelopeID = envelope.id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = 100; c.insert(plan)
            let trip = Trip(); trip.start = try GregorianDay("2026-10-28").date(in: zone); trip.end = try GregorianDay("2026-10-30").date(in: zone); trip.tzID = zone.identifier; trip.lat = 24.7; trip.lon = 46.7; c.insert(trip)
            let open = Trip(); open.start = at("2026-10-15"); open.tzID = zone.identifier; open.lat = 24.7; open.lon = 46.7; c.insert(open)
            _ = try SettingsStore(context: c).stage(["mal.travelPausesDaily": .bool(true)])
            try c.save()
            let result = try XCTUnwrap(project(c, app, service)[envelope.id])
            XCTAssertEqual(result.balance(on: try .init("2026-10-27")), 1100)
            XCTAssertEqual(result.balance(on: try .init("2026-10-29")), 1100)
            XCTAssertEqual(result.balance(on: try .init("2026-10-30")), 1200)
        }
    }
    func testKnownClosingDeficitDoesNotPromiseTheSameSurplusToGoals() throws {
        try run { c, app, service, cycle in
            // 26 × 40,000 accrued, minus 1,060,000 carry = −20,000 at the next salary without any new spending.
            cycle.carryAdjustMinor = -1_060_000
            let envelope = goal(c)
            let plan = EnvelopePlan(); plan.envelopeID = envelope.id; plan.source = "surplus"; plan.perPaycheckMinor = 20_000; c.insert(plan)
            try c.save()
            XCTAssertTrue(try project(c, app, service, surplus: 20_000).isEmpty)
            _ = try SettingsStore(context: c).stage(["mal.autoOffset": .bool(false)]); try c.save()
            let result = try XCTUnwrap(project(c, app, service, surplus: 20_000)[envelope.id])
            XCTAssertEqual(result.balance(on: try .init("2026-10-27")), 20_000)
        }
    }
}
