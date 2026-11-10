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

    /// Owner, 10 Nov 2026 («احذف نهائيًا» في سلة المحبرة): a trashed book, its file, cover, drawings, highlights, notes and
    /// saved words are wiped for good; the tombstone row stays (RA4), reading history and every other book stay as they were.
    @Test func purgingATrashedBookWipesItsContentAndKeepsEverythingElse() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookPurge-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!, later = now.addingTimeInterval(86_400)
        let bookID = UUID(), otherID = UUID(), mediaID = UUID(), otherMediaID = UUID()
        let bytes = Data("synthetic EPUB to purge".utf8), hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        func media(_ id: UUID, kind: String, type: String, source: String?, data: Data) {
            let row = Media(); row.id = id; row.kind = kind; row.contentType = type; row.sourceID = source; row.state = "ok"; row.data = data; row.sizeBytes = data.count
            row.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); context.insert(row)
        }
        media(mediaID, kind: "doc", type: "org.idpf.epub-container", source: nil, data: bytes)
        let coverID = UUID(), inkID = UUID()
        media(coverID, kind: "photo", type: "image/png", source: "book-cover:\(bookID.uuidString)", data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1]))
        media(inkID, kind: "drawing", type: "application/x-pencilkit-drawing", source: "pdf-ink:\(bookID.uuidString):3", data: Data("ink".utf8))
        media(otherMediaID, kind: "doc", type: "org.idpf.epub-container", source: nil, data: Data("other book file".utf8))
        let book = Book(); book.id = bookID; book.title = "كتاب سيُحذف نهائيًا"; book.author = "مؤلف"; book.kind = "file"; book.format = "epub"; book.shelf = "want"
        book.mediaID = mediaID; book.fileHash = hash; book.isbn13 = "9780000000002"; book.review = "رأيي"; book.rating = 4; book.currentPage = 9; context.insert(book)
        let other = Book(); other.id = otherID; other.title = "كتاب آخر يبقى"; other.kind = "file"; other.format = "epub"; other.mediaID = otherMediaID; other.fileHash = "x"; context.insert(other)
        let session = ReadingSession(); session.id = UUID(); session.bookID = bookID; session.start = now; session.end = now.addingTimeInterval(120); session.activeSeconds = 120; session.fromPage = 1; session.toPage = 3; session.pagesCounted = 2; context.insert(session)
        let highlight = Highlight(); highlight.id = UUID(); highlight.bookID = bookID; highlight.locatorJSON = Data("{\"href\":\"a\"}".utf8); highlight.color = "yellow"; highlight.note = "ملاحظة التظليل"; context.insert(highlight)
        let note = NotebookNote(); note.id = UUID(); note.text = "ملاحظة على الكتاب"; note.link = "book"; note.targetID = bookID; context.insert(note)
        let unrelated = NotebookNote(); unrelated.id = UUID(); unrelated.text = "ملاحظة عامة تبقى"; unrelated.link = "general"; context.insert(unrelated)
        let word = UserWord(); word.id = UUID(); word.word = "كلمة"; word.bookID = bookID; word.bookTitle = "كتاب سيُحذف نهائيًا"; word.context = "سياق الكلمة"; context.insert(word)
        try context.save()

        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ id: UUID, at t: Date) async throws -> CommandOutcome { try await bus.execute(.init(name: name, payload: .object(["id": .string(id.uuidString)]), issuedAt: t), now: t) }
        #expect(BookCommand.parse("book.purge", ["id": .string(bookID.uuidString)]) == .purgeBook(id: bookID))
        #expect(BookCommand.parse("book.purge", ["id": .string(bookID.uuidString), "extra": .bool(true)]) == nil)
        #expect(BookCommand.names.contains("book.purge"))
        // A book on the shelves is never purged: only the trash offers it.
        #expect(try await run("book.purge", bookID, at: now).status != .applied)
        #expect(try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first { $0.id == bookID }).title == "كتاب سيُحذف نهائيًا")

        #expect(try await run("book.delete", bookID, at: now).status == .applied)
        let purged = try await run("book.purge", bookID, at: later)
        #expect(purged.status == .applied); #expect(purged.undoToken == nil)

        let after = ModelContext(container)
        let tomb = try #require(after.fetch(FetchDescriptor<Book>()).first { $0.id == bookID })
        #expect(tomb.deletedAt != nil && tomb.deletionBarrierAt != nil)
        #expect(tomb.title.isEmpty && tomb.author.isEmpty && tomb.isbn13 == nil && tomb.fileHash == nil && tomb.mediaID == nil && tomb.review == nil && tomb.rating == nil && tomb.currentPage == nil)
        for id in [mediaID, coverID, inkID] {
            let row = try #require(after.fetch(FetchDescriptor<Media>()).first { $0.id == id })
            #expect(row.data == nil && row.sizeBytes == 0 && row.sha256.isEmpty && row.deletedAt != nil, "media \(id) must be wiped")
        }
        let h = try #require(after.fetch(FetchDescriptor<Highlight>()).first { $0.id == highlight.id })
        #expect(h.deletedAt != nil && h.locatorJSON.isEmpty && h.note == nil)
        #expect(try #require(after.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == note.id }).text.isEmpty)
        #expect(try #require(after.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == note.id }).deletedAt != nil)
        let w = try #require(after.fetch(FetchDescriptor<UserWord>()).first { $0.id == word.id })
        #expect(w.deletedAt != nil && w.word.isEmpty && w.context.isEmpty && w.bookTitle.isEmpty)
        // Everything that is not this book's content stays.
        #expect(try #require(after.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == session.id }).deletedAt == nil)
        #expect(try #require(after.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == unrelated.id }).text == "ملاحظة عامة تبقى")
        #expect(try #require(after.fetch(FetchDescriptor<Book>()).first { $0.id == otherID }).title == "كتاب آخر يبقى")
        let otherMedia = try #require(after.fetch(FetchDescriptor<Media>()).first { $0.id == otherMediaID })
        #expect(otherMedia.data == Data("other book file".utf8) && otherMedia.deletedAt == nil)
        // A purged book cannot come back from the trash, and purging twice is refused.
        #expect(try await run("book.restore", bookID, at: later).status != .applied)
        #expect(try await run("book.purge", bookID, at: later).status != .applied)
    }

    /// The same file bytes can belong to two books; purging one must not take the other's file with it.
    @Test func purgingKeepsAFileAnotherBookStillUses() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookPurgeShared-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
        let gone = UUID(), keeper = UUID(), mediaID = UUID()
        let bytes = Data("same bytes".utf8)
        let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.state = "ok"; media.data = bytes; media.sizeBytes = bytes.count
        media.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(); context.insert(media)
        for (id, title) in [(gone, "نسخة محذوفة"), (keeper, "نسخة باقية")] {
            let b = Book(); b.id = id; b.title = title; b.kind = "file"; b.format = "epub"; b.mediaID = mediaID; b.fileHash = media.sha256; context.insert(b)
        }
        try context.save()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ id: UUID) async throws -> CommandOutcome { try await bus.execute(.init(name: name, payload: .object(["id": .string(id.uuidString)]), issuedAt: now), now: now) }
        #expect(try await run("book.delete", gone).status == .applied)
        #expect(try await run("book.purge", gone).status == .applied)
        let after = ModelContext(container)
        let kept = try #require(after.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID })
        #expect(kept.data == bytes && kept.deletedAt == nil && kept.state == "ok")
        #expect(try #require(after.fetch(FetchDescriptor<Book>()).first { $0.id == keeper }).title == "نسخة باقية")
        #expect(try #require(after.fetch(FetchDescriptor<Book>()).first { $0.id == gone }).title.isEmpty)
    }
}
