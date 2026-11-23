import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

/// Idea 2 (owner, 17 Nov 2026): the Saturday lobby note about a struggling daily habit. It never changes the habit.
@MainActor final class HabitSuggestionIntegrationTests: XCTestCase {
    private func session(events: [String: [String]]) throws -> (AppSession, [String: Habit]) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarHabitSuggestion-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), store = try SettingsStore(context: context)
        _ = try store.stage(["core.dayStart": .string("midnight"), "bahw.smartPresence": .string("medium")]); try context.save()
        var habits: [String: Habit] = [:]
        for (name, days) in events {
            let habit = Habit(); habit.name = name; habit.startDate = ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!; context.insert(habit); habits[name] = habit
            let policy = HabitPolicy(); policy.habitID = habit.id; policy.effectiveFrom = "2026-10-01"; policy.frequency = "daily"; policy.measure = "once"; policy.target = 1
            context.insert(policy)
            for day in days {
                let event = HabitEvent(); event.habitID = habit.id; event.dayKey = day; event.periodKey = day; event.delta = 1; event.tzID = "Asia/Riyadh"; event.dayPolicy = "midnight@1"
                event.eventAt = ISO8601DateFormatter().date(from: day + "T09:00:00+03:00")!; context.insert(event)
            }
        }
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        return (app, habits)
    }
    private let saturday = ISO8601DateFormatter().date(from: "2026-10-17T14:00:00+03:00")!   // 17 Oct 2026 is a Saturday
    private let friday = ISO8601DateFormatter().date(from: "2026-10-16T14:00:00+03:00")!

    func testSaturdayNamesTheWeakestHabitAndChangesNothing() throws {
        // Days closed: 10–16 Oct. «الرياضة» met 2 of 7; «الماء» met 5 of 7; «القراءة» met 3 of 7 (not struggling).
        let (app, habits) = try session(events: [
            "الرياضة": ["2026-10-11", "2026-10-14"],
            "الماء": ["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-14", "2026-10-16"],
            "القراءة": ["2026-10-10", "2026-10-12", "2026-10-15"]])
        let suggestions = AppBahwService(session: app, evaluationDate: saturday).suggestions()
        let help = try XCTUnwrap(suggestions.first { $0.id == "habitHelp" })
        XCTAssertEqual(help.title, "«الرياضة» تتعثّر")
        XCTAssertTrue(help.detail.contains("أتممتها يومين من ٧"), help.detail)
        guard case .habit(let id) = help.destination else { return XCTFail("opens the habit") }
        XCTAssertEqual(id, habits["الرياضة"]?.id)
        // Nothing is written: the policy is still the one saved, and no extra policy rows exist.
        let policies = try ModelContext(app.container).fetch(FetchDescriptor<HabitPolicy>())
        XCTAssertEqual(policies.count, 3); XCTAssertTrue(policies.allSatisfy { $0.target == 1 && $0.windowStartMin == nil })
    }

    func testOtherDaysAndHealthyWeeksShowNothing() throws {
        let (app, _) = try session(events: ["الرياضة": ["2026-10-11"]])
        XCTAssertNil(AppBahwService(session: app, evaluationDate: friday).suggestions().first { $0.id == "habitHelp" })
        let (steady, _) = try session(events: ["الماء": ["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-14", "2026-10-16"]])
        XCTAssertNil(AppBahwService(session: steady, evaluationDate: saturday).suggestions().first { $0.id == "habitHelp" })
    }
}
