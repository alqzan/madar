import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct BookMutationTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
    @Test func shelfReplacementAndUndoPreserveEveryBook() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        c.autosaveEnabled = false
        let ids = (0..<4).map { _ in UUID() }
        for i in 0..<4 { _ = try BookMutationHandler.stage(.savePaper(id: ids[i], title: "كتاب \(i)", author: "مؤلف", pages: 250, shelf: i < 3 ? "reading" : "want", replacing: nil, isbn13: nil, tocJSON: nil), context: c, now: now, writer: "fixture") }; try c.save()
        #expect(throws: (any Error).self) { _ = try BookMutationHandler.stage(.shelf(id: ids[3], shelf: "reading", replacing: nil), context: c, now: now, writer: "fixture") }
        let undo = try BookMutationHandler.stage(.shelf(id: ids[3], shelf: "reading", replacing: ids[1]), context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        let after = try c.fetch(FetchDescriptor<Book>())
        #expect(after.filter { $0.shelf == "reading" }.count == 3)
        #expect(after.first { $0.id == ids[1] }?.shelf == "want")
        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(2), writer: "fixture"); try c.save()
        #expect(try c.fetchCount(FetchDescriptor<Book>()) == 4)
        #expect(after.first { $0.id == ids[1] }?.shelf == "reading")
        #expect(after.first { $0.id == ids[3] }?.shelf == "want")
    }
    @Test func renameAFileBookAndUndoIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID(), paper = UUID()
        let file = Book(); file.id = id; file.kind = "file"; file.format = "epub"; file.title = "زاد المعاد في هدي خير العباد - ط الرسالة"; file.author = "ابن القيم"
        file.shelf = "want"; file.createdAt = now; file.updatedAt = now; c.insert(file)
        _ = try BookMutationHandler.stage(.savePaper(id: paper, title: "كتاب", author: "", pages: 250, shelf: "want", replacing: nil, isbn13: nil, tocJSON: nil), context: c, now: now, writer: "fixture"); try c.save()
        #expect(BookCommand.parse("book.rename", ["id": .string(id.uuidString), "title": .string("  "), "author": .string("")]) == nil)
        let command = try #require(BookCommand.parse("book.rename", ["id": .string(id.uuidString), "title": .string(" زاد المعاد "), "author": .string("ابن قيم الجوزية")]))
        let undo = try BookMutationHandler.stage(command, context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        #expect(file.title == "زاد المعاد"); #expect(file.author == "ابن قيم الجوزية")
        #expect(throws: (any Error).self) { _ = try BookMutationHandler.stage(.rename(id: paper, title: "آخر", author: ""), context: c, now: now, writer: "fixture") }
        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(2), writer: "fixture"); try c.save()
        let restored = try c.fetch(FetchDescriptor<Book>()).first { $0.id == id }
        #expect(restored?.title == "زاد المعاد في هدي خير العباد - ط الرسالة"); #expect(restored?.author == "ابن القيم")
    }
    @Test func lastPageNeverFinishesWithoutTheExplicitChoice() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID()
        _ = try BookMutationHandler.stage(.savePaper(id: id, title: "كتاب", author: "", pages: 250, shelf: "reading", replacing: nil, isbn13: nil, tocJSON: nil), context: c, now: now, writer: "fixture"); try c.save()
        _ = try BookMutationHandler.stage(.position(id: id, page: 250, finished: false), context: c, now: now, writer: "fixture"); try c.save()
        let b = try #require(c.fetch(FetchDescriptor<Book>()).first)
        #expect(try JSONDecoder().decode(PaperBookPosition.self, from: #require(b.locatorJSON)).page == 250); #expect(b.currentPage == 250); #expect(b.shelf == "reading"); #expect(b.finishedAt == nil); #expect(b.readCount == 0)
        let undo = try BookMutationHandler.stage(.position(id: id, page: 250, finished: true), context: c, now: now, writer: "fixture"); try c.save()
        #expect(b.readCount == 1); #expect(b.finishedAt == now)
        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        #expect(b.finishedAt == nil); #expect(b.readCount == 0); #expect(b.currentPage == 250)
    }

    @Test func paperIndexAndISBNShareTheUndoableBookMutation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID()
        let chapters = [PaperBookChapter(title: "المدخل", page: 1, pageSource: .entered), PaperBookChapter(title: "الرحلة", page: 24, pageSource: .estimated)]
        let toc = try #require(PaperBookIndex.encode(chapters, pages: 120))
        let saved = try BookMutationHandler.stage(.savePaper(id: id, title: "كتاب من مكتبتي", author: "مؤلف", pages: 120, shelf: "want", replacing: nil, isbn13: "9780306406157", tocJSON: toc), context: c, now: now, writer: "fixture")
        try c.save()
        let book = try #require(c.fetch(FetchDescriptor<Book>()).first)
        #expect(book.isbn13 == "9780306406157")
        #expect(try PaperBookIndex.decode(#require(book.tocJSON), pages: book.pages) == chapters)
        try BookMutationHandler.undo(saved, context: c, now: now.addingTimeInterval(1), writer: "fixture")
        try c.save()
        #expect(book.deletedAt != nil)
    }
    @Test func updatingPaperDetailsIsUndoableAndPreservesShelfAndPosition() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID()
        let originalChapters = [PaperBookChapter(title: "المدخل", page: 1, pageSource: .entered)]
        let originalTOC = try #require(PaperBookIndex.encode(originalChapters, pages: 120))
        _ = try BookMutationHandler.stage(.savePaper(id: id, title: "كتاب ورقي", author: "مؤلف", pages: 120, shelf: "want", replacing: nil, isbn13: "9780306406157", tocJSON: originalTOC), context: c, now: now, writer: "fixture")
        try c.save()
        let book = try #require(c.fetch(FetchDescriptor<Book>()).first)
        book.currentPage = 24
        try c.save()

        let updatedChapters = [PaperBookChapter(title: "بداية الطريق", page: 1, pageSource: .entered), PaperBookChapter(title: "فصل ثانٍ", page: 32, pageSource: .estimated)]
        let updatedTOC = try #require(PaperBookIndex.encode(updatedChapters, pages: 140))
        let parsed = BookCommand.parse("book.updatePaper", [
            "id": .string(id.uuidString), "title": .string("كتاب ورقي"), "author": .string("مؤلف"),
            "pages": .number(140), "position": .number(26), "isbn13": .null, "tocJSON": .string(String(decoding: updatedTOC, as: UTF8.self))
        ])
        #expect(parsed == .updatePaper(id: id, title: "كتاب ورقي", author: "مؤلف", pages: 140, position: 26, isbn13: nil, tocJSON: updatedTOC))
        #expect(throws: (any Error).self) {
            _ = try BookMutationHandler.stage(.updatePaper(id: id, title: "كتاب ورقي", author: "مؤلف", pages: 20, position: 24, isbn13: nil, tocJSON: updatedTOC), context: c, now: now.addingTimeInterval(1), writer: "fixture")
        }

        let undo = try BookMutationHandler.stage(.updatePaper(id: id, title: "كتاب منقح", author: "مؤلف ثانٍ", pages: 140, position: 26, isbn13: nil, tocJSON: updatedTOC), context: c, now: now.addingTimeInterval(2), writer: "fixture")
        try c.save()
        #expect(book.title == "كتاب منقح"); #expect(book.author == "مؤلف ثانٍ"); #expect(book.pages == 140)
        #expect(book.isbn13 == nil); #expect(book.shelf == "want"); #expect(book.currentPage == 26)
        #expect(try JSONDecoder().decode(PaperBookPosition.self, from: #require(book.locatorJSON)).page == 26)
        #expect(PaperBookIndex.decode(try #require(book.tocJSON), pages: book.pages) == updatedChapters)

        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(3), writer: "fixture")
        try c.save()
        #expect(book.title == "كتاب ورقي"); #expect(book.author == "مؤلف"); #expect(book.pages == 120)
        #expect(book.isbn13 == "9780306406157"); #expect(book.shelf == "want"); #expect(book.currentPage == 24)
        #expect(PaperBookIndex.decode(try #require(book.tocJSON), pages: book.pages) == originalChapters)
    }
    @Test func hadithReturnAndUnderstandingUseTheSameIdentityAndUndo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        let day = try DiaryLineRenderer.today(context: c, now: now)
        _ = try BookMutationHandler.stage(.hadith(number: 13, edition: "wikisource-ar-500107", understood: false, day: day), context: c, now: now, writer: "fixture"); try c.save()
        let undo = try BookMutationHandler.stage(.hadith(number: 13, edition: "wikisource-ar-500107", understood: true, day: day), context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        let rows = try c.fetch(FetchDescriptor<HadithProgress>()), h = try #require(rows.first)
        #expect(rows.count == 1); #expect(h.number == 13); #expect(h.understood); #expect(!h.returnTo); #expect(h.readAt == now)
        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(2), writer: "fixture"); try c.save()
        #expect(h.returnTo); #expect(!h.understood); #expect(h.understoodDayKey == nil)
        #expect(throws: (any Error).self) { _ = try BookMutationHandler.stage(.hadith(number: 14, edition: "wikisource-ar-500107", understood: true, day: day.adding(days: -1)), context: c, now: now, writer: "fixture") }
    }
    @Test func explicitHadithActionRestoresItsUndoneStableIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container)
        let day = try DiaryLineRenderer.today(context: c, now: now)
        let inserted = try BookMutationHandler.stage(.hadith(number: 13, edition: "wikisource-ar-500107", understood: false, day: day), context: c, now: now, writer: "fixture"); try c.save()
        try BookMutationHandler.undo(inserted, context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        let row = try #require(c.fetch(FetchDescriptor<HadithProgress>()).first)
        let barrier = try #require(row.deletionBarrierAt)
        #expect(row.deletedAt != nil)

        _ = try BookMutationHandler.stage(.hadith(number: 13, edition: "wikisource-ar-500107", understood: true, day: day), context: c, now: now.addingTimeInterval(2), writer: "fixture"); try c.save()
        #expect(row.deletedAt == nil)
        #expect(try #require(row.restoredAt) > barrier)
        #expect(row.understood)
        #expect(!row.returnTo)
        #expect(row.understoodDayKey == day.description)
    }
    @Test func privateNotebookNotesSaveEditDeleteAndUndoAsTombstones() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Mihbara-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID(), firstID = UUID()
        let created = try BookMutationHandler.stage(.savePrivateNote(id: firstID, text: "ملاحظة مؤقتة"), context: c, now: now, writer: "fixture"); try c.save()
        let first = try #require(c.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == firstID })
        try BookMutationHandler.undo(created, context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        #expect(first.deletedAt != nil)

        _ = try BookMutationHandler.stage(.savePrivateNote(id: id, text: "فكرة خاصة"), context: c, now: now.addingTimeInterval(2), writer: "fixture"); try c.save()
        let note = try #require(c.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == id })
        #expect(note.isPrivate); #expect(note.link == "general"); #expect(note.text == "فكرة خاصة")
        let edited = try BookMutationHandler.stage(.savePrivateNote(id: id, text: "فكرة محدثة"), context: c, now: now.addingTimeInterval(3), writer: "fixture"); try c.save()
        #expect(note.text == "فكرة محدثة")
        try BookMutationHandler.undo(edited, context: c, now: now.addingTimeInterval(4), writer: "fixture"); try c.save()
        #expect(note.text == "فكرة خاصة")
        let deleted = try BookMutationHandler.stage(.deletePrivateNote(id: id), context: c, now: now.addingTimeInterval(5), writer: "fixture"); try c.save()
        #expect(note.deletedAt != nil)
        try BookMutationHandler.undo(deleted, context: c, now: now.addingTimeInterval(6), writer: "fixture"); try c.save()
        #expect(note.deletedAt == nil); #expect(note.text == "فكرة خاصة")
        #expect(BookCommand.parse("notebook.savePrivate", ["id": .string(id.uuidString), "text": .string("فكرة")]) == .savePrivateNote(id: id, text: "فكرة"))
        #expect(BookCommand.parse("notebook.deletePrivate", ["id": .string(id.uuidString)]) == .deletePrivateNote(id: id))
        #expect(BookCommand.parse("notebook.savePrivate", ["id": .string(id.uuidString), "text": .string("فكرة"), "isPrivate": .bool(false)]) == nil)
    }

    @Test func goodreadsBookNoteEditDeleteAndUndoKeepItsBookLink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraGoodreadsNote-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let bookID = UUID(), noteID = UUID()
        let book = Book(); book.id = bookID; book.title = "رحلة Goodreads"; book.kind = "paper"
        context.insert(book)
        let note = NotebookNote(); note.id = noteID; note.isPrivate = true; note.link = "general"; note.targetID = bookID; note.text = "ملاحظة أصلية"
        context.insert(note); try context.save()

        let edited = try BookMutationHandler.stage(.savePrivateNote(id: noteID, text: "ملاحظة معدلة"), context: context,
                                                   now: now.addingTimeInterval(1), writer: "fixture")
        try context.save()
        #expect(note.text == "ملاحظة معدلة" && note.isPrivate)
        #expect(note.link == "general" && note.targetID == bookID)
        try BookMutationHandler.undo(edited, context: context, now: now.addingTimeInterval(2), writer: "fixture")
        try context.save()
        #expect(note.text == "ملاحظة أصلية" && note.link == "general" && note.targetID == bookID)

        let deleted = try BookMutationHandler.stage(.deletePrivateNote(id: noteID), context: context,
                                                    now: now.addingTimeInterval(3), writer: "fixture")
        try context.save()
        #expect(note.deletedAt != nil)
        try BookMutationHandler.undo(deleted, context: context, now: now.addingTimeInterval(4), writer: "fixture")
        try context.save()
        #expect(note.deletedAt == nil && note.text == "ملاحظة أصلية" && note.isPrivate)
        #expect(note.link == "general" && note.targetID == bookID)
    }

    @Test func savedWordsUpsertByNaturalKeyAndUndoWithoutLosingMeaning() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraWords-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let bookID = UUID(), firstID = UUID(), secondID = UUID(), book = Book()
        book.id = bookID; book.title = "English book"; book.kind = "file"; book.format = "epub"
        context.insert(book); try context.save()
        let locator = "{\"href\":\"OEBPS/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"progression\":0.25}}"
        func payload(id: UUID, word: String, context text: String) -> [String: MadarCore.JSONValue] {
            ["id": .string(id.uuidString), "word": .string(word), "language": .string("en"),
             "bookID": .string(bookID.uuidString), "bookTitle": .string("English book"),
             "locator": .string(locator), "context": .string(text)]
        }
        let firstPayload = payload(id: firstID, word: "Book", context: "A book opens a window.")
        let first = try #require(BookCommand.parse("word.save", firstPayload))
        #expect(first == .saveUserWord(id: firstID, word: "Book", language: "en", bookID: bookID,
                                       bookTitle: "English book", locatorJSON: Data(locator.utf8), context: "A book opens a window."))
        let createdUndo = try BookMutationHandler.stage(first, context: context, now: now, writer: "fixture")
        try context.save()
        let saved = try #require(context.fetch(FetchDescriptor<UserWord>()).first)
        #expect(saved.word == "Book"); #expect(saved.language == "en"); #expect(saved.meaning == nil)
        #expect(saved.bookID == bookID); #expect(saved.bookTitle == "English book"); #expect(saved.context == "A book opens a window.")

        let secondPayload = payload(id: secondID, word: "book", context: "I closed the book.")
        let update = try #require(BookCommand.parse("word.save", secondPayload))
        try BookMutationHandler.undo(createdUndo, context: context, now: now.addingTimeInterval(1), writer: "fixture")
        try context.save()
        #expect(saved.deletedAt != nil); #expect(saved.deletionBarrierAt != nil)
        _ = try BookMutationHandler.stage(update, context: context, now: now.addingTimeInterval(2), writer: "fixture")
        try context.save()
        #expect(saved.id == firstID); #expect(saved.deletedAt == nil); #expect(saved.restoredAt != nil)
        #expect(saved.word == "book"); #expect(saved.context == "I closed the book.")

        saved.meaning = "مجلد للقراءة"; saved.meaningSource = "user"; try context.save()
        let updated = try #require(BookCommand.parse("word.save", firstPayload))
        let updateUndo = try BookMutationHandler.stage(updated, context: context, now: now.addingTimeInterval(3), writer: "fixture")
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<UserWord>()) == 1)
        #expect(saved.id == firstID); #expect(saved.word == "Book"); #expect(saved.context == "A book opens a window.")
        #expect(saved.meaning == "مجلد للقراءة"); #expect(saved.meaningSource == "user")

        try BookMutationHandler.undo(updateUndo, context: context, now: now.addingTimeInterval(4), writer: "fixture")
        try context.save()
        #expect(saved.word == "book"); #expect(saved.context == "I closed the book.")
        #expect(saved.meaning == "مجلد للقراءة"); #expect(saved.meaningSource == "user")

        var phrase = secondPayload; phrase["word"] = .string("two words")
        #expect(BookCommand.parse("word.save", phrase) == nil)
        var unsafeLocator = secondPayload; unsafeLocator["locator"] = .string("{\"href\":\"https://example.com/book\",\"type\":\"application/xhtml+xml\"}")
        #expect(BookCommand.parse("word.save", unsafeLocator) == nil)
    }

    @Test func diaryReadingLinesComeFromSavedSessionsAndRespectHide() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"MihbaraDiary-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),context=ModelContext(container),day=try GregorianDay("2026-10-17")
        let book=Book();book.id=UUID();book.title="كتاب الاختبار";book.deletedAt=now
        let session=ReadingSession();session.id=UUID();session.bookID=book.id;session.dayKey=day.description;session.start=now.addingTimeInterval(-300);session.end=now;session.activeSeconds=300;session.pagesCounted=12
        let tooShort=ReadingSession();tooShort.bookID=book.id;tooShort.dayKey=day.description;tooShort.start=now.addingTimeInterval(-59);tooShort.end=now;tooShort.activeSeconds=59;tooShort.pagesCounted=4
        context.insert(book);context.insert(session);context.insert(tooShort);try context.save()

        var lines=try DiaryLineRenderer.live(day:day,context:context).filter{$0.kind=="mihbara"}
        #expect(lines.map(\.text)==["قرأت ١٢ صفحة من كتاب الاختبار"])
        #expect(lines.first?.id=="mihbara."+session.id.uuidString)

        let hidden=HiddenAutoLine();hidden.eventKind="mihbara";hidden.eventID=session.id;hidden.dayKey=day.description;context.insert(hidden);try context.save()
        lines=try DiaryLineRenderer.live(day:day,context:context).filter{$0.kind=="mihbara"}
        #expect(lines.isEmpty,"Hiding the diary line does not delete the saved reading session")
        #expect(try context.fetch(FetchDescriptor<ReadingSession>()).count==2)
    }

    @Test func goodreadsImportUpdatesBySourceWithoutDuplicatingAndUndoRestoresImportState() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GoodreadsImport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: "BookStaging")
        let source = root.appending(path: "goodreads.csv")
        let csv = "Book Id,Title,Author,Additional Authors,ISBN,ISBN13,My Rating,Exclusive Shelf,Date Read,Read Count,My Review,Private Notes,Number of Pages,Year Published,Date Added,Bookshelves\r\n"
            + "42,رحلة,أحمد,,,9780306406157,5,read,2023/12/31,2,\"السطر الأول\r\nالسطر الثاني\",ملاحظة خاصة,120,2020,2020/02/01,favorites"
        try Data(csv.utf8).write(to: source)
        let stage = try GoodreadsCSVFiles.stage(source: source, id: UUID(), root: staging)
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        context.autosaveEnabled = false

        func importCommand(_ id: UUID) throws -> BookCommand {
            let payload: [String: MadarCore.JSONValue] = [
                "id": .string(id.uuidString), "fileID": .string(stage.id.uuidString), "sha256": .string(stage.sha256),
                "fileName": .string(stage.fileName), "cutoffYear": .number(2024), "missingDateShelf": .string("old"),
                "selectedMatchesJSON": .string("{}")
            ]
            guard let command = BookCommand.parse("book.importGoodreads", payload) else { throw DataError.invalidValue("Goodreads test command rejected") }
            return command
        }

        let firstBatch = UUID()
        _ = try BookMutationHandler.stage(importCommand(firstBatch), context: context, now: now, writer: "fixture", stagingDirectory: staging)
        try context.save()
        let imported = try #require(context.fetch(FetchDescriptor<Book>()).first { $0.deletedAt == nil })
        let importedNote = try #require(context.fetch(FetchDescriptor<NotebookNote>()).first { $0.deletedAt == nil })
        let importedLink = try #require(context.fetch(FetchDescriptor<ImportLink>()).first { $0.deletedAt == nil })
        #expect(imported.sourceGoodreadsID == "42"); #expect(imported.title == "رحلة"); #expect(imported.author == "أحمد")
        #expect(imported.shelf == "old"); #expect(imported.rating == 5); #expect(imported.readCount == 2)
        #expect(imported.review == "السطر الأول\r\nالسطر الثاني"); #expect(imported.finishedAt != nil)
        #expect(importedNote.isPrivate && importedNote.link == "general" && importedNote.targetID == imported.id)
        #expect(importedNote.text == "ملاحظة خاصة")
        #expect(importedLink.source == "goodreads" && importedLink.sourceID == "42" && importedLink.targetID == imported.id)
        let archived = try JSONDecoder().decode([String: String].self, from: #require(importedLink.unmappedJSON))
        #expect(archived["Year Published"] == "2020" && archived["My Review"] == nil && archived["Private Notes"] == nil)

        let secondBatch = UUID()
        let secondUndo = try BookMutationHandler.stage(importCommand(secondBatch), context: context, now: now.addingTimeInterval(10), writer: "fixture", stagingDirectory: staging)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Book>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count == 1)
        #expect(try context.fetch(FetchDescriptor<NotebookNote>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count == 1)
        #expect(try context.fetch(FetchDescriptor<ImportLink>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count == 1)
        #expect(importedLink.importBatchID == secondBatch)

        try BookMutationHandler.undo(secondUndo, context: context, now: now.addingTimeInterval(11), writer: "fixture")
        try context.save()
        #expect(imported.deletedAt == nil && imported.title == "رحلة")
        #expect(imported.importBatchID == firstBatch)
        #expect(importedLink.deletedAt == nil && importedLink.importBatchID == firstBatch)
        #expect(importedNote.deletedAt == nil && importedNote.text == "ملاحظة خاصة")
        #expect(try context.fetch(FetchDescriptor<ImportBatch>()).first { $0.id == secondBatch }?.deletedAt != nil)

    }

    @Test func goodreadsMatchSuggestionUpdatesOnlyAfterAnExplicitChoice() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GoodreadsMatch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: "BookStaging"), source = root.appending(path: "match.csv")
        let csv = "Book Id,Title,Author,Additional Authors,ISBN,ISBN13,My Rating,Exclusive Shelf,Date Read,Read Count,My Review,Private Notes,Number of Pages,Year Published,Date Added,Bookshelves\n"
            + "314,عنوان Goodreads,مؤلف,,,9780306406157,0,to-read,,0,,,,2020,,"
        try Data(csv.utf8).write(to: source)
        let stage = try GoodreadsCSVFiles.stage(source: source, id: UUID(), root: staging)
        let context = ModelContext(try MadarContainerFactory.makeLocal(at: root))
        context.autosaveEnabled = false
        let manual = Book(); manual.title = "عنوان كتبته يدويًا"; manual.author = "مؤلف"; manual.isbn13 = "9780306406157"; manual.shelf = "want"
        context.insert(manual); try context.save()
        let entry = try #require(GoodreadsCSV.parse(Data(csv.utf8)).first)
        let candidate = GoodreadsBookCandidate(id: manual.id, title: manual.title, author: manual.author, isbn13: manual.isbn13, sourceGoodreadsID: nil, shelf: manual.shelf)
        let suggestion = GoodreadsCSV.preview(entries: [entry], existing: [candidate])
        #expect(suggestion.rows[0].targetBookID == nil)
        #expect(suggestion.rows[0].suggestions.map(\.id) == [manual.id])

        let selected = try JSONEncoder().encode([entry.rowKey: manual.id])
        let batchID = UUID()
        let payload: [String: MadarCore.JSONValue] = [
            "id": .string(batchID.uuidString), "fileID": .string(stage.id.uuidString), "sha256": .string(stage.sha256),
            "fileName": .string(stage.fileName), "cutoffYear": .number(2024), "missingDateShelf": .string("old"),
            "selectedMatchesJSON": .string(String(decoding: selected, as: UTF8.self))
        ]
        let command = try #require(BookCommand.parse("book.importGoodreads", payload))
        _ = try BookMutationHandler.stage(command, context: context, now: now, writer: "fixture", stagingDirectory: staging)
        try context.save()
        let live = try context.fetch(FetchDescriptor<Book>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        #expect(live.count == 1 && live[0].id == manual.id)
        #expect(live[0].title == "عنوان Goodreads" && live[0].sourceGoodreadsID == "314")
    }
}
