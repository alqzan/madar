import Foundation
import Testing
import SwiftData
import CryptoKit
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct BookCommandBusTests {
    @Test func durableReplayAppOnlyAndTombstoneUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookBus-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, identity = UUID(), commandID = UUID()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let p: MadarCore.JSONValue = .object(["id":.string(identity.uuidString),"title":.string("كتاب"),"author":.string(""),"pages":.number(250),"shelf":.string("reading")])
        let denied = try await bus.execute(.init(name: "book.savePaper", payload: p, source: .shortcut, issuedAt: now), now: now)
        #expect(denied.status == .needsApp)
        let command = CommandEnvelope(commandID: commandID, name: "book.savePaper", payload: p, issuedAt: now)
        let first = try await bus.execute(command, now: now), second = try await bus.execute(command, now: now)
        #expect(first == second); #expect(first.status == .applied); #expect(first.undoToken != nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Book>()) == 1)
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken":.string(commandID.uuidString)]), issuedAt: now), now: now)
        #expect(undo.status == .applied)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        #expect(row.id == identity); #expect(row.deletedAt != nil); #expect(row.deletionBarrierAt != nil)
    }

    @Test func epubLocatorIsUndoableAndReadingSessionsAreSavedWithoutUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookReaderBus-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, bookID = UUID(), mediaID = UUID()
        let bytes = Data("synthetic EPUB test bytes".utf8), hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = hash; context.insert(media)
        let book = Book(); book.id = bookID; book.title = "كتاب اختباري"; book.kind = "file"; book.format = "epub"; book.mediaID = mediaID; book.fileHash = hash; book.shelf = "reading"; context.insert(book); try context.save()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let locator = "{\"href\":\"Text/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"position\":2,\"progression\":0.2,\"totalProgression\":0.2}}"
        let locatorID = UUID(), locatorPayload: MadarCore.JSONValue = .object(["id":.string(bookID.uuidString),"locator":.string(locator)])
        let locatorResult = try await bus.execute(.init(commandID: locatorID, name: "book.setLocator", payload: locatorPayload, issuedAt: now), now: now)
        #expect(locatorResult.status == .applied); #expect(locatorResult.undoToken != nil)
        #expect(try #require(context.fetch(FetchDescriptor<Book>()).first?.locatorJSON) == Data(locator.utf8))
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken":.string(locatorID.uuidString)]), issuedAt: now.addingTimeInterval(1)), now: now.addingTimeInterval(1))
        #expect(undo.status == .applied); #expect(try context.fetch(FetchDescriptor<Book>()).first?.locatorJSON == nil)

        let sessionID = UUID(), sessionCommandID = UUID()
        func sessionPayload(_ seconds: Int, end: String = "2026-10-17T12:02:00Z") -> MadarCore.JSONValue {
            .object(["id":.string(sessionID.uuidString),"bookID":.string(bookID.uuidString),"start":.string("2026-10-17T12:00:00Z"),"end":.string(end),"activeSeconds":.number(Double(seconds)),"fromPage":.number(2),"toPage":.number(4),"startLocator":.string(locator),"endLocator":.string(locator),"startProgression":.number(0.2),"endProgression":.number(0.3),"pagesCounted":.number(2)])
        }
        let saved = try await bus.execute(.init(commandID: sessionCommandID, name: "reading.saveSession", payload: sessionPayload(61), issuedAt: now), now: now)
        #expect(saved.status == .applied); #expect(saved.undoToken == nil)
        var sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1); #expect(sessions[0].activeSeconds == 61); #expect(sessions[0].bookID == bookID)
        #expect(sessions[0].tzID == "Asia/Riyadh"); #expect(sessions[0].dayPolicy == "fajr@1")
        let originalDay = sessions[0].dayKey, originalZone = sessions[0].tzID, originalPolicy = sessions[0].dayPolicy
        _ = try SettingsStore(context: context).stage(["core.dayStart": .string("midnight")]); try context.save()
        let updated = try await bus.execute(.init(name: "reading.saveSession", payload: sessionPayload(90, end: "2026-10-18T12:02:00Z"), issuedAt: now.addingTimeInterval(2)), now: now.addingTimeInterval(2))
        #expect(updated.status == .applied); #expect(updated.undoToken == nil)
        sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1); #expect(sessions[0].activeSeconds == 90)
        #expect(sessions[0].dayKey == originalDay)
        #expect(sessions[0].tzID == originalZone)
        #expect(sessions[0].dayPolicy == originalPolicy)
        let tooShort = try await bus.execute(.init(name: "reading.saveSession", payload: sessionPayload(59), issuedAt: now.addingTimeInterval(3)), now: now.addingTimeInterval(3))
        #expect(tooShort.status == .rejected); #expect(tooShort.reason == "invalidPayload")
    }

    @Test func deletingBookKeepsItsTitleReadingHistoryHighlightsAndFileAndCanUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookDelete-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, bookID = UUID(), mediaID = UUID()
        let bytes = Data("synthetic EPUB file retained after deleting its book".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = hash; context.insert(media)
        let book = Book(); book.id = bookID; book.title = "عنوان يبقى في السجل"; book.author = "مؤلف"; book.kind = "file"; book.format = "epub"; book.shelf = "want"; book.mediaID = mediaID; book.fileHash = hash; context.insert(book)
        let session = ReadingSession(); session.id = UUID(); session.bookID = bookID; session.start = now; session.end = now.addingTimeInterval(120); session.activeSeconds = 120; session.fromPage = 1; session.toPage = 3; session.pagesCounted = 2; context.insert(session)
        let highlight = Highlight(); highlight.id = UUID(); highlight.bookID = bookID; highlight.locatorJSON = Data(#"{"href":"Text/chapter.xhtml","type":"application/xhtml+xml"}"#.utf8); highlight.color = "yellow"; context.insert(highlight)
        try context.save()

        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let commandID = UUID(), payload: MadarCore.JSONValue = .object(["id": .string(bookID.uuidString)])
        #expect(BookCommand.parse("book.delete", ["id": .string(bookID.uuidString)]) == .deleteBook(id: bookID))
        #expect(BookCommand.parse("book.delete", ["id": .string(bookID.uuidString), "extra": .bool(true)]) == nil)
        let deleted = try await bus.execute(.init(commandID: commandID, name: "book.delete", payload: payload, issuedAt: now), now: now)
        #expect(deleted.status == .applied); #expect(deleted.undoToken != nil)

        let deletedBook = try #require(context.fetch(FetchDescriptor<Book>()).first { $0.id == bookID })
        #expect(deletedBook.deletedAt == now); #expect(deletedBook.deletionBarrierAt == now); #expect(deletedBook.title == "عنوان يبقى في السجل")
        #expect(try #require(context.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == session.id }).deletedAt == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Highlight>()).first { $0.id == highlight.id }).deletedAt == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }).data == bytes)

        let undone = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(commandID.uuidString)]), issuedAt: now.addingTimeInterval(1)), now: now.addingTimeInterval(1))
        #expect(undone.status == .applied)
        #expect(try #require(context.fetch(FetchDescriptor<Book>()).first { $0.id == bookID }).deletedAt == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }).data == bytes)
    }

    @Test func removingBookFileKeepsBookAndReadingHistoryAndCannotBeUndone() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookFileRemove-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, bookID = UUID(), mediaID = UUID()
        let bytes = Data("synthetic EPUB file to remove".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = hash; context.insert(media)
        let book = Book(); book.id = bookID; book.title = "كتاب يبقى بعد إزالة ملفه"; book.kind = "file"; book.format = "epub"; book.shelf = "want"; book.mediaID = mediaID; book.fileHash = hash; context.insert(book)
        let session = ReadingSession(); session.id = UUID(); session.bookID = bookID; session.start = now; session.end = now.addingTimeInterval(120); session.activeSeconds = 120; session.fromPage = 1; session.toPage = 3; session.pagesCounted = 2; context.insert(session)
        let highlight = Highlight(); highlight.id = UUID(); highlight.bookID = bookID; highlight.locatorJSON = Data(#"{"href":"Text/chapter.xhtml","type":"application/xhtml+xml"}"#.utf8); highlight.color = "yellow"; context.insert(highlight)
        try context.save()

        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        #expect(BookCommand.parse("book.removeFile", ["id": .string(bookID.uuidString)]) == .removeBookFile(id: bookID))
        #expect(BookCommand.parse("book.removeFile", ["id": .string(bookID.uuidString), "extra": .bool(true)]) == nil)
        let removed = try await bus.execute(.init(name: "book.removeFile", payload: .object(["id": .string(bookID.uuidString)]), issuedAt: now), now: now)
        #expect(removed.status == .applied); #expect(removed.undoToken == nil)

        let retainedBook = try #require(context.fetch(FetchDescriptor<Book>()).first { $0.id == bookID })
        #expect(retainedBook.deletedAt == nil); #expect(retainedBook.title == "كتاب يبقى بعد إزالة ملفه"); #expect(retainedBook.fileHash == hash)
        #expect(try #require(context.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == session.id }).deletedAt == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Highlight>()).first { $0.id == highlight.id }).deletedAt == nil)
        let missingMedia = try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID })
        #expect(missingMedia.data == nil); #expect(missingMedia.state == "missing"); #expect(missingMedia.sha256 == hash); #expect(missingMedia.sizeBytes == bytes.count)
    }
    /// «سلة المحذوفات» (owner, 30 Oct): a deleted book comes back after the undo window; a book that was being read
    /// waits in «أبي أقرأه» when the three reading places were filled meanwhile; a live book is not «restored».
    @Test func deletedBookRestoresFromTheTrash() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookTrash-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, later = now.addingTimeInterval(3 * 86_400)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ p: [String: MadarCore.JSONValue], at t: Date) async throws -> CommandOutcome { try await bus.execute(.init(name: name, payload: .object(p), issuedAt: t), now: t) }
        let gone = UUID()
        #expect(try await run("book.savePaper", ["id":.string(gone.uuidString),"title":.string("كتاب محذوف"),"author":.string(""),"pages":.number(200),"shelf":.string("reading")], at: now).status == .applied)
        #expect(try await run("book.delete", ["id":.string(gone.uuidString)], at: now).status == .applied)
        for n in 0..<3 { _ = try await run("book.savePaper", ["id":.string(UUID().uuidString),"title":.string("كتاب \(n)"),"author":.string(""),"pages":.number(100),"shelf":.string("reading")], at: now) }
        #expect(BookCommand.parse("book.restore", ["id": .string(gone.uuidString)]) == .restoreBook(id: gone))
        let restored = try await run("book.restore", ["id":.string(gone.uuidString)], at: later)
        #expect(restored.status == .applied && restored.undoToken != nil)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first { $0.id == gone })
        #expect(row.deletedAt == nil && row.restoredAt != nil && row.shelf == "want")
        #expect(try await run("book.restore", ["id":.string(gone.uuidString)], at: later).status != .applied)
    }
}
