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
        for i in 0..<4 { _ = try BookMutationHandler.stage(.savePaper(id: ids[i], title: "كتاب \(i)", author: "مؤلف", pages: 250, shelf: i < 3 ? "reading" : "want", replacing: nil), context: c, now: now, writer: "fixture") }; try c.save()
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
        _ = try BookMutationHandler.stage(.savePaper(id: id, title: "كتاب", author: "", pages: 250, shelf: "reading", replacing: nil), context: c, now: now, writer: "fixture"); try c.save()
        _ = try BookMutationHandler.stage(.position(id: id, page: 250, finished: false), context: c, now: now, writer: "fixture"); try c.save()
        let b = try #require(c.fetch(FetchDescriptor<Book>()).first)
        #expect(try JSONDecoder().decode(PaperBookPosition.self, from: #require(b.locatorJSON)).page == 250); #expect(b.currentPage == 250); #expect(b.shelf == "reading"); #expect(b.finishedAt == nil); #expect(b.readCount == 0)
        let undo = try BookMutationHandler.stage(.position(id: id, page: 250, finished: true), context: c, now: now, writer: "fixture"); try c.save()
        #expect(b.readCount == 1); #expect(b.finishedAt == now)
        try BookMutationHandler.undo(undo, context: c, now: now.addingTimeInterval(1), writer: "fixture"); try c.save()
        #expect(b.finishedAt == nil); #expect(b.readCount == 0); #expect(b.currentPage == 250)
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
}
