import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// Owner, 17 Nov 2026 (ideas 8, 10, 16): dated rule versions written by one save, tombstoned by the next, restored by undo;
/// a habit you quit logs only an explicit slip. Synthetic stores only.
@MainActor struct HabitScheduleStepsTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!
    let zone = ActivePlace.riyadh.timeZone
    func day(_ s: String) -> GregorianDay { try! GregorianDay(s) }
    func at(_ d: GregorianDay) -> Date { d.date(in: zone).addingTimeInterval(43200) }
    func json(_ r: HabitRule) throws -> MadarCore.JSONValue { try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(r)) }
    func store() throws -> (ModelContainer, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitSteps-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root)
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), root)
    }
    func save(_ bus: CommandBus, _ habit: UUID, _ rule: HabitRule, steps: [HabitRule] = [], reminder: String = "dot", id: UUID = UUID()) async throws -> CommandOutcome {
        var p: [String: MadarCore.JSONValue] = ["id": .string(habit.uuidString), "name": .string("القراءة"), "rule": try json(rule), "reminder": .string(reminder)]
        if !steps.isEmpty { p["steps"] = .array(try steps.map(json)) }
        return try await bus.execute(.init(commandID: id, name: "habit.save", payload: .object(p), issuedAt: now), now: now)
    }
    func pages(_ from: String, _ target: Int) -> HabitRule { var r = HabitRule(effectiveFrom: day(from)); r.measure = .count; r.unit = "pages"; r.target = target; return r }
    func policies(_ container: ModelContainer, _ habit: UUID) throws -> [HabitPolicy] {
        try ModelContext(container).fetch(FetchDescriptor<HabitPolicy>()).filter { $0.habitID == habit }.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
    func target(_ container: ModelContainer, _ habit: UUID, on d: GregorianDay) throws -> Int? {
        try HabitRepository(context: ModelContext(container)).reading(id: habit, at: at(d))?.summary.current?.target
    }

    @Test func aGrowingGoalWritesItsFutureStepsAndPastPeriodsStayAsTheyWere() async throws {
        let (container, bus, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID(), base = pages("2026-10-15", 5)
        let plan = HabitSchedule.plan(base: base, ramp: .init(step: 1, everyDays: 7, cap: 7), ramadan: nil, today: day("2026-10-15"), days: MadarCalendarDays(zone: zone))
        #expect(try await save(bus, habit, plan.rule, steps: plan.steps).status == .applied)
        let rows = try policies(container, habit)
        #expect(rows.map(\.effectiveFrom) == ["2026-10-15", "2026-10-22", "2026-10-29"] && rows.map { $0.target ?? 0 } == [5, 6, 7] && rows.allSatisfy { $0.deletedAt == nil })
        #expect(try target(container, habit, on: day("2026-10-15")) == 5 && target(container, habit, on: day("2026-10-23")) == 6 && target(container, habit, on: day("2026-11-02")) == 7)
        let reading = try #require(try HabitRepository(context: ModelContext(container)).reading(id: habit, at: at(day("2026-10-30"))))
        let byStart = Dictionary(uniqueKeysWithValues: reading.summary.periods.map { ($0.start.description, $0.target) })
        #expect(byStart["2026-10-16"] == 5 && byStart["2026-10-21"] == 5 && byStart["2026-10-22"] == 6 && byStart["2026-10-28"] == 6 && byStart["2026-10-29"] == 7)
    }
    @Test func anEditTombstonesTheFutureStepsAndUndoRestoresThem() async throws {
        let (container, bus, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID(), base = pages("2026-10-15", 5)
        let plan = HabitSchedule.plan(base: base, ramp: .init(step: 1, everyDays: 7, cap: 7), ramadan: nil, today: day("2026-10-15"), days: MadarCalendarDays(zone: zone))
        _ = try await save(bus, habit, plan.rule, steps: plan.steps)
        let edit = UUID()
        #expect(try await save(bus, habit, pages("2026-10-15", 3), id: edit).status == .applied)
        let after = try policies(container, habit)
        #expect(after.count == 3 && after[0].deletedAt == nil && after[0].target == 3)
        #expect(after[1...].allSatisfy { $0.deletedAt != nil && $0.deletionBarrierAt != nil })   // tombstones, never deleted rows
        #expect(try target(container, habit, on: day("2026-10-23")) == 3 && target(container, habit, on: day("2026-11-02")) == 3)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(edit.uuidString)]), issuedAt: now), now: now)
        let restored = try policies(container, habit)
        #expect(restored.count == 3 && restored.allSatisfy { $0.deletedAt == nil } && restored.map { $0.target ?? 0 } == [5, 6, 7])
        #expect(try target(container, habit, on: day("2026-10-23")) == 6 && target(container, habit, on: day("2026-11-02")) == 7)
    }
    @Test func savingTheSameStepsAgainReusesTheirRowsAndAClosedTombstoneComesBack() async throws {
        let (container, bus, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID(), base = pages("2026-10-15", 5), plan = HabitSchedule.plan(base: base, ramp: .init(step: 1, everyDays: 7, cap: 6), ramadan: nil, today: day("2026-10-15"), days: MadarCalendarDays(zone: zone))
        _ = try await save(bus, habit, plan.rule, steps: plan.steps)
        _ = try await save(bus, habit, plan.rule, steps: plan.steps)           // same set: rows updated in place
        #expect(try policies(container, habit).count == 2)
        _ = try await save(bus, habit, base)                                    // no steps: the step is tombstoned
        #expect(try policies(container, habit).filter { $0.deletedAt != nil }.count == 1)
        _ = try await save(bus, habit, plan.rule, steps: plan.steps)           // steps again: the tombstoned row is restored, not duplicated
        let rows = try policies(container, habit)
        #expect(rows.count == 2 && rows.allSatisfy { $0.deletedAt == nil })
    }
    @Test func ramadanWritesItsWindowAtFirstRamadanAndTheNormalOneAtShawwal() async throws {
        let (container, bus, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID(); var base = HabitRule(effectiveFrom: day("2026-10-15")); base.windowAnchor = .fajr; base.windowStart = 0; base.windowEnd = 90
        let calendar = MadarCalendarDays(zone: zone, source: .ummAlQura)
        let plan = HabitSchedule.plan(base: base, ramp: nil, ramadan: .init(anchor: .isha, start: 90, end: 360), today: day("2026-10-15"), days: calendar)
        let first = HabitSchedule.ramadanSpans(from: day("2026-10-15"), days: calendar)[0]
        #expect(try await save(bus, habit, plan.rule, steps: plan.steps).status == .applied)
        func window(_ d: GregorianDay) throws -> Prayer? { try HabitRepository(context: ModelContext(container)).reading(id: habit, at: at(d))?.summary.current?.rule.windowAnchor }
        #expect(try window(day("2026-10-20")) == .fajr)
        #expect(try window(first.start.adding(days: 2)) == .isha)
        #expect(try window(first.end) == .fajr && window(first.end.adding(days: 3)) == .fajr)
        // Closed periods are unchanged: the day before Ramadan still reads as Fajr after Ramadan has passed.
        let after = try #require(try HabitRepository(context: ModelContext(container)).reading(id: habit, at: at(first.end.adding(days: 1))))
        #expect(after.summary.periods.first { $0.start == first.start.adding(days: -1) }?.rule.windowAnchor == .fajr)
        #expect(after.summary.periods.first { $0.start == first.start }?.rule.windowAnchor == .isha)
    }
    @Test func aHabitYouQuitLogsOnlyAnExplicitSlip() async throws {
        let (container, bus, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let habit = UUID(); var rule = HabitRule(effectiveFrom: day("2026-10-10")); rule.measure = .abstain
        #expect(try await save(bus, habit, rule, reminder: "dot").status == .rejected)   // a reminder would say «سوّها الحين»
        #expect(try await save(bus, habit, rule, reminder: "none").status == .applied)
        func complete(_ extra: [String: MadarCore.JSONValue], id: UUID = UUID()) async throws -> CommandOutcome {
            var p: [String: MadarCore.JSONValue] = ["habitID": .string(habit.uuidString), "delta": .number(1)]; p.merge(extra) { $1 }
            return try await bus.execute(.init(commandID: id, name: "habit.complete", payload: .object(p), issuedAt: now), now: now)
        }
        func reading() throws -> HabitReading { try #require(try HabitRepository(context: ModelContext(container)).reading(id: habit, at: now)) }
        #expect(try reading().summary.current?.outcome == .complete && reading().summary.streak == 6)   // 10–15 Oct, today included
        // Lobby lists, notifications, widgets and intents read without it; only the room asks for it.
        #expect(try HabitRepository(context: ModelContext(container)).readings(at: now).contains { $0.id == habit } == false)
        #expect(try HabitRepository(context: ModelContext(container)).readings(at: now, includeQuitting: true).contains { $0.id == habit })
        _ = try await complete([:])                                                                        // a plain tap, as a ring or widget would send
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter { $0.delta != 0 }.isEmpty)
        let slip = UUID()
        #expect(try await complete(["slip": .bool(true)], id: slip).status == .applied)
        #expect(try reading().summary.current?.outcome == .missed && reading().summary.streak == 0)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(slip.uuidString)]), issuedAt: now), now: now)
        #expect(try reading().summary.current?.outcome == .complete && reading().summary.streak == 6)
    }
}
