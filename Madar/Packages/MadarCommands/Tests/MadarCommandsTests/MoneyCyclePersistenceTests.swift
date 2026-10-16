import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

@MainActor struct MoneyCyclePersistenceTests {
    @Test func planDropsAccrueFromStartExactlyOnceAndDoNotChargeDailyTwice() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyDrips-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let start = try GregorianDay("2026-10-01"), zone = ActivePlace.riyadh.timeZone
        let now = start.adding(days: 2).date(in: zone).addingTimeInterval(12 * 3600)
        _ = try SettingsStore(context: context).stage(["core.dayStart": .string("midnight")])
        let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = start.adding(days: 28).date(in: zone); cycle.dailyAllowanceMinor = 41300; context.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.allowanceMinor = 41300; policy.dailyRateMinor = 41300; context.insert(policy)
        let envelope = Envelope(); envelope.name = "هدف"; context.insert(envelope)
        let plan = EnvelopePlan(); plan.envelopeID = envelope.id; plan.source = "daily"; plan.period = "perCycle"; plan.perPaycheckMinor = 300000; plan.startDayKey = start.description; context.insert(plan); try context.save()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func accrue(_ at: Date) async throws -> CommandOutcome { try await bus.execute(.init(name: "money.accruePlans", payload: .object([:]), issuedAt: at), now: at) }
        #expect(try await accrue(now).status == .applied); #expect(try await accrue(now).status == .duplicate)
        let read = ModelContext(container), repo = MoneyRepository(context: read)
        #expect(try read.fetchCount(FetchDescriptor<Allocation>()) == 6)
        let allocations = try repo.allocationRows(); #expect(allocations.reduce(0) { $0 + $1.amountMinor } == 0)
        #expect(allocations.filter { $0.target == .envelope(envelope.id.uuidString) }.reduce(0) { $0 + $1.amountMinor } == 32142)
        let reading = try #require(try repo.cycle(at: now))
        #expect(reading.headline.todayAllowanceMinor == 30586); #expect(reading.headline.availableNowMinor == 91758)
        let lastDay = start.adding(days: 27).date(in: zone).addingTimeInterval(12 * 3600)
        _ = try await accrue(lastDay)
        let deposited = try MoneyRepository(context: ModelContext(container)).allocationRows().filter { $0.target == .envelope(envelope.id.uuidString) }.reduce(0) { $0 + $1.amountMinor }
        #expect(deposited == 300000, "L06: 28 × 10714 + 8, not an amount from the preview date")
    }
    @Test func percentPolicyReadsItsFrozenRateAndReturnsRefundToOriginalDay() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyFrozen-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), zone = ActivePlace.riyadh.timeZone
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight")])
        let start = try GregorianDay("2026-10-01"), now = start.adding(days: 2).date(in: zone).addingTimeInterval(43200)
        let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = start.adding(days: 28).date(in: zone); cycle.incomeMinor = 1500000; contextForCycle(c, cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.mode = "percent"; policy.percentBp = 4000
        // L07: the policy was frozen against 31 scheduled days, despite the salary arriving early.
        policy.dailyRateMinor = 19354; policy.lastDayRemainderMinor = 26; c.insert(policy)
        let original = MoneyTransaction(); original.dayKey = start.description; original.eventAt = cycle.start; original.cycleID = cycle.id; original.homeAmountMinor = 100; original.amountMinor = 100; c.insert(original)
        let refund = MoneyTransaction(); refund.kind = "refund"; refund.relatedTransactionID = original.id; refund.dayKey = start.adding(days: 2).description; refund.eventAt = now; refund.cycleID = cycle.id; refund.homeAmountMinor = 50; refund.amountMinor = 50; c.insert(refund)
        for (tx, amount, kind) in [(original, -100, "spend"), (refund, 50, "refund")] { let a = Allocation(); a.transactionID = tx.id; a.cycleID = cycle.id; a.amountMinor = amount; a.kind = kind; c.insert(a) }; try c.save()
        let reading = try #require(try MoneyRepository(context: ModelContext(container)).cycle(at: now))
        #expect(reading.headline.todayAllowanceMinor == 19354); #expect(reading.headline.todaySpentMinor == 0)
        #expect(reading.spent[1] == 50); #expect(reading.headline.availableNowMinor == 58012)
    }
    private func contextForCycle(_ c: ModelContext, _ cycle: Cycle) { c.insert(cycle) }
}
