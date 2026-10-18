import Foundation
import Testing
import MadarCore

struct PaperBookIndexTests {
    @Test func isbn13AcceptsArabicDigitsAndChecksTheChecksum() {
        #expect(PaperBookIndex.normalizedISBN13("٩٧٨-٠٣٠٦٤٠٦١٥٧") == "9780306406157")
        #expect(PaperBookIndex.normalizedISBN13("9780306406158") == nil)
        #expect(PaperBookIndex.normalizedISBN13("9770306406157") == nil)
        #expect(PaperBookIndex.normalizedISBN13("9780-306406157x") == nil)
    }

    @Test func indexKeepsUnknownAndEstimatedPagesDistinct() throws {
        let chapters = [
            PaperBookChapter(title: "المدخل", page: 1, pageSource: .entered),
            PaperBookChapter(title: "المتن", page: 18, pageSource: .estimated),
            PaperBookChapter(title: "الخاتمة")
        ]
        let bytes = try #require(PaperBookIndex.encode(chapters, pages: 120))
        #expect(PaperBookIndex.decode(bytes, pages: 120) == chapters)
        #expect(PaperBookIndex.isValid(chapters, pages: 120))
        #expect(!PaperBookIndex.isValid([chapters[1], chapters[0]], pages: 120))
        #expect(!PaperBookIndex.isValid([PaperBookChapter(title: "خارج الطبعة", page: 121, pageSource: .entered)], pages: 120))
        #expect(!PaperBookIndex.isValid([PaperBookChapter(title: "بلا مصدر", page: 4)], pages: 120))
    }

    @Test func ocrKeepsOnlyTrailingPageCandidatesAndMarksThemEstimated() {
        let chapters = PaperBookIndex.chapters(fromOCRLines: [
            "البداية ........ ١",
            "متن الكتاب …… ٢٤",
            "سطر بلا صفحة",
            "خارج الطبعة ١٢١"
        ], totalPages: 120)
        #expect(chapters.map(\.title) == ["البداية", "متن الكتاب"])
        #expect(chapters.map(\.page) == [1, 24])
        #expect(chapters.allSatisfy { $0.pageSource == .estimated })
    }

    @Test func paperSaveCommandAcceptsOnlyValidatedIndexAndISBN() throws {
        let id = UUID()
        let chapters = [PaperBookChapter(title: "المدخل", page: 1, pageSource: .entered)]
        let toc = try #require(PaperBookIndex.encode(chapters, pages: 120))
        let tocText = try #require(String(data: toc, encoding: .utf8))
        let payload: [String: JSONValue] = [
            "id": .string(id.uuidString), "title": .string("كتاب من مكتبتي"), "author": .string(""),
            "pages": .number(120), "shelf": .string("want"), "isbn13": .string("٩٧٨٠٣٠٦٤٠٦١٥٧"), "tocJSON": .string(tocText)
        ]
        #expect(BookCommand.parse("book.savePaper", payload) == .savePaper(id: id, title: "كتاب من مكتبتي", author: "", pages: 120, shelf: "want", replacing: nil, isbn13: "9780306406157", tocJSON: toc))
        var invalid = payload
        invalid["isbn13"] = .string("9780306406158")
        #expect(BookCommand.parse("book.savePaper", invalid) == nil)
        invalid = payload
        invalid["tocJSON"] = .string("[{\"title\":\"خارج الطبعة\",\"page\":121,\"pageSource\":\"entered\"}]")
        #expect(BookCommand.parse("book.savePaper", invalid) == nil)
        invalid = payload
        invalid["isbn13"] = .bool(true)
        #expect(BookCommand.parse("book.savePaper", invalid) == nil)
    }
}
