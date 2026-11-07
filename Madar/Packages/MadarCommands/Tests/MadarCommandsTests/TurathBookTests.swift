import Foundation
import Testing
@testable import MadarCommands

/// M6-T01: Turath catalogue search and the book-to-EPUB conversion, on hand-written data shaped like
/// `files.turath.io/data-v3.json` and `books-v3/{id}.json` (obfuscated metadata keys, `pages` by name).
struct TurathBookTests {
    private let catalogue = Data("""
    {"cats":{"23":{"id":23,"name":"الرقاق والآداب","books":[12028]},"1":{"id":1,"name":"العقيدة","books":[1]}},
     "authors":{"51":{"id":51,"name":"ابن الجوزي","death":597,"books":[12028]},"513":{"id":513,"name":"مؤلف آخر","death":99999,"books":[1,2]}},
     "books":{"12028":{"id":12028,"name":"صيد الخاطر","author_id":51,"cat_id":23,"size":1480554,"page_count":893},
              "1":{"id":1,"name":"الفواكه العذاب","author_id":513,"cat_id":1,"size":214912,"page_count":90},
              "2":{"id":2,"name":"شرح صيد الخواطر المختصر","author_id":513,"cat_id":1,"size":1000,"page_count":10}},
     "books_changed":[],"date":"2026-02-03","version":1}
    """.utf8)

    private let book = Data("""
    {"ً":{"ٌ":12028,"ٍ":"صيد الخاطر","ّ":"الكتاب: صيد الخاطر\\nالناشر: دار القلم & شركاه","ٖ":1770153735},
     "٘":{"ٙ":["1","2"],"ٚ":[{"title":"مقدمة","level":1,"page":1},{"title":"علو الهمة","level":2,"page":2},{"title":"خاتمة","level":1,"page":3}]},
     "pages":[{"text":"<span data-type=\\"title\\" id=toc-1>مقدمة</span>\\nنص <المقدمة>.","vol":"1","page":1},
              {"text":"٧- فصل:<span data-type=\\"title\\" id=toc-2> علوُّ الهمةِ</span>\\nوالراضي بالدون١ دني.\\n_________\\n١ الدون: الأمر الخسيس.","vol":"1","page":2},
              {"text":"<span data-type=\\"title\\" id=toc-3>خاتمة</span>\\n﴿اقْرَأْ﴾","vol":"2","page":1}]}
    """.utf8)

    @Test func searchFoldsDiacriticsAndLetterVariantsAndRanksTitlesFirst() throws {
        let books = try TurathCatalogue.decode(catalogue)
        #expect(books.count == 3)
        let jawzi = try #require(books.first { $0.id == 12028 })
        #expect(jawzi.author == "ابن الجوزي"); #expect(jawzi.authorDeath == 597); #expect(jawzi.category == "الرقاق والآداب"); #expect(jawzi.categoryID == 23); #expect(jawzi.pageCount == 893)
        #expect(jawzi.shamelaLink.absoluteString == "https://shamela.ws/book/12028")
        #expect(books.first { $0.id == 1 }?.authorDeath == nil)   // 99999 is Turath's "living / unknown"
        #expect(TurathCatalogue.search(books, query: "صَيْدُ الخاطِر").map(\.id) == [12028])
        #expect(TurathCatalogue.search(books, query: "صيد").map(\.id) == [12028, 2])
        #expect(TurathCatalogue.search(books, query: "إبن الجوزى").map(\.id) == [12028])
        #expect(TurathCatalogue.search(books, query: "   ").isEmpty)
    }

