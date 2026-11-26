import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar

final class HabitRhythmTests: XCTestCase {
    @MainActor func testDisplayedCompletionDoesNotCarryIntoTheNextPeriod() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "HabitCompletionPeriod-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00"))
        let next = first.addingTimeInterval(86400)
        let id = UUID()
        var rule = HabitRule(effectiveFrom: try GregorianDay("2026-10-15"))
        rule.measure = .count
        rule.target = 2
        let savedRule = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))
        func run(_ name: String, payload: [String: MadarCore.JSONValue], at date: Date) async throws -> CommandOutcome {
            try await bus.execute(.init(name: name, payload: .object(payload), issuedAt: date), now: date)
        }
        let created = try await run("habit.save", payload: ["id": .string(id.uuidString), "name": .string("عادة"), "rule": savedRule], at: first)
        XCTAssertEqual(created.status, .applied)
        func period(at date: Date) throws -> HabitPeriodResult {
            try XCTUnwrap(HabitRepository(context: ModelContext(container)).reading(id: id, at: date)?.summary.current)
        }

        let previous = try period(at: first)
        let expired = try await run("habit.complete", payload: previous.completionPayload(for: id, delta: 1), at: next)
        XCTAssertEqual(expired.status, .rejected)
        let current = try period(at: next)
        XCTAssertNotEqual(current.key, previous.key)
        XCTAssertEqual(current.value, 0)
        let logged = try await run("habit.complete", payload: current.completionPayload(for: id, delta: 1), at: next)
        XCTAssertEqual(logged.status, .applied)
        XCTAssertEqual(try period(at: next).value, 1)
    }

    @MainActor func testHabitDiaryExcerptsRequireAuthorizationAndKeepOnlyRequestedLiveHeads() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "HabitDiaryLines-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        let context = ModelContext(container), day = try GregorianDay("2026-10-15")
        let other = day.adding(days: -1), now = day.date(in: .gmt)

        func insert(_ text: String, on date: GregorianDay? = nil, createdAt: Date? = nil) -> Entry {
            let row = Entry()
            row.dayKey = (date ?? day).description
            row.text = text
            row.createdAt = createdAt ?? now
            context.insert(row)
            return row
        }

        let original = insert("النص السابق")
        let kept = insert("سطر آخر", createdAt: now.addingTimeInterval(1))
        let revised = insert("النص الحالي", createdAt: now.addingTimeInterval(2))
        revised.source = "revision"
        revised.sourceID = original.id.uuidString
        insert("سطر محذوف").deletedAt = now
        insert("سطر آلي").source = "autoPinned"
        _ = insert("سطر من يوم آخر", on: other)
        try context.save()

        XCTAssertFalse(HabitDiaryLines.Access(app).allowed)
        do {
            _ = try await HabitDiaryLines.read([day], session: app)
            XCTFail("Habit excerpts must use the diary authorization gate")
        } catch let error as DataError {
            XCTAssertEqual(error, .invalidValue("المذكرات مقفلة"))
        }

        app.authorizeProtectedData()
        let authorized = HabitDiaryLines.Access(app)
        let days = try await HabitDiaryLines.read([day], session: app)
        XCTAssertEqual(days[day]?.map(\.id), [kept.id, revised.id])
        XCTAssertNil(days[other])
        app.redactProtectedData()
        XCTAssertNotEqual(HabitDiaryLines.Access(app), authorized)
    }

    func testDailyBandKeepsPartialCountBelowACompleteDayEvenAtMinimum() throws {
        let today = try GregorianDay("2026-10-15"), yesterday = today.adding(days: -1)
        var rule = HabitRule(effectiveFrom: yesterday)
        rule.measure = .count; rule.target = 8; rule.minimum = 1; rule.unit = "كوب"
        let summary = try HabitEngine.evaluate(rules: [rule], facts: [
            .init(id: UUID(), day: yesterday, periodKey: yesterday.description, delta: 1, unit: "كوب"),
            .init(id: UUID(), day: today, periodKey: today.description, delta: 8, unit: "كوب")
        ], today: today, days: .init(zone: .gmt))
        let steps = HabitRhythmBand.dailySteps(summaries: [summary], today: today)
        XCTAssertEqual(steps[5].share, 0.125, accuracy: 0.0001)
        XCTAssertEqual(steps[6].share, 1)
        XCTAssertEqual(steps.filter { $0.share >= 1 }.count, 1)
    }

    func testDailyBandUsesHistoricalEligibilityInsteadOfTodaysFreezeOrNewHabit() throws {
        let today = try GregorianDay("2026-10-15"), yesterday = today.adding(days: -1)
        var old = HabitRule(effectiveFrom: today.adding(days: -6)); old.restWeekdays = [3] // Tuesday
        let summary = try HabitEngine.evaluate(rules: [old], facts: [
            .init(id: UUID(), day: yesterday, periodKey: yesterday.description, delta: 1)
        ], pauses: [.init(from: today)], today: today, days: .init(zone: .gmt))
        let new = try HabitEngine.evaluate(rules: [.init(effectiveFrom: today)], facts: [], today: today, days: .init(zone: .gmt))
        let steps = HabitRhythmBand.dailySteps(summaries: [summary, new], today: today)
        XCTAssertEqual(steps[5].share, 1, "A habit created today cannot make yesterday incomplete; today's freeze cannot erase it")
        XCTAssertEqual(steps[4].share, 0, "A rest day is not a completed day")
        XCTAssertEqual(steps[6].share, 0)
    }
}
