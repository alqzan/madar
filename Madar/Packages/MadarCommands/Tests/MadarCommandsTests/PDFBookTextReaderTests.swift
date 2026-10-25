import Foundation
import Testing
import CoreGraphics
import CoreText
import PDFKit
@testable import MadarCommands

struct PDFBookTextReaderTests {
    /// An image-only second page: OCR expectations come from this typed fixture,
    /// never from the recognizer's output. The first page has an original text layer.
    private func sample() throws -> Data {
        let bitmap = try #require(CGContext(data: nil, width: 900, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(gray: 1, alpha: 1); bitmap.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        func write(_ text: String, at point: CGPoint, context: CGContext) {
            context.setFillColor(gray: 0, alpha: 1); context.textPosition = point
            let font = CTFontCreateWithName("Arial" as CFString, 52, nil)
            let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }
        write("القراءة باب المعرفة", at: CGPoint(x: 120, y: 400), context: bitmap)
        write("READING OPENS A DOOR", at: CGPoint(x: 70, y: 200), context: bitmap)
        let image = try #require(bitmap.makeImage()), bytes = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 900, height: 600)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &rect, nil))
        pdf.beginPDFPage(nil)
        write("ORIGINAL TEXT LAYER", at: CGPoint(x: 70, y: 400), context: pdf)
        pdf.endPDFPage(); pdf.beginPDFPage(nil)
        pdf.draw(image, in: rect)
        pdf.endPDFPage(); pdf.closePDF()
        return bytes as Data
    }

    @Test func mixedDocumentPreservesOriginalTextAndRecognizesArabicImageOnDevice() async throws {
        let data = try sample(), original = try #require(PDFDocument(data: data))
        #expect(original.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        let reader = PDFBookTextReader(data: data, language: "ar")
        #expect(try await reader.pageCount() == 2)
        let first = try await reader.page(at: 0), second = try await reader.page(at: 1)
        #expect(first.source == .embedded && first.contains("original text layer"))
        // A text page can also be read from its image (for malformed embedded Arabic).
        let forced = try await reader.page(at: 0, optical: true)
        #expect(forced.source == .optical && forced.contains("ORIGINAL TEXT"), "Recognized fixture: \(forced.text)")
        #expect(second.source == .optical)
        #expect(second.contains("المعرفة"), "Recognized fixture: \(second.text)")
        #expect(second.contains("READING OPENS"), "Recognized fixture: \(second.text)")
        // No hidden text is added to the PDF; the index is an independent value.
        #expect(PDFDocument(data: data)?.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
    }

    @Test func pageCoordinatesAndCorruptInputFailClosed() async throws {
        let reader = PDFBookTextReader(data: try sample(), language: "en")
        await #expect(throws: PDFBookTextReader.Failure.self) { try await reader.page(at: -1) }
        await #expect(throws: PDFBookTextReader.Failure.self) { try await reader.page(at: 2) }
        let broken = PDFBookTextReader(data: Data("not a PDF".utf8), language: "ar")
        await #expect(throws: PDFBookTextReader.Failure.self) { try await broken.pageCount() }
    }

    @Test func embeddedColumnsUseTheirBoundsRatherThanTheirPDFPaintOrder() async throws {
        let bytes = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 500, height: 500)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &rect, nil))
        pdf.beginPDFPage(nil)
        // Deliberately paint the left column first and the right one backwards.
        for (text, point) in [("LEFT FIRST", CGPoint(x: 20, y: 420)), ("RIGHT SECOND", CGPoint(x: 280, y: 390)),
                              ("LEFT SECOND", CGPoint(x: 20, y: 390)), ("RIGHT FIRST", CGPoint(x: 280, y: 420))] {
            pdf.textPosition = point
            let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Arial" as CFString, 16, nil)])
            CTLineDraw(CTLineCreateWithAttributedString(string), pdf)
        }
        pdf.endPDFPage(); pdf.closePDF()
        let rtl = try await PDFBookTextReader(data: bytes as Data, language: "ar").page(at: 0)
        let ltr = try await PDFBookTextReader(data: bytes as Data, language: "en").page(at: 0)
        #expect(rtl.text.split(whereSeparator: \.isWhitespace).joined(separator: " ") == "RIGHT FIRST RIGHT SECOND LEFT FIRST LEFT SECOND")
        #expect(ltr.text.split(whereSeparator: \.isWhitespace).joined(separator: " ") == "LEFT FIRST LEFT SECOND RIGHT FIRST RIGHT SECOND")
    }

    @Test func searchIgnoresArabicMarksAlefFormsAndLineBreaksButRejectsEmptyQuery() {
        let page = PDFBookPageText(index: 0, text: "إِنَّ القِراءةَ\nبابُ المَعرفة", source: .optical)
        #expect(page.contains("ان القراءة باب"))
        #expect(!page.contains("   "))
        #expect(!page.contains("كلمة غير موجودة"))
    }

    @Test func compatibilityFormsSearchNormallyAndBrokenArabicMappingsNeverBecomeExcerpts() {
        let forms = PDFBookPageText(index: 0, text: "ﻧﺺ ﻋﺮﺑﻲ PDF", source: .embedded)
        #expect(forms.contains("نص عربي"))
        #expect(!forms.hasUnreliableArabicMapping)
        #expect(forms.excerpt(matching: "نص عربي") != nil)

        let broken = PDFBookPageText(index: 1, text: "ﻫﺬا ٮ'ﺺ ﻋرٮ3ى 4 ﻣﻮﺣ 3 ﻮد PDF", source: .embedded)
        #expect(broken.contains("PDF"))
        #expect(broken.hasUnreliableArabicMapping)
        #expect(broken.excerpt(matching: "PDF") == nil)
    }

    @Test func cancellationIsObservedBeforeRenderingTheNextPage() async throws {
        let reader = PDFBookTextReader(data: try sample(), language: "ar")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.page(at: 1)
        }
        do { _ = try await task.value; Issue.record("Cancelled OCR unexpectedly returned a page") }
        catch is CancellationError { }
    }

    @Test func excerptKeepsOriginalArabicAroundAMatchBeyondThePageOpening() {
        let page = PDFBookPageText(index: 0,
            text: "واحد اثنان ثلاثة أربعة خمسة ستة سبعة ثمانية تسعة عشرة إِنَّ\nالقِراءةَ بابُ المَعرفة ثم يأتي كلام آخر في نهاية هذه الصفحة الطويلة جدًا للقارئ",
            source: .embedded)
        #expect(page.excerpt(matching: "ان القراءة باب") == "… خمسة ستة سبعة ثمانية تسعة عشرة إِنَّ القِراءةَ بابُ المَعرفة ثم يأتي كلام آخر في نهاية هذه الصفحة …")
        #expect(page.excerpt(matching: "واحد")?.hasPrefix("واحد اثنان") == true)
        #expect(page.excerpt(matching: "للقارئ")?.hasSuffix("للقارئ") == true)
        #expect(page.excerpt(matching: "غير موجودة") == nil)
        #expect(page.excerpt(matching: "  \n ") == nil)
        let marks = PDFBookPageText(index: 1, text: "ـ إِنَّ ـ القِراءةَ\tبابُ المَعرفة", source: .optical)
        #expect(marks.excerpt(matching: "ان القراءة باب") == "إِنَّ القِراءةَ بابُ المَعرفة")
    }

    /// Lines Vision returned for the owner's scanned «مشروع العمر», page 9 (25 Oct 2026). Expected values are
    /// the printed words with only the impossible marks removed; missing letters are not invented.
    @Test func ocrStraySymbolsLeaveArabicLinesWithoutGuessingLetters() {
        #expect(PDFBookTextReader.withoutStraySymbols("حياتك% والذي يعدُّ كتابُ مشروع العمر! #هو الترجمةَ") == "حياتك والذي يعدُّ كتابُ مشروع العمر! هو الترجمةَ")
        #expect(PDFBookTextReader.withoutStraySymbols("وقد بلغتْ منِّي هذه الكلمة ' شروع العمر 'كلَّ مَبْلَغ،") == "وقد بلغتْ منِّي هذه الكلمة ' شروع العمر 'كلَّ مَبْلَغ،")
        #expect(PDFBookTextReader.withoutStraySymbols("وقد بلغتْ منِّي هذه الكلمة مشروع العمر% كلَّ مَبْلَغ ،") == "وقد بلغتْ منِّي هذه الكلمة مشروع العمر كلَّ مَبْلَغ،")
        #expect(PDFBookTextReader.withoutStraySymbols("كتابُ (مشروع العمر )' هو") == "كتابُ (مشروع العمر ) هو")
        #expect(PDFBookTextReader.withoutStraySymbols("100% of C# & more") == "100% of C# & more")
        let line = { (text: String) in PDFTextReadingOrder.Line(text: text, bounds: .zero) }
        let page = ["هل يمكن أن يحوّل", "MiPig a", "الإنسان ميوله", "www.alkalam-sy.com", "Chapter One Begins Here", "إلى مشروع ما"].map(line)
        #expect(PDFBookTextReader.withoutLatinNoise(page).map(\.text) == ["هل يمكن أن يحوّل", "الإنسان ميوله", "www.alkalam-sy.com", "Chapter One Begins Here", "إلى مشروع ما"])
        #expect(PDFBookTextReader.withoutLatinNoise(["Short title", "عنوان"].map(line)).count == 2)
        // Owner's scan: ornaments read as Latin letters stuck to words; real Latin words and links stay.
        #expect(PDFBookTextReader.withoutStraySymbols("كانت تميمةvVv في سرورهV") == "كانت تميمة في سروره")
        #expect(PDFBookTextReader.withoutStraySymbols("الفصل V الأول") == "الفصل الأول")
        #expect(PDFBookTextReader.withoutStraySymbols("زوروا www.alkalam-sy.com للمزيد") == "زوروا www.alkalam-sy.com للمزيد")
        #expect(PDFBookTextReader.withoutStraySymbols("الْأَرْضِ وَاسْتَعْمَرَكُمْ فِيهَا [هود: ٦١]") == "الْأَرْضِ وَاسْتَعْمَرَكُمْ فِيهَا [هود: ٦١]")
    }
}
