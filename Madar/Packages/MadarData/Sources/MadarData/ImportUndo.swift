import Foundation

/// Undo for a whole-store import (the move from the old Madar, 25 Oct 2026). The importers write through commands,
/// direct rows and settings alike, so undo compares record snapshots instead of trusting each writer's bookkeeping.
/// Only rows still exactly as the import left them are reverted; a row the owner changed afterwards is kept and counted.
public enum ImportUndo {
    public struct Plan: Equatable, Sendable {
        /// Earlier versions to write back.
        public var writes: [DataRecord] = []
        /// Rows the import created, removed outright: they never existed before it, the v1 store is local-only (RA1),
        /// and a tombstone would make the next move from the same file skip them.
        public var removals: [DataRecord] = []
        public var restored = 0, removed = 0, keptChanged = 0
        public var isEmpty: Bool { writes.isEmpty && removals.isEmpty }
    }

    struct Key: Hashable { let model: String; let id: UUID; let merged: String? }
    static func key(_ row: DataRecord) -> Key { Key(model: row.model, id: row.id, merged: row.fields["mergedInto"]?.string) }

    public static func plan(before: [DataRecord], after: [DataRecord], current: [DataRecord], now: Date) throws -> Plan {
        let old = Dictionary(before.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let live = Dictionary(current.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        // Ids that rows written or changed after the import point to (a transaction on an imported account, a habit
        // time on an imported habit). Those imported rows stay, or the owner's own rows would dangle.
        var referenced = Set<String>()
        func collect(_ value: JSONValue) {
            switch value {
            case .string(let s): if s.count == 36 { referenced.insert(s.uppercased()) }
            case .array(let items): items.forEach(collect)
            case .object(let fields): fields.values.forEach(collect)
            default: break
            }
        }
        for row in current where row.isLive && new[key(row)] != row {
            for (field, value) in row.fields where field != "id" { collect(value) }
        }
        // A later native event keeps its imported habit. Keep that habit's rules and pauses too, or the event would
        // survive but the habit would lose the period/target used to interpret it. Old imported events still undo.
        for row in current where row.isLive && ["HabitPolicy", "HabitPause"].contains(row.model) {
            if let habit = row.fields["habitID"]?.string, referenced.contains(habit.uppercased()) {
                referenced.insert(row.id.uuidString.uppercased())
            }
        }
        var plan = Plan()
        for (k, imported) in new where old[k] != imported {
            guard let present = live[k] else { continue }
            guard present == imported else { plan.keptChanged += 1; continue }
            if var earlier = old[k] {
                try earlier.set(now, for: "updatedAt"); plan.writes.append(earlier); plan.restored += 1
            } else if referenced.contains(imported.id.uuidString.uppercased()) {
                plan.keptChanged += 1
            } else {
                plan.removals.append(imported); plan.removed += 1
            }
        }
        // Stable order: one undo always writes the same rows in the same sequence.
        plan.writes.sort { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
        plan.removals.sort { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
        return plan
    }
}
