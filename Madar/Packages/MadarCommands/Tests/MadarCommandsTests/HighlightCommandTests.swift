import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// M6-V08: a paragraph highlight and a page-linked note, written once, recoloured in place, undoable.
@MainActor struct HighlightCommandTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00+03:00")!
    private let paragraph = "{\"href\":\"OEBPS/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"cssSelector\":\"body > section > p:nth-child(3)\"}}"

    private func setUp(kind: String = "file") throws -> (CommandBus, ModelContainer, UUID, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "Highlight-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let book = Book(); book.id = UUID(); book.title = "كتاب"; book.kind = kind; book.format = kind == "file" ? "epub" : nil; book.shelf = "reading"
        context.insert(book); try context.save()
        return (CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), container, book.id, root)
    }

    @Test func highlightIsSavedRecolouredInPlaceAndUndone() async throws {
        let (bus, container, bookID, root) = try setUp(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        func save(_ color: String, at time: Date) async throws -> CommandOutcome {
            try await bus.execute(.init(name: "highlight.save", payload: .object(["id": .string(id.uuidString), "bookID": .string(bookID.uuidString), "locator": .string(paragraph), "color": .string(color), "pageLabel": .string("٤٥٣")]), issuedAt: time), now: time)
        }
        #expect(try await save("yellow", at: now).status == .applied)
        let recolourID = UUID(), later = now.addingTimeInterval(5)
        let recolour = try await bus.execute(.init(commandID: recolourID, name: "highlight.save", payload: .object(["id": .string(id.uuidString), "bookID": .string(bookID.uuidString), "locator": .string(paragraph), "color": .string("green")]), issuedAt: later), now: later)
        #expect(recolour.status == .applied)
        var rows = try ModelContext(container).fetch(FetchDescriptor<Highlight>())
        #expect(rows.count == 1); #expect(rows.first?.color == "green"); #expect(rows.first?.locatorJSON == Data(paragraph.utf8)); #expect(rows.first?.bookID == bookID)
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(recolourID.uuidString)]), issuedAt: later.addingTimeInterval(1)), now: later.addingTimeInterval(1))
        #expect(undo.status == .applied)
        rows = try ModelContext(container).fetch(FetchDescriptor<Highlight>())
        #expect(rows.first?.color == "yellow"); #expect(rows.first?.pageLabel == "٤٥٣"); #expect(rows.first?.deletedAt == nil)

        let deleteID = UUID(), end = later.addingTimeInterval(10)
        #expect(try await bus.execute(.init(commandID: deleteID, name: "highlight.delete", payload: .object(["id": .string(id.uuidString)]), issuedAt: end), now: end).status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Highlight>()).first?.deletedAt != nil)
        let restore = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(deleteID.uuidString)]), issuedAt: end.addingTimeInterval(1)), now: end.addingTimeInterval(1))
        #expect(restore.status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Highlight>()).first?.deletedAt == nil)
    }

    @Test func pageNoteIsLinkedToTheBookAndPlace() async throws {
        let (bus, container, bookID, root) = try setUp(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let result = try await bus.execute(.init(name: "notebook.savePage", payload: .object(["id": .string(id.uuidString), "bookID": .string(bookID.uuidString), "text": .string("فكرة من هذه الفقرة"), "locator": .string(paragraph), "page": .number(453)]), issuedAt: now), now: now)
        #expect(result.status == .applied); #expect(result.undoToken != nil)
        let note = try #require(ModelContext(container).fetch(FetchDescriptor<NotebookNote>()).first)
        #expect(note.link == "page"); #expect(note.targetID == bookID); #expect(note.page == 453)
        #expect(note.isPrivate == false); #expect(note.locatorJSON == Data(paragraph.utf8)); #expect(note.text == "فكرة من هذه الفقرة")
    }

    @Test func invalidColoursLocatorsAndPaperBooksAreRefused() async throws {
        #expect(BookCommand.parse("highlight.save", ["id": .string(UUID().uuidString), "bookID": .string(UUID().uuidString), "locator": .string(paragraph), "color": .string("blue")]) == nil)
        #expect(BookCommand.parse("highlight.save", ["id": .string(UUID().uuidString), "bookID": .string(UUID().uuidString), "locator": .string("{\"href\":\"/etc/passwd\",\"type\":\"x\"}"), "color": .string("yellow")]) == nil)
        #expect(BookCommand.parse("notebook.savePage", ["id": .string(UUID().uuidString), "bookID": .string(UUID().uuidString), "locator": .string(paragraph), "text": .string("  ")]) == nil)
        let (bus, container, bookID, root) = try setUp(kind: "paper"); defer { try? FileManager.default.removeItem(at: root) }
        let result = try await bus.execute(.init(name: "highlight.save", payload: .object(["id": .string(UUID().uuidString), "bookID": .string(bookID.uuidString), "locator": .string(paragraph), "color": .string("rose")]), issuedAt: now), now: now)
        #expect(result.status != .applied)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Highlight>()) == 0)
    }
}
