import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// FB-36 (owner, 5 Nov 2026): «ابي طريقه لو اضفت غلاف الكتاب يجيك ويطلع له شكل حلو».
@MainActor struct BookCoverTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00+03:00")!
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x05])

    /// One Media row per book keyed `book-cover:<id>`; a new photo replaces it, empty data tombstones it, and a later
    /// photo brings the same row back. The Book row itself never changes, and no undo chip is offered.
    @Test func coverIsOneMediaRowPerBookReplacedClearedAndRestored() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Cover-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), c = ModelContext(container), id = UUID()
        c.autosaveEnabled = false
        _ = try BookMutationHandler.stage(.savePaper(id: id, title: "رياض الصالحين", author: "النووي", pages: 600, shelf: "want", replacing: nil, isbn13: nil, tocJSON: nil), context: c, now: now, writer: "fixture"); try c.save()
        let bookBefore = try #require(c.fetch(FetchDescriptor<Book>()).first).updatedAt
        func save(_ data: Data, _ t: TimeInterval) throws -> Data {
            let command = try #require(BookCommand.parse("book.saveCover", ["bookID": .string(id.uuidString), "image": .string(data.base64EncodedString())]))
            #expect(!command.isUndoable)
            let token = try BookMutationHandler.stage(command, context: c, now: now.addingTimeInterval(t), writer: "fixture"); try c.save(); return token
        }
        func covers() throws -> [Media] { try c.fetch(FetchDescriptor<Media>()).filter { $0.sourceID == "book-cover:\(id.uuidString)" } }
        #expect(try save(jpeg, 1).isEmpty)
        var rows = try covers()
        #expect(rows.count == 1 && rows[0].kind == "photo" && rows[0].contentType == "image/jpeg" && rows[0].data == jpeg && rows[0].sizeBytes == 6)
        // `printf '\xff\xd8\xff\xe0\x01\x02' | shasum -a 256`
        #expect(rows[0].sha256 == "301719c15771aa2c23c572c8a6dd768a2e875f2bf5654e30f70331698d6a1607")
        _ = try save(png, 2)
        rows = try covers()
        // `printf '\x89PNG\r\n\x1a\n\x05' | shasum -a 256`
        #expect(rows.count == 1 && rows[0].contentType == "image/png" && rows[0].data == png)
        #expect(rows[0].sha256 == "cd2006c7bd198a85c4c94929d3ea3e5d0439b14f4f7e6ada727827b60a2b32ac")
        _ = try save(Data(), 3)
        rows = try covers()
        #expect(rows.count == 1 && rows[0].deletedAt != nil && rows[0].data == nil && rows[0].sizeBytes == 0)
        _ = try save(jpeg, 4)
        rows = try covers()
        #expect(rows.count == 1 && rows[0].deletedAt == nil && rows[0].restoredAt != nil && rows[0].data == jpeg)
        #expect(try c.fetch(FetchDescriptor<Book>()).first?.updatedAt == bookBefore)
    }

    @Test func onlyJPEGOrPNGForAnExistingBookIsAccepted() throws {
        let id = UUID()
        #expect(BookCommand.parse("book.saveCover", ["bookID": .string(id.uuidString), "image": .string(Data("GIF89a".utf8).base64EncodedString())]) == nil)
        #expect(BookCommand.parse("book.saveCover", ["bookID": .string(id.uuidString)]) == nil)
        #expect(BookCommand.parse("book.saveCover", ["bookID": .string("x"), "image": .string(jpeg.base64EncodedString())]) == nil)
        #expect(BookCommand.parse("book.saveCover", ["bookID": .string(id.uuidString), "image": .string("")]) == .saveCover(bookID: id, image: Data()))
        let root = FileManager.default.temporaryDirectory.appending(path: "Cover-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let c = ModelContext(try MadarContainerFactory.makeLocal(at: root))
        #expect(throws: (any Error).self) { _ = try BookMutationHandler.stage(.saveCover(bookID: id, image: jpeg), context: c, now: now, writer: "fixture") }
        // A book in the trash takes no new cover.
        _ = try BookMutationHandler.stage(.savePaper(id: id, title: "كتاب", author: "", pages: 100, shelf: "want", replacing: nil, isbn13: nil, tocJSON: nil), context: c, now: now, writer: "fixture")
        _ = try BookMutationHandler.stage(.deleteBook(id: id), context: c, now: now.addingTimeInterval(1), writer: "fixture")
        #expect(throws: (any Error).self) { _ = try BookMutationHandler.stage(.saveCover(bookID: id, image: jpeg), context: c, now: now.addingTimeInterval(2), writer: "fixture") }
    }

    /// The shelf keeps a contrast-tested binding: each of the twenty leathers maps to itself, and a near colour to it.
    @Test func coverColourPicksTheNearestTestedBinding() {
        for (index, binding) in BookBindings.all.enumerated() { #expect(BookBindings.nearest(to: binding.base) == index) }
        // A white paperback reads as the ivory binding (0xF7F3EA), a deep red photo as the burgundy one (0x8A1F2E).
        #expect(BookBindings.nearest(to: 0xFFFFFF) == 15)
        #expect(BookBindings.nearest(to: 0x8C1E30) == 10)
    }
}
