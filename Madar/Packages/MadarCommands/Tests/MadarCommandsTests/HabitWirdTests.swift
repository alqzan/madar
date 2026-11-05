import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// Owner, 6 Nov 2026: «ابي فيه عادات التطبيق… القرآن والورد». The wird habit counts a day on which a new hifz
/// portion was recorded in the Quran room: once per day, never for a deleted session or a review.
@MainActor struct HabitWirdTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!
    @Test func wirdHabitCountsEachDayWithARecordedHifzPortionOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitWird-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let c = ModelContext(container)
        func session(_ day: String, _ kind: String, hour: Int, deleted: Bool = false) {
            let row = HifzSession(); row.dayKey = day; row.kind = kind; row.fromAyah = 1; row.toAyah = 7; row.pages = [1]; row.tzID = "Asia/Riyadh"
            row.endedAt = ISO8601DateFormatter().date(from: "\(day)T\(String(format: "%02d", hour)):00:00+03:00")!
            if deleted { row.deletedAt = row.endedAt }
            c.insert(row)
        }
        session("2026-10-12", "review", hour: 9)
        session("2026-10-13", "hifz", hour: 9, deleted: true)
        session("2026-10-14", "hifz", hour: 7); session("2026-10-14", "hifz", hour: 18)
        session("2026-10-15", "hifz", hour: 6)
        try c.save()
        var rule = HabitRule(effectiveFrom: try GregorianDay("2026-10-15")); rule.measure = .count; rule.unit = "ورد"; rule.target = 1
        let id = UUID()
        let payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string("ورد الحفظ"), "source": .string("wird"),
                                                      "rule": try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))]
        #expect(try await bus.execute(.init(name: "habit.save", payload: .object(payload), issuedAt: now), now: now).status == .applied)
        let reading = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first { $0.id == id })
        #expect(reading.source == "wird")
        #expect(reading.summary.current?.value == 1 && reading.summary.current?.met == true)
        #expect(reading.times.map(\.day.description) == ["2026-10-15", "2026-10-14"])
        // The unit is the wird itself; any other unit is refused at parse.
        var wrong = payload; rule.unit = "وجه"; wrong["rule"] = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))
        #expect(HabitCommand.parse("habit.save", wrong) == nil)
    }
}
