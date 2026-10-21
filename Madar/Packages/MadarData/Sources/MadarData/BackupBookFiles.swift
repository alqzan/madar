import Foundation

/// A book file left out of one backup because the backup would pass its size budget (RD4).
public struct BackupBookExclusion: Codable, Sendable, Equatable {
    public let title: String; public let bytes: Int; public let fromTurath: Bool
    public init(title: String, bytes: Int, fromTurath: Bool) { self.title = title; self.bytes = bytes; self.fromTurath = fromTurath }
}

/// RD4: photos, audio and records always travel; book files fill what is left of the budget.
/// A left-out file keeps its row as `state: "missing"` (a valid Media state, so older builds read the
/// backup), and a restore keeps the device's own bytes whenever the same file is still there.
enum BackupBookFiles {
    /// The plaintext archive budget. Below the codec's 512 MiB cap, with room for the in-memory copies one export makes.
    static let budget = 256 * 1024 * 1024

    static func estimatedBytes(_ records: [DataRecord]) -> Int {
        records.reduce(0) { total, row in
            if row.model == "Media", row.fields["data"].map({ $0 != .null }) ?? false {
                var light = row; light.fields["data"] = .null
                return total + Int(row.fields["sizeBytes"]?.number ?? 0) + ((try? JSONValue.object(light.fields).canonicalData().count) ?? 0)
            }
            return total + ((try? JSONValue.object(row.fields).canonicalData().count) ?? 0)
        }
    }

    /// Re-downloadable Turath files leave first, then the largest; ties keep a stable order by id.
    static func fitting(_ records: [DataRecord], budget: Int = budget) -> (records: [DataRecord], excluded: [BackupBookExclusion]) {
        var total = estimatedBytes(records)
        guard total > budget else { return (records, []) }
        var books: [UUID: (title: String, turath: Bool)] = [:]
        for row in records where row.model == "Book" && row.isLive {
            guard let raw = row.fields["mediaID"]?.string, let media = UUID(uuidString: raw) else { continue }
            books[media] = (row.fields["title"]?.string ?? "", row.fields["turathID"].map { $0 != .null } ?? false)
        }
        var rows = records
        let candidates = rows.indices.filter { i in
            rows[i].model == "Media" && rows[i].isLive && rows[i].fields["kind"]?.string == "doc"
                && rows[i].fields["state"]?.string == "ok" && (rows[i].fields["data"].map { $0 != .null } ?? false)
                && books[rows[i].id] != nil
        }.sorted { a, b in
            let ta = books[rows[a].id]!.turath, tb = books[rows[b].id]!.turath
            if ta != tb { return ta }
            let sa = Int(rows[a].fields["sizeBytes"]?.number ?? 0), sb = Int(rows[b].fields["sizeBytes"]?.number ?? 0)
            return sa != sb ? sa > sb : rows[a].id.uuidString < rows[b].id.uuidString
        }
        var excluded: [BackupBookExclusion] = []
        for i in candidates where total > budget {
            let size = Int(rows[i].fields["sizeBytes"]?.number ?? 0), book = books[rows[i].id]!
            rows[i].fields["data"] = .null; rows[i].fields["state"] = .string("missing")
            total -= size; excluded.append(.init(title: book.title, bytes: size, fromTurath: book.turath))
        }
        return (rows, excluded)
    }

    /// After a restore plan: a file the backup left out keeps the device's verified bytes.
    static func retainingLocalFiles(_ planned: [DataRecord], existing: [DataRecord]) -> [DataRecord] {
        let local = Dictionary(existing.filter { $0.model == "Media" && $0.isLive && $0.fields["state"]?.string == "ok" && ($0.fields["data"].map { $0 != .null } ?? false) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !local.isEmpty else { return planned }
        var rows = planned
        for i in rows.indices where rows[i].model == "Media" && rows[i].isLive && rows[i].fields["state"]?.string == "missing" && (rows[i].fields["data"].map { $0 == .null } ?? true) {
            guard let device = local[rows[i].id], let sha = rows[i].fields["sha256"]?.string, !sha.isEmpty,
                  device.fields["sha256"]?.string == sha, device.fields["sizeBytes"] == rows[i].fields["sizeBytes"] else { continue }
            rows[i].fields["data"] = device.fields["data"]; rows[i].fields["state"] = .string("ok")
        }
        return rows
    }
}
