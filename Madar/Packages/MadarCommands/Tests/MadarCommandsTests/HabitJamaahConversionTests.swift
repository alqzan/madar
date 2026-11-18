import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// Owner, 17 Nov 2026: prayer logging is gone, so «الجماعة» becomes the user's own daily habit,
/// asked an hour after Isha. Synthetic store only.
@MainActor struct HabitJamaahConversionTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-17T20:00:00+03:00")!
    @Test func jamaahHabitBecomesAManualOnceHabitAnchoredAfterIsha() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitJamaah-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), bus = CommandBus(adapter: legacyPrayerAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        var rule = HabitRule(effectiveFrom: try GregorianDay("2026-11-10")); rule.measure = .count; rule.unit = "صلاة"; rule.target = 5
        let id = UUID(), other = UUID()
        func save(_ id: UUID, _ name: String, _ source: String?) async throws {
            var payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string(name),
                                                          "rule": try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))]
            if let source { payload["source"] = .string(source) }
            #expect(try await bus.execute(.init(name: "habit.save", payload: .object(payload), issuedAt: now), now: now).status == .applied)
        }
        try await save(id, "الجماعة", "jamaah")
        rule.measure = .once; rule.unit = nil; rule.target = 1
        try await save(other, "الماء", nil)
        let today = try GregorianDay("2026-11-17")
        #expect(try HabitJamaahConversion.convert(in: ModelContext(container), today: today, now: now) == 1)
        let reading = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first { $0.id == id })
        #expect(reading.source == nil)
        #expect(reading.name == "صليت كل الصلوات بجماعة")
        #expect(reading.reminder == "push")
        let current = try #require(reading.summary.current?.rule)
        #expect(current.measure == .once && current.target == 1 && current.frequency == .daily)
        #expect(current.windowAnchor == .isha && current.windowStart == 60 && current.windowEnd == 240)
        #expect(current.effectiveFrom == today)
        // The other habit is untouched, and a second launch finds nothing to convert.
        let water = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first { $0.id == other })
        #expect(water.reminder != "push" || water.name == "الماء")
        #expect(try HabitJamaahConversion.convert(in: ModelContext(container), today: today, now: now) == 0)
    }
}
