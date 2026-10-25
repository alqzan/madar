import Foundation
import Testing
@testable import MadarData

struct ImportUndoTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000), now = Date(timeIntervalSince1970: 1_800_100_000)
    func row(_ model: String, _ id: String, _ value: String, updated: Date? = nil) throws -> DataRecord {
        var r = DataRecord(model: model, fields: ["id": .string(id), "value": .string(value)])
        try r.set(updated ?? t0, for: "updatedAt"); return r
    }
    let a = "00000000-0000-0000-0000-00000000000A", b = "00000000-0000-0000-0000-00000000000B"
    let c = "00000000-0000-0000-0000-00000000000C", d = "00000000-0000-0000-0000-00000000000D"

    @Test func revertsOnlyWhatTheImportTouchedAndKeepsLaterEdits() throws {
        let setting = try row("Setting", a, "old"), untouched = try row("Entry", b, "diary")
        let before = [setting, untouched]
        let changed = try row("Setting", a, "imported"), created = try row("PrayerLog", c, "fajr"), edited = try row("PrayerLog", d, "dhuhr")
        let after = [changed, untouched, created, edited]
        // After the import, the owner changed d; it must survive undo.
        let current = [changed, untouched, created, try row("PrayerLog", d, "dhuhr-late")]
        let plan = try ImportUndo.plan(before: before, after: after, current: current, now: now)
        #expect(plan.restored == 1); #expect(plan.removed == 1); #expect(plan.keptChanged == 1)
        #expect(plan.writes.count == 1); #expect(plan.removals.count == 1)
        let restored = try #require(plan.writes.first)
        #expect(restored.model == "Setting"); #expect(restored.fields["value"] == .string("old")); #expect(restored.date("updatedAt") == now)
        let removed = try #require(plan.removals.first)
        #expect(removed.model == "PrayerLog"); #expect(removed.id.uuidString == c)
    }

    @Test func secondUndoAfterTheFirstChangesNothing() throws {
        let before = [try row("Setting", a, "old")], after = [try row("Setting", a, "new"), try row("Entry", b, "x")]
        let first = try ImportUndo.plan(before: before, after: after, current: after, now: now)
        // The store now holds the first undo's writes and no longer the removed row.
        #expect(first.removals.map(\.model) == ["Entry"])
        let plan = try ImportUndo.plan(before: before, after: after, current: first.writes, now: now)
        #expect(plan.isEmpty); #expect(plan.keptChanged == 1)
    }

    @Test func importedRowTheOwnerNowUsesIsKept() throws {
        let account = try row("Account", a, "imported"), setting = try row("Setting", b, "x")
        var spend = try row("MoneyTransaction", c, "coffee"); spend.fields["fromAccountID"] = .string(a.lowercased())
        let plan = try ImportUndo.plan(before: [setting], after: [setting, account], current: [setting, account, spend], now: now)
        #expect(plan.removals.isEmpty); #expect(plan.keptChanged == 1)
    }

    @Test func usedHabitKeepsItsRulesButUndoesOldImportedTimes() throws {
        let habit = try row("Habit", a, "imported")
        var policy = try row("HabitPolicy", b, "daily"); policy.fields["habitID"] = .string(a.lowercased())
        var oldTime = try row("HabitEvent", c, "old"); oldTime.fields["habitID"] = .string(a)
        var nativeTime = try row("HabitEvent", d, "new"); nativeTime.fields["habitID"] = .string(a)
        let plan = try ImportUndo.plan(before: [], after: [habit, policy, oldTime], current: [habit, policy, oldTime, nativeTime], now: now)
        #expect(plan.removals.map(\.model) == ["HabitEvent"])
        #expect(plan.removals.first?.id.uuidString == c)
        #expect(plan.keptChanged == 2)
    }

    @Test func emptyImportPlansNothing() throws {
        let rows = [try row("Setting", a, "same")]
        #expect(try ImportUndo.plan(before: rows, after: rows, current: rows, now: now).isEmpty)
    }
}
