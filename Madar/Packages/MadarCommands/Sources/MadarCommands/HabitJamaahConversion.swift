import Foundation
import SwiftData
import MadarCore
import MadarData

/// Owner, 17 Nov 2026: Madar no longer logs prayers, so a habit linked to «الجماعة» can no longer read them.
/// It becomes the user's own once-a-day habit «صليت كل الصلوات بجماعة», asked by a push one hour after Isha
/// (window Isha +60 … +240 min). Its earlier rules stay for closed periods; the new rule starts `today`.
/// Idempotent: a converted habit has no linked source, so the next launch finds nothing.
@MainActor public enum HabitJamaahConversion {
    public static let writer = "system.habit-jamaah-manual-v1"
    public static let name = "صليت كل الصلوات بجماعة"

    public static func rule(from day: GregorianDay) -> HabitRule {
        var rule = HabitRule(effectiveFrom: day)
        rule.frequency = .daily; rule.measure = .once; rule.unit = nil; rule.target = 1; rule.minimum = nil
        rule.windowAnchor = .isha; rule.windowStart = 60; rule.windowEnd = 240
        return rule
    }

    @discardableResult
    public static func convert(in context: ModelContext, today: GregorianDay, now: Date = .now) throws -> Int {
        let habits = try context.fetch(FetchDescriptor<Habit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.linkedSource == "jamaah" }
        guard !habits.isEmpty else { return 0 }
        func touch(_ row: some MadarRecordModel) throws {
            var record = try row.record()
            try record.set(StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast), for: "updatedAt")
            try record.set(writer, for: "writerID"); try row.apply(record)
        }
        do {
            for habit in habits {
                habit.linkedSource = nil; habit.kind = "custom"; habit.reminder = "push"
                if habit.name == "الجماعة" || habit.name.isEmpty { habit.name = name }
                try touch(habit)
                let id = habit.id, key = today.description
                let policy = try context.fetch(FetchDescriptor<HabitPolicy>(predicate: #Predicate { $0.habitID == id && $0.effectiveFrom == key && $0.deletedAt == nil && $0.mergedInto == nil })).first ?? {
                    let row = HabitPolicy(); row.id = StableIdentity.uuid(for: "habit-policy:\(id):\(today)"); row.habitID = id; row.createdAt = now; context.insert(row); return row
                }()
                HabitRepository.apply(rule(from: today), to: policy); try touch(policy)
            }
            try context.save()
        } catch { context.rollback(); throw error }
        return habits.count
    }
}
