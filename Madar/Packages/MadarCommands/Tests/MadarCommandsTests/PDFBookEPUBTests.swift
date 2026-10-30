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

    /// Owner, 25 Oct 2026: a scanned book's printed contents page is its index. Hand-worked fixture: every
    /// heading sits one file page after its printed number, and the last page's numbers came as a column.
    @Test func aScannedBookTakesItsIndexFromItsPrintedContentsPage() throws {
        var pages = Array(repeating: "نص عادي في صفحة من الكتاب لا عنوان فيه.", count: 12)
        pages[2] = "المقدمة\nنص المقدمة."
        pages[4] = "البداية\nنص الفصل الأول."
        pages[6] = "الطريق الطويل\nنص الفصل الثاني."
        pages[8] = "٣ - الخاتمة\nنص الخاتمة."
        pages[10] = "الفهرس\nالمقدمة.....٢\n١ - البداية\n٤\n٢ - الطريق الطويل......٦"
        pages[11] = "٣ - الخاتمة\nأولاً: الشكر\nثانياً: الدعاء\n٨\n٨\n٩"
        let expected: [PDFBookEPUB.PrintedEntry] = [
            .init(title: "المقدمة", page: 2), .init(title: "١ - البداية", page: 4), .init(title: "٢ - الطريق الطويل", page: 6),
            .init(title: "٣ - الخاتمة", page: 8), .init(title: "أولاً: الشكر", page: 8), .init(title: "ثانياً: الدعاء", page: 9)
        ]
        #expect(PDFBookEPUB.printedContents(pages) == expected)
        let body = text(try PDFBookEPUB.build(title: "ت", author: "", language: "ar", sourceHash: "h",
            pages: pages.map { PDFBookEPUB.Page(text: $0, optical: true, unreliable: false) }, outline: []))
        #expect(body.contains("<a href=\"c1.xhtml#p-5\">١ - البداية</a>"))
        // The printed contents page itself reads as the parsed contents with links, not its OCR columns.
        #expect(body.contains("<nav class=\"madar-contents\"><h2>الفهرس</h2><ol><li><a href=\"c1.xhtml#p-3\">المقدمة</a></li>"))
        #expect(!body.contains("المقدمة.....٢") && !body.contains("<p>٨</p>"))
        #expect(body.contains("id=\"p-11\"") && body.contains("id=\"p-12\""))
        #expect(!body.contains(">صفحة ١١</a>"))
        // No contents page: the index keeps listing every tenth page.
        #expect(PDFBookEPUB.printedContents(Array(pages.prefix(10))).isEmpty)
    }

    /// The owner's contents page as the phone read it: titles run together on one line, leader dots read as
    /// digits («٢..٠», «٠٤٠٠» — ٤, not ٤٠, in a 60-page book), Latin digits, and one number misread. Expected pages are the heading pages.
    @Test func aContentsPageReadWithMergedTitlesAndGarbledNumbersStillFindsEveryChapter() {
        var pages = Array(repeating: "نص عادي في صفحة من الكتاب لا عنوان فيه.", count: 60)
        pages[1] = "إضاءة\nنص."; pages[3] = "المقدمة\nنص."; pages[5] = "١ - البداية\nنص."
        pages[7] = "٢ - الطريق الطويل\nنص."; pages[9] = "٣ - الثمرة\nنص."
        pages[14] = "الفهرس\nإضاءة\nالمقدمة\n١ - البداية ٢ - الطريق الطويل ٣ - الثمرة\n٤ - الخاتمة\n٢..٠\n٠٤٠٠\n6\n٣\n١٠\n١٢"
        pages[11] = "١٤\nالخا\nنص."   // The heading split over lines: only its printed number places it.
        let expected: [PDFBookEPUB.PrintedEntry] = [
            .init(title: "إضاءة", page: 1), .init(title: "المقدمة", page: 3), .init(title: "١ - البداية", page: 5),
            .init(title: "٢ - الطريق الطويل", page: 7), .init(title: "٣ - الثمرة", page: 9), .init(title: "٤ - الخاتمة", page: 11)
        ]
        let found = PDFBookEPUB.printedContents(pages)
        #expect(found == expected, "\(found.map { "\($0.page) \($0.title)" })")
    }

    /// The owner's scan reads a section break as «* * #», «#» or «*»: each becomes one centred «* * *».
    @Test func sectionBreaksReadAsStrayMarksBecomeOneBreak() throws {
        let pages = ["نص الفقرة الأولى في الصفحة.\n* * #\nنص الفقرة الثانية بعد الفاصل.", "#\nنص في الصفحة التالية."]
            .map { PDFBookEPUB.Page(text: $0, optical: true, unreliable: false) }
        let body = text(try PDFBookEPUB.build(title: "ت", author: "", language: "ar", sourceHash: "h", pages: pages, outline: []))
        #expect(body.components(separatedBy: PDFBookEPUB.sectionBreak).count == 3)
        #expect(!body.contains("* * #") && !body.contains("<p>#</p>"))
        #expect(PDFBookEPUB.isOrnament("* *") && !PDFBookEPUB.isOrnament("٥ * ٣") && !PDFBookEPUB.isOrnament(" "))
    }

    /// A page that opens on a heading, or follows a page ending on a short line, starts a new paragraph.
    @Test func headingsAndShortLastLinesDoNotRunIntoTheNextPage() throws {
        let pages = [
            "سطر طويل أول يملأ عرض الصفحة كله تقريبا هنا\nسطر طويل ثان يملأ عرض الصفحة كله تقريبا هنا\nهاتف ٢٢٢٩",
            "عنوان الكتاب\nسطر طويل يبدأ به النص الجديد في هذه الصفحة هنا\nوسطر طويل آخر يملأ العرض ويستمر إلى التالية",
            "عنوان الفصل\nثم يبدأ نص جديد طويل في الصفحة الثالثة هنا\nويستمر النص في سطر آخر طويل حتى نهايته."
        ].map { PDFBookEPUB.Page(text: $0, optical: true, unreliable: false) }
        let body = text(try PDFBookEPUB.build(title: "ت", author: "", language: "ar", sourceHash: "h", pages: pages, outline: []))
        #expect(body.contains("هاتف ٢٢٢٩</p>"))
        #expect(body.contains("<p>عنوان الكتاب</p>"))
        #expect(body.contains("إلى التالية</p><span id=\"p-3\""))
        #expect(body.contains("<p>عنوان الفصل</p>"))
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
            if index == 0 {   // one sub-bookmark under the first chapter: it must be recorded one level deeper
                let child = PDFOutline(); child.label = "فرع"
                child.destination = PDFDestination(page: try #require(document.page(at: 1)), at: CGPoint(x: 0, y: 400))
                item.insertChild(child, at: 0)
            }
        }
        document.outlineRoot = root
        // PDFKit keeps an in-memory outline; the shared definition reads it with one-based pages and the nesting level.
        #expect(PDFBookFiles.outline(of: document) == [.init(title: "أول", page: 1, depth: 0), .init(title: "فرع", page: 2, depth: 1), .init(title: "ثالث", page: 3, depth: 0)])
    }
    /// Owner, 24 Oct 2026: running headers and bare page numbers leave the text, and a paragraph that crosses a
    /// page break stays one paragraph.
    @Test func runningHeadersAndPageNumbersLeaveAndParagraphsCrossPages() throws {
        let pages = [
            "كتاب الأدب\nأول الكلام في هذا الباب أن\n١",
            "كتاب الأدب\nالقراءة تحتاج إلى صبر.\nفصل آخر تام.\n٢",
            "كتاب الأدب\nثالث الصفحات كاملة.\n- ٣ -",
        ]
        let cleaned = PDFBookEPUB.withoutRunningLines(pages)
        #expect(cleaned[0] == "أول الكلام في هذا الباب أن")
        #expect(cleaned[1] == "القراءة تحتاج إلى صبر.\nفصل آخر تام.")
        #expect(cleaned[2] == "ثالث الصفحات كاملة.")
        let epub = try PDFBookEPUB.build(title: "كتاب", author: "", language: "ar", sourceHash: "x", pages: pages.map { .init(text: $0, optical: false, unreliable: false) }, outline: [])
        let chapter = text(epub) // a stored (uncompressed) ZIP: the chapter text is readable as is
        #expect(chapter.contains("<p>أول الكلام في هذا الباب أن <span id=\"p-2\""), "page 1's open paragraph continues over the marker")
        #expect(chapter.contains("aria-label=\"٢\"></span>القراءة تحتاج إلى صبر.</p>"))
        #expect(!chapter.contains("كتاب الأدب"))
    }

    @Test func repeatedBodySentencesAndStandaloneBodyNumbersArePreserved() {
        let pages = (1...3).map { "الصفحة رقم \($0)\nالقراءة باب إلى المعرفة، والكتاب صاحب لا يمل." }
        #expect(PDFBookEPUB.withoutRunningLines(pages) == Array(repeating: "القراءة باب إلى المعرفة، والكتاب صاحب لا يمل.", count: 3))
        let numbered = "كتاب الأدب\nالكلام الأول\n١٢\nالكلام الأخير.\n١"
        #expect(PDFBookEPUB.withoutRunningLines([numbered, numbered, numbered]).allSatisfy { $0.contains("\n١٢\n") })
        let ambiguous = Array(repeating: "كلام أول\nكلام ثان", count: 3)
        #expect(PDFBookEPUB.withoutRunningLines(ambiguous) == ambiguous)
    }

    /// Owner's scanned book, 25 Oct 2026: page 5 is a calligraphic basmala with no words. It must appear as its
    /// picture, never as «لم يُستخرج نصها بدقة»; a blank page adds nothing; a pictured first page is the cover.
    @Test func wordlessPagesKeepTheirPictureBlankPagesVanishAndThePicturedFirstPageIsTheCover() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let pages = [
            PDFBookEPUB.Page(text: "", optical: true, unreliable: false, image: jpeg),
            PDFBookEPUB.Page(text: "", optical: true, unreliable: false, blank: true),
            PDFBookEPUB.Page(text: "", optical: true, unreliable: false, image: jpeg),
            PDFBookEPUB.Page(text: "إضاءة.", optical: true, unreliable: false),
            PDFBookEPUB.Page(text: "", optical: true, unreliable: false)
        ]
        #expect(PDFBookEPUB.summary(pages) == .init(pages: 5, opticalPages: 5, skippedPages: [5], picturedPages: 2))
        let epub = try PDFBookEPUB.build(title: "مشروع العمر", author: "", language: "ar", sourceHash: String(repeating: "b", count: 64), pages: pages, outline: [])
        let all = text(epub)
        #expect(all.contains("<img src=\"images/p1.jpg\""))
        #expect(all.contains("<img src=\"images/p3.jpg\""))
        #expect(!all.contains("images/p2.jpg"))
        #expect(all.contains("href=\"images/p1.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\""))
        #expect(all.contains("href=\"images/p3.jpg\" media-type=\"image/jpeg\"/>"))
        #expect(!all.contains("صفحة ١: لم يُستخرج") && !all.contains("صفحة ٢: لم يُستخرج") && !all.contains("صفحة ٣: لم يُستخرج"))
        #expect(all.contains("صفحة ٥: لم يُستخرج نصها بدقة"))
        #expect(all.contains("id=\"p-2\""))
    }
}
