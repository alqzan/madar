import Foundation
import CoreFoundation

/// Remaining personal rows in the pinned My-dream backup. Original day strings
/// are Gregorian keys; no device timezone conversion or guessed clock is applied.
public enum LegacyPersonalImport {
    public struct Provenance: Equatable, Sendable {
        public let updatedAt: Date, deletedAt: Date?, deletionBarrierAt: Date?, restoredAt: Date?
    }
    public struct LetterRow: Equatable, Sendable {
        public let id: UUID, sourceID: String, text: String, writtenDay: GregorianDay, deliveryDay: GregorianDay
        public let opened: Bool, openedDay: GregorianDay?, provenance: Provenance
    }
    public struct DayRow: Equatable, Sendable {
        public let id: UUID, sourceID: String, title: String, day: GregorianDay, provenance: Provenance
    }
    public struct Archive: Equatable, Sendable {
        public let model: String, sourceID: String, json: Data
    }
    public struct Plan: Equatable, Sendable {
        public var letters: [LetterRow] = []
        public var days: [DayRow] = []
        public var archives: [Archive] = []
        public var counts: [String: Int] = [:]
    }
    public static func plan(backup: Data, observedDay: GregorianDay, zone: TimeZone, uuid: (String) -> UUID) throws -> Plan {
        guard let root = try JSONSerialization.jsonObject(with: backup) as? [String: Any] else { throw CoreError.invalidCommand }
        let deleted = root["deleted"] as? [String: Any] ?? [:]
        var result = Plan()
        func count(_ key: String) { result.counts[key, default: 0] += 1 }
        func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) }
        func timestamp(_ raw: Any?) -> Date? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: n.doubleValue / 1000)
        }
        func boolean(_ raw: Any?) -> Bool? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        }
        func provenance(_ row: [String: Any], id: String, fallback: GregorianDay) -> Provenance? {
            let explicit = timestamp(row["updatedAt"]), removed = timestamp(deleted[id])
            if deleted[id] != nil, removed == nil { count("skipped.deletion"); return nil }
            let deletion = removed.flatMap { tombstone in explicit.map { $0 > tombstone } == true ? nil : tombstone }
            return .init(updatedAt: max(explicit ?? fallback.date(in: zone), deletion ?? .distantPast), deletedAt: deletion,
                deletionBarrierAt: removed, restoredAt: removed.flatMap { tombstone in explicit.flatMap { $0 > tombstone ? $0 : nil } })
        }
        for (key, model) in [("futureLetters", "FutureLetter"), ("countdownEvents", "CountdownEvent")] {
            guard root[key] == nil || root[key] is [Any] else { throw CoreError.invalidCommand }
            var groups: [String: [[String: Any]]] = [:]
            for (index, raw) in (root[key] as? [Any] ?? []).enumerated() {
                guard let row = raw as? [String: Any], let id = row["id"] as? String, !id.isEmpty else {
                    result.archives.append(.init(model: model + ".invalid", sourceID: "invalid:\(index)", json: try json(raw)))
                    count("skipped.identity"); continue
                }
                groups[id, default: []].append(row)
            }
            for id in groups.keys.sorted() {
                let copies = groups[id]!
                let raw: [String: Any] = ["rows": copies, "deletedAt": deleted[id] ?? NSNull()]
                result.archives.append(.init(model: model, sourceID: id, json: try json(raw)))
                let sorted = try copies.map { (row: $0, raw: try json($0)) }.sorted {
                    let a = timestamp($0.row["updatedAt"]) ?? .distantPast, b = timestamp($1.row["updatedAt"]) ?? .distantPast
                    return a == b ? $0.raw.lexicographicallyPrecedes($1.raw) : a < b
                }
                let row = sorted.last!.row
                if model == "FutureLetter" {
                    guard let text = row["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let written = (row["writtenDate"] as? String).flatMap({ try? GregorianDay($0) }),
                          let delivery = (row["deliveryDate"] as? String).flatMap({ try? GregorianDay($0) }),
                          let meta = provenance(row, id: id, fallback: written) else { count("skipped.letter"); continue }
                    let opened = boolean(row["opened"]) == true
                    let openedDay = opened ? (row["openedDate"] as? String).flatMap({ try? GregorianDay($0) }) : nil
                    // An explicit opened flag survives even if its clock/day was not
                    // recorded. A stray openedDate alone never reveals sealed text.
                    result.letters.append(.init(id: uuid("myDream:Letter:" + id), sourceID: id, text: text,
                        writtenDay: written, deliveryDay: delivery, opened: opened, openedDay: openedDay, provenance: meta))
                } else {
                    // Count-up requires an owner-approved model field. Archive its
                    // complete source instead of silently changing that behavior.
                    if boolean(row["countUpAfter"]) == true { count("archived.countUpAfter"); continue }
                    if row["countUpAfter"] != nil, boolean(row["countUpAfter"]) == nil { count("skipped.countUpAfter"); continue }
                    guard let title = row["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let day = (row["date"] as? String).flatMap({ try? GregorianDay($0) }),
                          let meta = provenance(row, id: id, fallback: observedDay) else { count("skipped.day"); continue }
                    // Pinned source default: hide after occurrence when the optional
                    // countUpAfter flag is absent. No recurrence is inferred.
                    result.days.append(.init(id: uuid("myDream:UpcomingDay:" + id), sourceID: id, title: title, day: day, provenance: meta))
                }
            }
        }
        result.counts["letters"] = result.letters.count; result.counts["days"] = result.days.count
        return result
    }
}
