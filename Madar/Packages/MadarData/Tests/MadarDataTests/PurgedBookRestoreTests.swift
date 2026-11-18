import Foundation
import Testing
@testable import MadarData

@MainActor struct PurgedBookRestoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func row(_ model: String, _ fields: [String: JSONValue]) throws -> DataRecord {
        var f = fields; if f["id"] == nil { f["id"] = .string(UUID().uuidString) }
        var r = DataRecord(model: model, fields: f)
        try r.set(now.addingTimeInterval(-86_400), for: "updatedAt"); try r.set(now.addingTimeInterval(-86_400), for: "createdAt")
        return r
    }

    @Test(arguments: [RestoreMode.replace, RestoreMode.merge])
    func olderBackupNeverBringsBackAPurgedBooksDependents(mode: RestoreMode) throws {
        let bookID = UUID(), fileID = UUID(), other = UUID()
        var purged = try row("Book", ["id": .string(bookID.uuidString), "title": .string("")])
        try purged.set(now, for: "deletedAt"); try purged.set(now, for: "deletionBarrierAt"); try purged.set(now, for: "updatedAt")
        let general = try row("NotebookNote", ["targetID": .string(bookID.uuidString), "link": .string("general")])
        let incoming = [
            try row("Book", ["id": .string(bookID.uuidString), "title": .string("كتاب"), "mediaID": .string(fileID.uuidString)]),
            try row("Highlight", ["bookID": .string(bookID.uuidString)]),
            try row("NotebookNote", ["targetID": .string(bookID.uuidString), "link": .string("book")]),
            general,
            try row("NotebookNote", ["id": .string(StableIdentity.uuid(for: "GoodreadsPrivateNote:\(bookID.uuidString)").uuidString), "targetID": .string(bookID.uuidString), "link": .string("general")]),
            try row("UserWord", ["bookID": .string(bookID.uuidString)]),
            try row("Media", ["id": .string(fileID.uuidString)]),
            try row("Media", ["sourceID": .string("book-cover:\(bookID.uuidString)")]),
            try row("Media", ["sourceID": .string("pdf-ink:\(bookID.uuidString):3")]),
            try row("Highlight", ["bookID": .string(other.uuidString)]),
        ]
        let existing = [purged, general, try row("Book", ["title": .string("آخر")])]
        let planned = try BackupCoordinator.plan(existing: existing, incoming: incoming, mode: mode, now: now.addingTimeInterval(60), writerID: "test")
        let live = planned.filter(\.isLive)
        #expect(!live.contains { $0.model == "Highlight" && $0.fields["bookID"]?.string == bookID.uuidString })
        #expect(live.filter { $0.model == "NotebookNote" }.map(\.id) == [general.id], "only the book's own general note survives; the book note and the Goodreads note stay gone")
        #expect(!live.contains { $0.model == "UserWord" })
        #expect(!live.contains { $0.model == "Media" })
        #expect(!live.contains { $0.model == "Book" && $0.id == bookID })
        #expect(live.contains { $0.model == "Highlight" && $0.fields["bookID"]?.string == other.uuidString })
    }
}