    @Test func bookBecomesAValidDeterministicEPUBWithIndexPagesAndNotes() throws {
        let entry = try #require(try TurathCatalogue.decode(catalogue).first { $0.id == 12028 })
        let document = try TurathBookDocument.decode(book, catalogue: entry)
        #expect(document.pages.count == 3); #expect(document.headings.count == 3); #expect(document.stamp == 1770153735)
        #expect(document.info.hasPrefix("الكتاب: صيد الخاطر")); #expect(document.headings[1] == .init(title: "علو الهمة", level: 2, pageIndex: 2))

        let epub = try TurathEPUB.build(document)
        #expect(try TurathEPUB.build(document) == epub)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Turath-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("صيد الخاطر.epub"); try epub.write(to: file)
        let inspection = try EPUBBookFiles.stage(source: file, root: root.appendingPathComponent("staging"))
        // The fixture has three printed pages in two volumes (vol "1" twice, vol "2" once).
        let shape = try #require(try EPUBBookFiles.printedShape(file: file))
        #expect(shape.pages == 3); #expect(shape.volumes == 2)
        #expect(inspection.printedPageCount == shape.pages); #expect(inspection.printedVolumeCount == shape.volumes)
        #expect(inspection.title == "صيد الخاطر"); #expect(inspection.author == "ابن الجوزي"); #expect(inspection.appLanguage == "ar")
        #expect(inspection.direction == "rtl"); #expect(inspection.hasPageList)
        #expect(inspection.outline.map(\.title) == ["بيانات الكتاب", "مقدمة", "علو الهمة", "خاتمة"])
        #expect(inspection.outline.map(\.depth) == [0, 0, 1, 0] || inspection.outline.map(\.depth) == [1, 1, 2, 1])
        #expect(inspection.outline[2].href.hasSuffix("c1.xhtml#toc-2"))
    }

    @Test func pageTextKeepsTitlesNotesAndEscapesMarkup() {
        var ids: [Int: String] = [:]
        let html = TurathEPUB.render("٧- فصل:<span data-type=\"title\" id=toc-9> علو الهمة</span>\nنص <b>غامق</b> & آخر\n_________\n١ الدون: الخسيس.", file: "c2.xhtml", pageAnchor: "p-2", titleIDs: &ids)
        #expect(html == "<h2>٧- فصل:<span id=\"toc-9\" class=\"madar-title\"> علو الهمة</span></h2><p>نص غامق &amp; آخر</p><p><a id=\"p-2-notes-ref\" class=\"madar-page-notes-link\" epub:type=\"noteref\" role=\"doc-noteref\" href=\"#p-2-notes\">حواشي الصفحة</a></p><aside id=\"p-2-notes\" class=\"madar-page-notes\" epub:type=\"footnote\" role=\"doc-footnote\"><p>١ الدون: الخسيس.</p><a role=\"doc-backlink\" href=\"#p-2-notes-ref\">العودة إلى المتن</a></aside>")
        #expect(ids == [9: "c2.xhtml"])
        #expect(TurathEPUB.arabicDigits("2/453") == "٢/٤٥٣")
    }
    @Test func eachPrintedPageHasItsOwnCompleteNoteTarget() {
        var ids: [Int: String] = [:]
        let first = TurathEPUB.render("متن الصفحة الأولى\n_____\n١ الحاشية الأولى.\nسطر مكمل لا يضيع.\n٢ الحاشية الثانية.", file: "c1.xhtml", pageAnchor: "p-1", titleIDs: &ids)
        let second = TurathEPUB.render("متن الصفحة الثانية\n_____\n١ حاشية مختلفة.", file: "c1.xhtml", pageAnchor: "p-2", titleIDs: &ids)
        #expect(first.contains("href=\"#p-1-notes\""))
        #expect(second.contains("href=\"#p-2-notes\""))
        #expect(first.contains("<p>١ الحاشية الأولى.</p><p>سطر مكمل لا يضيع.</p><p>٢ الحاشية الثانية.</p>"))
        #expect(second.contains("<p>١ حاشية مختلفة.</p>"))
        #expect(!first.contains("p-2-notes"))
        let plain = TurathEPUB.render("صفحة بلا حاشية", file: "c1.xhtml", pageAnchor: "p-3", titleIDs: &ids)
        #expect(plain == "<p>صفحة بلا حاشية</p>")
    }

}
