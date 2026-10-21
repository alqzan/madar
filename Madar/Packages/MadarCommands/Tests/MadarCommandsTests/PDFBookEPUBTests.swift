import Foundation
import Testing
import CoreGraphics
import CoreText
import PDFKit
@testable import MadarCommands

/// Owner, 21 October 2026: any PDF becomes a flowing book on the device. Expected values are typed here
/// from the fixture text, never taken from the converter's output.
struct PDFBookEPUBTests {
    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func printedLinesJoinIntoParagraphsAtPunctuationShortLinesAndBlanks() {
        let page = """
        الحمد لله الذي جعل القراءة بابًا من أبواب المعرفة الواسعة
        وجعل الكتاب صاحبًا لا يمل ولا يخون صاحبه في سفر
        ولا حضر.
        فصل في آداب القراءة

        أول الآداب أن يقرأ المرء بقلب حاضر ونية صادقة وهمة عالية
        ثم يقيد ما يفهمه
        """
        #expect(PDFBookEPUB.paragraphs(page) == [
            "الحمد لله الذي جعل القراءة بابًا من أبواب المعرفة الواسعة وجعل الكتاب صاحبًا لا يمل ولا يخون صاحبه في سفر ولا حضر.",
            "فصل في آداب القراءة",
            "أول الآداب أن يقرأ المرء بقلب حاضر ونية صادقة وهمة عالية ثم يقيد ما يفهمه"
        ])
        #expect(PDFBookEPUB.paragraphs("  \n\n ").isEmpty)
    }

    @Test func pagesBecomeADeterministicRightToLeftEPUBWithBookmarksAndHonestGaps() throws {
        let pages = [
            PDFBookEPUB.Page(text: "مقدمة الكتاب.\nنص <الصفحة> الأولى & ما بعدها.", optical: false, unreliable: false),
            PDFBookEPUB.Page(text: "قراءة ضوئية للصفحة الثانية.", optical: true, unreliable: false, label: "12"),
            PDFBookEPUB.Page(text: "كلمةxكلمة", optical: false, unreliable: true)
        ]
        let outline = [PDFBookOutlineItem(title: "المقدمة", page: 1), PDFBookOutlineItem(title: "الفصل الأول", page: 3)]
        let epub = try PDFBookEPUB.build(title: "آداب القراءة", author: "مؤلف", language: "ar", sourceHash: String(repeating: "a", count: 64), pages: pages, outline: outline)
        #expect(try PDFBookEPUB.build(title: "آداب القراءة", author: "مؤلف", language: "ar", sourceHash: String(repeating: "a", count: 64), pages: pages, outline: outline) == epub)
        #expect(PDFBookEPUB.summary(pages) == .init(pages: 3, opticalPages: 1, skippedPages: [3]))

        let body = text(epub)
        #expect(body.contains("<p>مقدمة الكتاب.</p><p>نص &lt;الصفحة&gt; الأولى &amp; ما بعدها.</p>"))
        #expect(body.contains("title=\"١٢\""))
        #expect(body.contains("صفحة ٣: لم يُستخرج نصها بدقة؛ راجعها في ملف PDF الأصلي."))
        #expect(!body.contains("كلمةxكلمة"))
        #expect(body.contains("صفحات قُرئت من صورها: ١ من ٣."))
        #expect(body.contains("urn:madar:pdf:" + String(repeating: "a", count: 64)))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PDFBookEPUB-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("book.epub"); try epub.write(to: file)
        let inspection = try EPUBBookFiles.stage(source: file, root: root.appendingPathComponent("staging"))
        #expect(inspection.title == "آداب القراءة"); #expect(inspection.author == "مؤلف")
        #expect(inspection.direction == "rtl"); #expect(inspection.hasPageList)
        #expect(inspection.outline.map(\.title) == ["عن هذه النسخة", "المقدمة", "الفصل الأول"])
        #expect(inspection.outline[2].href.hasSuffix("c1.xhtml#p-3"))
    }

    @Test func withoutBookmarksTheIndexListsEveryTenthPage() throws {
        let pages = (1...25).map { PDFBookEPUB.Page(text: "صفحة رقم \($0).", optical: false, unreliable: false) }
        let body = text(try PDFBookEPUB.build(title: "ت", author: "", language: "ar", sourceHash: "h", pages: pages, outline: []))
        #expect(body.contains(">صفحة ١</a>")); #expect(body.contains(">صفحة ١١</a>")); #expect(body.contains(">صفحة ٢١</a>"))
        #expect(!body.contains(">صفحة ٢</a>"))
    }

    @Test func bookmarksReadWithOneBasedPages() throws {
        let bytes = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &rect, nil))
        for _ in 0..<3 { pdf.beginPDFPage(nil); pdf.fill(CGRect(x: 10, y: 10, width: 20, height: 20)); pdf.endPDFPage() }
        pdf.closePDF()
        let document = try #require(PDFDocument(data: bytes as Data))
        let root = PDFOutline()
        for (title, index) in [("أول", 0), ("ثالث", 2)] {
            let item = PDFOutline(); item.label = title
            item.destination = PDFDestination(page: try #require(document.page(at: index)), at: CGPoint(x: 0, y: 400))
            root.insertChild(item, at: root.numberOfChildren)
        }
        document.outlineRoot = root
        // PDFKit keeps an in-memory outline; the shared definition reads it with one-based pages.
        #expect(PDFBookFiles.outline(of: document) == [.init(title: "أول", page: 1), .init(title: "ثالث", page: 3)])
    }
}
