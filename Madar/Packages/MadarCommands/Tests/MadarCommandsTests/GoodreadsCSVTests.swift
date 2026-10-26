import Foundation
import Testing
import MadarCommands

@Suite struct GoodreadsCSVTests {
    private let headers = "Book Id,Title,Author,Additional Authors,ISBN,ISBN13,My Rating,Exclusive Shelf,Date Read,Read Count,My Review,Private Notes,Number of Pages,Year Published,Date Added,Bookshelves"

    @Test func parsesQuotedArabicMultilineReviewAndUnmappedColumns() throws {
        let csv = headers + "\r\n" +
            "42,\"A \"\"Quoted\"\", Book\",\"أحمد\",\"كاتب ثانٍ\",,9780306406157,5,read,,2,\"السطر الأول\r\nالسطر الثاني\",\"ملاحظة خاصة\",120,1980,2022/01/03,favorites"
        let entry = try #require(GoodreadsCSV.parse(Data(csv.utf8)).first)
        #expect(entry.goodreadsID == "42")
        #expect(entry.title == "A \"Quoted\", Book")
        #expect(entry.author == "أحمد، كاتب ثانٍ" || entry.author == "أحمد, كاتب ثانٍ")
        #expect(entry.isbn13 == "9780306406157")
        #expect(entry.rating == 5 && entry.readCount == 2)
        #expect(entry.review == "السطر الأول\r\nالسطر الثاني")
        #expect(entry.privateNote == "ملاحظة خاصة")
        #expect(entry.pages == 120 && entry.dateRead == nil)
        #expect(entry.archivedFields["Year Published"] == "1980")
        #expect(entry.archivedFields["Date Added"] == "2022/01/03")
        #expect(entry.archivedFields["Bookshelves"] == "favorites")
        #expect(entry.archivedFields["My Review"] == nil && entry.archivedFields["Private Notes"] == nil)
        #expect(GoodreadsCSV.normalizeISBN13("=\"9780306406157\"") == "9780306406157")
    }

    @Test func mapsShelvesWithoutInventingDatesAndKeepsTheCutoffStable() throws {
        let csv = headers + "\n" +
            "1,قديم,مؤلف,,,9780306406157,0,read,,3,,,,1980,," + "\n" +
            "2,حديث,مؤلف,,,9780306406157,4,read,2023/12/31,1,,,,2023,," + "\n" +
            "3,قراءة,مؤلف,,,,0,currently-reading,,0,,,,,," + "\n" +
            "4,لاحقًا,مؤلف,,,,0,to-read,,0,,,,,,"
        let entries = try GoodreadsCSV.parse(Data(csv.utf8))
        let preview = GoodreadsCSV.preview(entries: entries, existing: [], cutoffYear: 2024)
        #expect(preview.rows.map(\.targetShelf) == ["old", "old", "reading", "want"])
        #expect(preview.rows[0].entry.dateRead == nil && preview.rows[0].entry.rating == nil)
        #expect(preview.rows[1].entry.dateRead != nil)
        let missingDateFinished = GoodreadsCSV.preview(entries: [entries[0]], existing: [], cutoffYear: 2024, missingDateShelf: "finished")
        #expect(missingDateFinished.rows[0].targetShelf == "finished")
        #expect(missingDateFinished.rows[0].entry.dateRead == nil)
    }

    @Test func threeReadingSlotsAndExplicitOnlySuggestions() throws {
        let csv = headers + "\n" + "17,عنوان,مؤلف,,,,0,currently-reading,,0,,,,,,"
        let entry = try #require(GoodreadsCSV.parse(Data(csv.utf8)).first)
        let active = (0..<3).map { GoodreadsBookCandidate(id: UUID(), title: "موجود \($0)", author: "كاتب", isbn13: nil, sourceGoodreadsID: nil, shelf: "reading") }
        let full = GoodreadsCSV.preview(entries: [entry], existing: active)
        #expect(full.rows[0].targetShelf == "want")

        let isbnCandidate = GoodreadsBookCandidate(id: UUID(), title: "كتاب مختلف", author: "كاتب", isbn13: "9780306406157", sourceGoodreadsID: nil, shelf: "want")
        let withISBN = try #require(GoodreadsCSV.parse(Data((headers + "\n" + "18,عنوان,مؤلف,,,9780306406157,0,to-read,,0,,,,,,").utf8)).first)
        let suggestions = GoodreadsCSV.preview(entries: [withISBN], existing: [isbnCandidate])
        #expect(suggestions.rows[0].targetBookID == nil)
        #expect(suggestions.rows[0].suggestions.map(\.id) == [isbnCandidate.id])
        let explicit = GoodreadsCSV.preview(entries: [withISBN], existing: [isbnCandidate], selectedMatches: [withISBN.rowKey: isbnCandidate.id])
        #expect(explicit.rows[0].targetBookID == isbnCandidate.id)
    }

    @Test func reimportIdentityAndISBNWrappersAreStable() throws {
        let csv = headers + "\n" + "7,عنوان,مؤلف, إضافي,\"=\"\"0306406152\"\"\",,0,to-read,,0,,,,,,"
        let entry = try #require(GoodreadsCSV.parse(Data(csv.utf8)).first)
        #expect(entry.isbn13 == "9780306406157")
        let same = try #require(GoodreadsCSV.parse(Data(csv.utf8)).first)
        #expect(entry.rowKey == same.rowKey && entry.deterministicBookID == same.deterministicBookID)
        let match = GoodreadsBookCandidate(id: entry.deterministicBookID, title: entry.title, author: entry.author, isbn13: entry.isbn13, sourceGoodreadsID: nil, shelf: "want")
        #expect(GoodreadsCSV.preview(entries: [entry], existing: [match]).rows[0].targetBookID == match.id)
    }

    @Test func idlessRowsKeepDistinctStableIdentityAndRejectExactDuplicates() throws {
        let firstRow = ",عنوان أول,مؤلف,,,9780306406157,0,to-read,,0,,,,,,"
        let secondRow = ",عنوان ثانٍ,مؤلف,,,9780306406157,0,to-read,,0,,,,,,"
        let entries = try GoodreadsCSV.parse(Data((headers + "\n" + firstRow + "\n" + secondRow).utf8))
        #expect(entries[0].rowKey != entries[1].rowKey)
        #expect(entries[0].deterministicBookID != entries[1].deterministicBookID)
        let duplicate = headers + "\n" + firstRow + "\n" + firstRow
        #expect(throws: GoodreadsCSVError.duplicateIdentity(row: 3)) { try GoodreadsCSV.parse(Data(duplicate.utf8)) }
    }

    @Test func rejectsMalformedCSVUnsupportedShelvesAndRepeatedSourceIDs() {
        #expect(throws: GoodreadsCSVError.malformed) { try GoodreadsCSV.parse(Data((headers + "\n1,\"كتاب,مؤلف,,,,,0,read,,0,,,,,,").utf8)) }
        #expect(throws: GoodreadsCSVError.invalidShelf(row: 2, value: "abandoned")) {
            try GoodreadsCSV.parse(Data((headers + "\n1,كتاب,مؤلف,,,,0,abandoned,,0,,,,,,").utf8))
        }
        let duplicate = headers + "\n1,كتاب,مؤلف,,,,0,read,,0,,,,,,\n1,كتاب آخر,مؤلف,,,,0,to-read,,0,,,,,,"
        #expect(throws: GoodreadsCSVError.duplicateBookID("1")) { try GoodreadsCSV.parse(Data(duplicate.utf8)) }
    }
}
