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
}
