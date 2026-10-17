import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct MoneyGoalTests {
    @Test func oneGoalBalancedFundingExactDailyCapAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyGoal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
        let settings = try SettingsStore(context: c); _ = try settings.stage(["core.dayStart": .string("midnight")])
        let cycle = Cycle(); cycle.start = now.addingTimeInterval(-86400); cycle.expectedEnd = now.addingTimeInterval(29*86400); cycle.dailyAllowanceMinor = 40_000; c.insert(cycle)
        let fund = Allocation(); fund.target = "surplus"; fund.amountMinor = 100_000; fund.kind = "fund"; fund.idempotencyKey = "seed"; c.insert(fund)
        let old = MoneyTransaction(); old.reviewState = "ok"; old.amountMinor = 10_000; old.homeAmountMinor = 10_000; old.dayKey = "2026-10-17"; old.eventAt = now; c.insert(old); try c.save()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func read(_ date: Date) throws -> MoneyGoalReading { try MoneyRepository(context: ModelContext(container)).goalPreparation(at: date) }
        let r = try read(now), id = UUID()
        let payload: [String:MadarCore.JSONValue] = ["name":.string("هدف"),"totalMinor":.string("130000"),"paidIDs":.array([.string(old.id.uuidString)]),"upfrontMinor":.string("100000"),"dailyMinor":.string("13333"),"source":.string("surplus"),"due":.string("2026-11-01T12:00:00Z"),"signature":.string(r.signature)]
        func run(_ name: String, _ p: [String:MadarCore.JSONValue], _ date: Date, _ commandID: UUID = UUID()) async throws -> CommandOutcome { try await bus.execute(.init(commandID: commandID, name:name,payload:.object(p),issuedAt:date),now:date) }
        #expect(try await run("money.prepareGoal", payload, now, id).status == .applied)
        let first = ModelContext(container)
        #expect(try first.fetch(FetchDescriptor<Envelope>()).first { $0.id == id }?.targetMinor == 120000)
        #expect(try read(now).surplusMinor == 0)
        #expect(try await run("money.prepareGoal", payload, now).status == .rejected)
        #expect(try await run("system.undo", ["undoToken":.string(id.uuidString)], now).status == .applied)
        #expect(try read(now).surplusMinor == 100000)
        let id2 = UUID(); #expect(try await run("money.prepareGoal", payload, now, id2).status == .applied)
        let later = now.addingTimeInterval(86400)
        #expect(try await run("money.accruePlans", [:], later).status == .applied)
        #expect(try await run("money.accruePlans", [:], later).status == .duplicate)
        let nextAt = now.addingTimeInterval(2*86400)
        let transition = ModelContext(container)
        let oldCycle = try #require(transition.fetch(FetchDescriptor<Cycle>()).first { $0.id == cycle.id })
        oldCycle.end = nextAt; oldCycle.closedAt = nextAt
        let nextCycle = Cycle(); nextCycle.start = nextAt; nextCycle.expectedEnd = nextAt.addingTimeInterval(30*86400); nextCycle.dailyAllowanceMinor = 40000; transition.insert(nextCycle); try transition.save()
        #expect(try await run("money.accruePlans", [:], nextAt.addingTimeInterval(3*86400)).status == .applied)
        let final = ModelContext(container), rows = try final.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.targetID == id2 }
        #expect(rows.reduce(0) { $0 + $1.amountMinor } == 120000)
        #expect(rows.filter { $0.idempotencyKey.hasPrefix("daily:") }.map(\.amountMinor).sorted() == [6667,13333])
        #expect(try final.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil }.count == 1)
    }
}
