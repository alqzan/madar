import Foundation
import CoreFoundation

/// My-dream aba0c1b: a custom habit is a daily checkbox; logs are Gregorian day
/// strings, not quantities or owning-room facts. This planner never writes a store.
public enum LegacyHabitImport {
    public struct HabitRow: Equatable, Sendable {
        public let id: UUID, sourceID: String, name: String, icon: String, color: String
        public let start: GregorianDay, updatedAt: Date, deletedAt: Date?, deletionBarrierAt: Date?, restoredAt: Date?, order: Int
    }
    public struct EventRow: Equatable, Sendable {
        public let id: UUID, habitID: UUID, day: GregorianDay, deletedAt: Date?
    }
    public struct PauseRow: Equatable, Sendable {
        public let id: UUID, habitID: UUID, observedFrom: GregorianDay
    }
    public struct Archive: Equatable, Sendable {
        public let sourceID: String, json: Data
    }
    public struct Plan: Equatable, Sendable {
        public var habits: [HabitRow] = []
        public var events: [EventRow] = []
        public var pauses: [PauseRow] = []
        public var archives: [Archive] = []
        public var counts: [String: Int] = [:]
    }
    public static func plan(backup: Data, observedDay: GregorianDay, zone: TimeZone,
                            uuid: (String) -> UUID) throws -> Plan {
        guard let root = try JSONSerialization.jsonObject(with: backup) as? [String: Any] else { throw CoreError.invalidCommand }
        var result = Plan()
        func count(_ key: String, _ amount: Int = 1) { result.counts[key, default: 0] += amount }
        func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) }
        func milliseconds(_ value: Any?) -> Date? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: n.doubleValue / 1000)
        }
        let rawRows = root["habits"] as? [Any] ?? []
        let deleted = root["deleted"] as? [String: Any] ?? [:]
        let frozen = Set(root["frozenHabits"] as? [String] ?? [])
        var groups: [String: [[String: Any]]] = [:], order: [String] = []
        for (index, raw) in rawRows.enumerated() {
            guard let row = raw as? [String: Any], let id = row["id"] as? String, !id.isEmpty else {
                result.archives.append(.init(sourceID: "invalid:\(index)", json: try json(raw)))
                count("skipped.identity"); continue
            }
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(row)
        }
        for (position, sourceID) in order.enumerated() {
            let copies = groups[sourceID]!
            result.archives.append(.init(sourceID: "habit:" + sourceID, json: try json(copies)))
            // Match the old per-item merge: newest metadata wins, dates union.
            let sorted = try copies.map { (row: $0, raw: try json($0)) }.sorted {
                let a = milliseconds($0.row["updatedAt"]) ?? .distantPast
                let b = milliseconds($1.row["updatedAt"]) ?? .distantPast
                return a == b ? $0.raw.lexicographicallyPrecedes($1.raw) : a < b
            }
            let row = sorted.last!.row
            guard let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                count("skipped.name"); continue
            }
            var liveDays = Set<GregorianDay>()
            for copy in copies {
                for raw in copy["logs"] as? [Any] ?? [] {
                    guard let text = raw as? String, let day = try? GregorianDay(text) else { count("skipped.logDay"); continue }
                    if !liveDays.insert(day).inserted { count("deduped.logDay") }
                }
            }
            var removed: [GregorianDay: Date] = [:], uncertainDeletions = Set<GregorianDay>()
            let prefix = "habitlog:" + sourceID + ":"
            for (key, raw) in deleted where key.hasPrefix(prefix) {
                guard let day = try? GregorianDay(String(key.dropFirst(prefix.count))) else { count("skipped.logDeletion"); continue }
                guard let stamp = milliseconds(raw) else {
                    uncertainDeletions.insert(day); count("skipped.logDeletion"); continue
                }
                removed[day] = stamp
            }
            let allDays = liveDays.union(removed.keys).subtracting(uncertainDeletions)
            let start = allDays.min() ?? observedDay
            let explicitStamp = milliseconds(row["updatedAt"])
            let stamp = explicitStamp ?? start.date(in: zone)
            // A fallback timestamp is not evidence of an edit. Only the actual
            // legacy updatedAt can prove that the owner restored a deleted item.
            let tombstone = milliseconds(deleted[sourceID])
            if deleted[sourceID] != nil, tombstone == nil { count("skipped.itemDeletion"); continue }
            let deletion = tombstone.flatMap { removed in explicitStamp.map { $0 > removed } == true ? nil : removed }
            let id = uuid("myDream:Habit:" + sourceID)
            result.habits.append(.init(id: id, sourceID: sourceID, name: name,
                icon: row["icon"] as? String ?? "", color: row["color"] as? String ?? "",
                start: start, updatedAt: max(stamp, deletion ?? .distantPast), deletedAt: deletion,
                deletionBarrierAt: tombstone, restoredAt: tombstone.flatMap { removed in explicitStamp.flatMap { $0 > removed ? $0 : nil } }, order: position))
            for day in allDays.sorted() {
                result.events.append(.init(id: uuid("myDream:HabitEvent:\(sourceID):\(day)"), habitID: id, day: day, deletedAt: removed[day]))
            }
            if frozen.contains(sourceID), deletion == nil {
                // No freeze-start history exists in the old model. Observe current
                // frozen state now; never backdate a pause across unknown history.
                result.pauses.append(.init(id: uuid("myDream:HabitPause:" + sourceID), habitID: id, observedFrom: observedDay))
                count("pause.startUnknown")
            }
        }
        // Keep all freeze keys (including unsupported built-in cards), relevant
        // deletion evidence, singleton timestamps and unknown source fields intact.
        let relevant = deleted.filter { groups[$0.key] != nil || $0.key.hasPrefix("habitlog:") }
        let metadata: [String: Any] = ["frozenHabits": root["frozenHabits"] ?? NSNull(),
            "fieldUpdatedAt": root["fieldUpdatedAt"] ?? NSNull(), "deleted": relevant,
            "freezeObservedDay": observedDay.description, "freezeStartKnown": false]
        result.archives.append(.init(sourceID: "metadata", json: try json(metadata)))
        count("archived.freezeKey", frozen.filter { groups[$0] == nil }.count)
        count("habits", result.habits.count); count("events.live", result.events.filter { $0.deletedAt == nil }.count)
        count("events.deleted", result.events.filter { $0.deletedAt != nil }.count); count("pauses", result.pauses.count)
        return result
    }
}
