import Foundation
import SwiftData

private struct ModelDefinition: Decodable { let name: String; let naturalKey: JSONValue; let fields: [FieldDefinition] }
private struct FieldDefinition: Decodable { let name: String; let fk: String? }
private struct DictionarySpec: Decodable { let models: [ModelDefinition]; let reconcileOrder: [String] }

/// Context confined. One app-owned context; Intents perform upserts but never deduplicate.
@MainActor public final class RowMerger {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }
    @discardableResult public func run() throws -> Int {
        do {
            let instances = try RecordBridge.instances(context)
            let original = try instances.map { try $0.record() }
            let result = try Self.reconciled(original)
            let changed = result.indices.filter { result[$0] != original[$0] }
            for index in changed { try instances[index].apply(result[index]) }
            if !changed.isEmpty { try context.save() }
            return changed.count
        } catch { context.rollback(); throw error }
    }
    public func restore(model: String, id: UUID, now: Date = Date(), writerID: String = "") throws {
        let rows = try RecordBridge.all(context)
        let resolved = Self.resolve(id: id, model: model, rows: rows)
        guard var row = rows.first(where: { $0.model == model && $0.id == resolved && $0.fields["mergedInto"] == .null }) else { throw DataError.invalidValue("restore target") }
        let barrier = max(row.date("deletionBarrierAt") ?? .distantPast, row.deletedAt ?? .distantPast)
        let stamp = max(StableIdentity.monotonic(now: now, previous: row.date("updatedAt") ?? .distantPast), barrier.addingTimeInterval(0.001))
        try row.set(stamp, for: "restoredAt"); try row.set(Optional<Date>.none, for: "deletedAt"); try row.set(stamp, for: "updatedAt"); try row.set(writerID, for: "writerID")
        try RecordBridge.upsert(row, in: context); try context.save()
    }
    public static func resolve(id: UUID, model: String, rows: [DataRecord]) -> UUID {
        var current = id; var seen = Set<UUID>()
        while seen.insert(current).inserted, let row = rows.first(where: { $0.model == model && $0.id == current && $0.fields["mergedInto"] == .null }) ?? rows.first(where: { $0.model == model && $0.id == current }), let value = row.fields["mergedInto"]?.string, let next = UUID(uuidString: value) { current = next }
        return current
    }
    /// Where `resolve` looks, built once per pass. Owner 7 Nov 2026 («أول ما أفتح التطبيق يعلق»): the linear search above ran for every
    /// foreign key of every row, so the merge after each launch grew with the square of the store (3.4 s on the main thread with real data).
    /// For each (model, id) it keeps the first unmerged row and the first row in array order, exactly the two rows `resolve` picks between.
    struct ResolveIndex {
        var unmerged: [String: Int] = [:]
        var first: [String: Int] = [:]
        init(_ rows: [DataRecord]) {
            for index in rows.indices {
                let key = Self.key(rows[index].model, rows[index].id)
                if first[key] == nil { first[key] = index }
                if unmerged[key] == nil, rows[index].fields["mergedInto"] == .null { unmerged[key] = index }
            }
        }
        static func key(_ model: String, _ id: UUID) -> String { model + "|" + id.uuidString }
    }
    /// Same answer as `resolve(id:model:rows:)` while no row's model, id or unmerged state changes after `index` was built.
    /// Rewriting a `mergedInto` to the end of its own chain (what the passes below do) keeps every answer the same.
    static func resolve(id: UUID, model: String, rows: [DataRecord], index: ResolveIndex) -> UUID {
        var current = id; var seen = Set<UUID>()
        while seen.insert(current).inserted {
            let key = ResolveIndex.key(model, current)
            guard let position = index.unmerged[key] ?? index.first[key],
                  let value = rows[position].fields["mergedInto"]?.string, let next = UUID(uuidString: value) else { break }
            current = next
        }
        return current
    }
    public static func mergeVersions(_ lhs: DataRecord, _ rhs: DataRecord) throws -> DataRecord {
        guard lhs.model == rhs.model && lhs.id == rhs.id else { throw DataError.invalidValue("logical record version mismatch") }
        var winner = newer(lhs,than:rhs) ? lhs : rhs
        let duplicates = [lhs,rhs]
        let barrier = duplicates.compactMap { maxOptional($0.deletedAt,$0.date("deletionBarrierAt")) }.max()
        let restoration = duplicates.compactMap { $0.date("restoredAt") }.max()
        try winner.set(barrier,for:"deletionBarrierAt"); try winner.set(restoration,for:"restoredAt")
        if let barrier, restoration == nil || restoration! <= barrier { try winner.set(barrier,for:"deletedAt") }
        else if restoration != nil { try winner.set(Optional<Date>.none,for:"deletedAt") }
        try mergeExceptions(winner:&winner,duplicates:duplicates)
        return winner
    }
    public static func reconciled(_ input: [DataRecord]) throws -> [DataRecord] {
        guard let url = Bundle.module.url(forResource: "data-dictionary", withExtension: "json") else { throw DataError.invalidValue("dictionary missing") }
        let spec = try JSONDecoder().decode(DictionarySpec.self, from: Data(contentsOf: url))
        var rows = input
        // Resolve previously persisted aliases too, including children imported after an earlier merge.
        let aliasIndex = ResolveIndex(rows)
        for i in rows.indices {
            guard let definition = spec.models.first(where: { $0.name == rows[i].model }) else { continue }
            for field in definition.fields {
                guard var target = field.fk else { continue }
                if target == "(targetModel)" { target = rows[i].fields["targetModel"]?.string ?? "" }
                if let text = rows[i].fields[field.name]?.string, let id = UUID(uuidString:text) { rows[i].fields[field.name] = .string(resolve(id:id,model:target,rows:rows,index:aliasIndex).uuidString) }
                else if let values = rows[i].fields[field.name]?.array { rows[i].fields[field.name] = .array(values.map { value in guard let text = value.string, let id = UUID(uuidString:text) else { return value }; return .string(resolve(id:id,model:target,rows:rows,index:aliasIndex).uuidString) }) }
            }
        }
        for i in rows.indices where rows[i].fields["mergedInto"] == .null {
            let barrier = maxOptional(rows[i].deletedAt, rows[i].date("deletionBarrierAt"))
            if let barrier {
                try rows[i].set(barrier,for:"deletionBarrierAt")
                if (rows[i].date("restoredAt") ?? .distantPast) <= barrier { try rows[i].set(barrier,for:"deletedAt") }
                else { try rows[i].set(Optional<Date>.none,for:"deletedAt") }
            }
        }
        for _ in 0..<3 {
            let before = rows
            for name in spec.reconcileOrder {
                guard let definition = spec.models.first(where: { $0.name == name }) else { continue }
                let candidates = rows.indices.filter { rows[$0].model == name && rows[$0].fields["mergedInto"] == .null }
                var groups: [[Int]] = []
                // Union applicable natural keys and id. Includes tombstones.
                // Keys are encoded once per row; `owners` maps a key to the group ids holding it, so a candidate finds its
                // groups without re-encoding every member's keys (the JSON encoding was the cost; the scan over group ids stays but is integer-only).
                var groupIDs: [Int] = []   // parallel to `groups`
                var owners: [String: Set<Int>] = [:]
                var nextGroupID = 0
                for index in candidates {
                    let keys = try logicalKeys(rows[index], definition: definition)
                    let touched = keys.reduce(into: Set<Int>()) { $0.formUnion(owners[$1] ?? []) }
                    let matching = groups.indices.filter { touched.contains(groupIDs[$0]) }
                    var joined = [index], joinedKeys = keys
                    for g in matching.reversed() { joined += groups.remove(at: g); groupIDs.remove(at: g) }
                    for i in joined where i != index { joinedKeys.formUnion((try? logicalKeys(rows[i], definition: definition)) ?? []) }
                    let gid = nextGroupID; nextGroupID += 1
                    for key in joinedKeys { owners[key] = (owners[key] ?? []).subtracting(touched).union([gid]) }
                    groups.append(joined); groupIDs.append(gid)
                }
                for group in groups where group.count > 1 {
                    let ordered = group.sorted { newer(rows[$0], than: rows[$1]) }; let winnerIndex = ordered[0]
                    let duplicateRows = ordered.map { rows[$0] }
                    let barrier = duplicateRows.compactMap { maxOptional($0.deletedAt, $0.date("deletionBarrierAt")) }.max()
                    let restoration = duplicateRows.compactMap { $0.date("restoredAt") }.max()
                    try rows[winnerIndex].set(barrier, for: "deletionBarrierAt"); try rows[winnerIndex].set(restoration, for: "restoredAt")
                    if let barrier, restoration == nil || restoration! <= barrier { try rows[winnerIndex].set(barrier, for: "deletedAt") }
                    else if restoration != nil { try rows[winnerIndex].set(Optional<Date>.none, for: "deletedAt") }
                    try mergeExceptions(winner: &rows[winnerIndex], duplicates: duplicateRows)
                    let winnerID = rows[winnerIndex].id
                    for loserIndex in ordered.dropFirst() {
                        let loserID = rows[loserIndex].id
                        // ImportLink alias merges target rows as well, but only within the same named model.
                        if name == "ImportLink", rows[loserIndex].fields["targetModel"] == rows[winnerIndex].fields["targetModel"], let target = rows[loserIndex].fields["targetID"]?.string, let targetWinner = rows[winnerIndex].fields["targetID"]?.string, target != targetWinner, let ti = rows.firstIndex(where: { $0.model == rows[winnerIndex].fields["targetModel"]?.string && $0.id.uuidString == target }) {
                            if let wi = rows.firstIndex(where: { $0.model == rows[ti].model && $0.id.uuidString == targetWinner && $0.fields["mergedInto"] == .null }) {
                                let targetDuplicates = [rows[wi],rows[ti]]
                                let barrier = targetDuplicates.compactMap { maxOptional($0.deletedAt,$0.date("deletionBarrierAt")) }.max()
                                let restoration = targetDuplicates.compactMap { $0.date("restoredAt") }.max()
                                var targetRow = newer(rows[ti],than:rows[wi]) ? rows[ti] : rows[wi]
                                try targetRow.set(rows[wi].id,for:"id"); try targetRow.set(barrier,for:"deletionBarrierAt"); try targetRow.set(restoration,for:"restoredAt")
                                if let barrier, restoration == nil || restoration! <= barrier { try targetRow.set(barrier,for:"deletedAt") }
                                else if restoration != nil { try targetRow.set(Optional<Date>.none,for:"deletedAt") }
                                try mergeExceptions(winner:&targetRow,duplicates:targetDuplicates); rows[wi] = targetRow
                            }
                            rows[ti].fields["mergedInto"] = .string(targetWinner)
                            if rows[ti].deletedAt == nil { rows[ti].fields["deletedAt"] = rows[winnerIndex].fields["updatedAt"] }
                        }
                        try rows[loserIndex].set(winnerID, for: "mergedInto")
                        if rows[loserIndex].deletedAt == nil { rows[loserIndex].fields["deletedAt"] = rows[winnerIndex].fields["updatedAt"] }
                        for childIndex in rows.indices {
                            guard let childDef = spec.models.first(where: { $0.name == rows[childIndex].model }) else { continue }
                            for field in childDef.fields where field.fk == name || (field.fk == "(targetModel)" && rows[childIndex].fields["targetModel"]?.string == name) {
                                if rows[childIndex].fields[field.name] == .string(loserID.uuidString) { rows[childIndex].fields[field.name] = .string(winnerID.uuidString) }
                                else if case .array(let ids) = rows[childIndex].fields[field.name] { rows[childIndex].fields[field.name] = .array(ids.map { $0 == .string(loserID.uuidString) ? .string(winnerID.uuidString) : $0 }) }
                            }
                        }
                    }
                }
            }
            let passIndex = ResolveIndex(rows)
            for i in rows.indices {
                guard let definition = spec.models.first(where: { $0.name == rows[i].model }) else { continue }
                for field in definition.fields {
                    guard let fk = field.fk else { continue }
                    let target = fk == "(targetModel)" ? (rows[i].fields["targetModel"]?.string ?? "") : fk
                    if let text = rows[i].fields[field.name]?.string, let id = UUID(uuidString:text) { rows[i].fields[field.name] = .string(resolve(id:id,model:target,rows:rows,index:passIndex).uuidString) }
                    else if let values = rows[i].fields[field.name]?.array { rows[i].fields[field.name] = .array(values.map { value in guard let text = value.string, let id = UUID(uuidString:text) else { return value }; return .string(resolve(id:id,model:target,rows:rows,index:passIndex).uuidString) }) }
                }
            }
            try cascade(&rows)
            try repair(&rows)
            if rows == before { break }
        }
        return rows
    }
    private static func newer(_ lhs: DataRecord, than rhs: DataRecord) -> Bool {
        let l = lhs.date("updatedAt") ?? .distantPast, r = rhs.date("updatedAt") ?? .distantPast
        if l != r { return l > r }; let lw = lhs.fields["writerID"]?.string ?? "", rw = rhs.fields["writerID"]?.string ?? ""
        if lw != rw { return lw > rw }; return lhs.id.uuidString > rhs.id.uuidString
    }
    private static func maxOptional(_ a: Date?, _ b: Date?) -> Date? { [a,b].compactMap { $0 }.max() }
    private static func logicalKeys(_ row: DataRecord, definition: ModelDefinition) throws -> Set<String> {
        var keys: Set<String> = ["id:\(row.id)"]
        func key(_ fields: [String]) throws -> String { String(data: try JSONValue.array(fields.map { row.fields[$0] ?? .null }).canonicalData(), encoding: .utf8)! }
        if let fields = definition.naturalKey.array?.compactMap(\.string), fields.allSatisfy({ row.fields[$0] != nil }) { keys.insert(try key(fields)) }
        switch row.model {
        case "Entry": if row.fields["sourceID"]?.string != nil { keys.insert(try key(["source","sourceID","sourceBranch"])) }; if row.fields["pinnedEventID"]?.string != nil { keys.insert(try key(["pinnedEventKind","pinnedEventID"])) }
        case "Media": if row.fields["sourceID"]?.string != nil { keys.insert(try key(["sourceID"])) }
        case "Book": if row.fields["sourceGoodreadsID"]?.string != nil { keys.insert(try key(["sourceGoodreadsID"])) }
        case "HifzSession": if row.fields["commitID"]?.string != nil { keys.insert(try key(["commitID"])) }
        case "Allocation": if let s = row.fields["idempotencyKey"]?.string, !s.isEmpty { keys.insert(try key(["idempotencyKey"])) }
        case "Envelope": if ["reserve","surplus"].contains(row.fields["role"]?.string ?? "") { keys.insert(try key(["role"])) }
        case "ZakatProfile": keys.insert("singleton")
        case "UserWord":
            let text = row.fields["word"]?.string ?? ""
            keys.insert(UserWordIdentity.key(language: row.fields["language"]?.string ?? "ar", word: text))
        case "Statement", "Cycle":
            let field = row.model == "Statement" ? "closeDate" : "start"
            if let date = row.date(field) { let day = Int(floor(date.timeIntervalSince1970 / 86400)); keys.insert("\(row.fields["cardID"]?.string ?? ""):\(day)") }
        default: break
        }
        return keys
    }
    private static func mergeExceptions(winner: inout DataRecord, duplicates: [DataRecord]) throws {
        switch winner.model {
        case "HabitLog": if winner.isLive { winner.fields["value"] = .number(duplicates.filter(\.isLive).compactMap { $0.fields["value"]?.number }.max() ?? 0) }
        case "Account": if let row = duplicates.max(by: { ($0.date("balanceAt") ?? .distantPast) < ($1.date("balanceAt") ?? .distantPast) }) { winner.fields["balanceAt"] = row.fields["balanceAt"]; winner.fields["balanceMinor"] = row.fields["balanceMinor"] }
        case "HadithProgress":
            winner.fields["understood"] = .bool(duplicates.contains { $0.fields["understood"] == .bool(true) })
            winner.fields["layersOpened"] = .array(Array(Set(duplicates.flatMap { $0.fields["layersOpened"]?.array ?? [] })).sorted { ($0.string ?? "") < ($1.string ?? "") })
            winner.fields["understoodDayKey"] = duplicates.compactMap { $0.fields["understoodDayKey"]?.string }.min().map(JSONValue.string) ?? .null
            try winner.set(duplicates.compactMap { $0.date("readAt") }.min(), for: "readAt")
        default: break
        }
    }
    private static func cascade(_ rows: inout [DataRecord]) throws {
        for parent in rows where parent.deletedAt != nil && parent.fields["mergedInto"] == .null {
            // RD2: margins and reading history have independent lifetimes. Keep the origin UUID
            // as provenance and the Book tombstone's title; never revive old child tombstones.
            let children: [(String,String)] = switch parent.model { case "HifzSession": [("PageGrade","sessionID"),("MistakeEvent","sessionID")]; default: [] }
            if parent.model == "Entry" {
                let mediaIDs = Set(([parent.fields["mediaID"] ?? .null] + (parent.fields["attachmentMediaIDs"]?.array ?? [])).compactMap(\.string))
                for i in rows.indices where rows[i].model == "Media" && mediaIDs.contains(rows[i].id.uuidString) {
                    let id = JSONValue.string(rows[i].id.uuidString)
                    let shared = rows.contains { row in
                        row.isLive && row.id != parent.id && row.model != "Media" && row.fields.values.contains { $0 == id || ($0.array?.contains(id) ?? false) }
                    }
                    if !shared { rows[i].fields["deletedAt"] = parent.fields["deletedAt"]; rows[i].fields["deletionBarrierAt"] = parent.fields["deletedAt"]; rows[i].fields["data"] = .null }
                }
            }
            for i in rows.indices where children.contains(where: { rows[i].model == $0.0 && rows[i].fields[$0.1] == .string(parent.id.uuidString) }) {
                if (rows[i].date("restoredAt") ?? .distantPast) <= parent.deletedAt!, (rows[i].deletedAt ?? .distantPast) < parent.deletedAt! { try rows[i].set(parent.deletedAt, for: "deletedAt"); try rows[i].set(parent.deletedAt, for: "deletionBarrierAt") }
            }
        }
    }
    private static func repair(_ rows: inout [DataRecord]) throws {
        let trips = rows.indices.filter { rows[$0].model == "Trip" && rows[$0].isLive && rows[$0].fields["end"] == .null && rows[$0].fields["dismissed"] == .bool(false) }
        if let winner = trips.max(by: { (rows[$0].date("start") ?? .distantPast) < (rows[$1].date("start") ?? .distantPast) }) { for i in trips where i != winner { rows[i].fields["end"] = rows[winner].fields["start"] == .null ? rows[winner].fields["createdAt"] : rows[winner].fields["start"] } }
        let plans = rows.indices.filter { rows[$0].model == "HifzPlan" && rows[$0].isLive && rows[$0].fields["supersededAt"] == .null }
        if let winner = plans.max(by: { (rows[$0].fields["version"]?.number ?? 0) < (rows[$1].fields["version"]?.number ?? 0) }) { for i in plans where i != winner { rows[i].fields["supersededAt"] = rows[winner].fields["activeFrom"] } }
        let recoveries = rows.indices.filter { rows[$0].model == "RecoveryPlan" && rows[$0].isLive && rows[$0].fields["cancelledAt"] == .null }
        if let winner = recoveries.max(by: { (rows[$0].fields["startDayKey"]?.string ?? "") < (rows[$1].fields["startDayKey"]?.string ?? "") }) { for i in recoveries where i != winner { rows[i].fields["cancelledAt"] = rows[winner].fields["createdAt"] } }
        for i in rows.indices where rows[i].model == "Envelope" && rows[i].isLive {
            let allocations = rows.filter { $0.model == "Allocation" && $0.isLive && $0.fields["targetID"] == .string(rows[i].id.uuidString) }
            rows[i].fields["balanceMinor"] = .number(allocations.reduce(0) { $0 + ($1.fields["amountMinor"]?.number ?? 0) })
        }
    }
}
