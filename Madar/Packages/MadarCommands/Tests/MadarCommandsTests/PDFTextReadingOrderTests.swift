import CoreGraphics
import Testing
@testable import MadarCommands

struct PDFTextReadingOrderTests {
    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat, width: CGFloat = 120) -> PDFTextReadingOrder.Line {
        .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: 12))
    }

    @Test(arguments: [true, false]) func columnsReadDownBeforeCrossingTheGutter(rightToLeft: Bool) {
        let lines = [line("يسار أول", 10, 30), line("يمين ثان", 170, 46),
                     line("يسار ثان", 10, 46), line("يمين أول", 170, 30)]
        let expected = rightToLeft ? "يمين أول\nيمين ثان\n\nيسار أول\nيسار ثان" : "يسار أول\nيسار ثان\n\nيمين أول\nيمين ثان"
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: rightToLeft) == expected)
    }

    @Test func fullWidthHeadingAndFootnoteStayOutsideTheColumns() {
        let lines = [line("حاشية أسفل العمودين", 10, 100, width: 280),
                     line("يسار أول", 10, 30), line("يمين ثان", 170, 46),
                     line("عنوان الفصل", 10, 0, width: 280),
                     line("يسار ثان", 10, 46), line("يمين أول", 170, 30)]
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: true) == "عنوان الفصل\n\nيمين أول\nيمين ثان\n\nيسار أول\nيسار ثان\n\nحاشية أسفل العمودين")
    }

    @Test func fragmentsKeepLogicalArabicAndMixedLanguageCharacters() {
        let lines = [line("PDF 123", 10, 10, width: 65), line("إِنَّ القراءةَ", 80, 9, width: 90),
                     line("سطر تالٍ", 10, 26, width: 160)]
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: true) == "إِنَّ القراءةَ\nPDF 123\nسطر تالٍ")
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: false) == "PDF 123\nإِنَّ القراءةَ\nسطر تالٍ")
    }

    @Test func paragraphSpacingNeverMakesColumnsInterleave() {
        let lines = [line("يسار أول", 10, 30), line("يمين ثان", 170, 70),
                     line("يسار ثان", 10, 70), line("يمين أول", 170, 30)]
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: true) == "يمين أول\n\nيمين ثان\n\nيسار أول\n\nيسار ثان")
    }

    @Test func invalidGeometryPreservesSourceOrderAndNoTextIsLost() {
        let lines = [line("أول", 0, 0), PDFTextReadingOrder.Line(text: "ثان", bounds: .null)]
        #expect(PDFTextReadingOrder.text(lines, rightToLeft: true) == "أول\nثان")
        #expect(PDFTextReadingOrder.text([], rightToLeft: true).isEmpty)
    }
}
