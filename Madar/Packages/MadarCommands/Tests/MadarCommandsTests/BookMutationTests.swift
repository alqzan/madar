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
}
