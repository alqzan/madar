import Testing
@testable import MadarCore

struct InlineTextTests {
    @Test func numericEdgesUseCommaAndWordEdgesKeepTheWordSeparator() {
        #expect(MadarInlineText.joined(["١٢:٣٤", "بعد دقيقة"]) == "١٢:٣٤، بعد دقيقة")
        #expect(MadarInlineText.joined(["المصدر", "١٢"]) == "المصدر، ١٢")
        #expect(MadarInlineText.joined(["مسافر", "مدينة 2", "قصر وجمع"]) == "مسافر · مدينة 2، قصر وجمع")
        #expect(MadarInlineText.joined(["", "كتاب", "", "مؤلف"]) == "كتاب · مؤلف")
        #expect(MadarInlineText.joined([]).isEmpty)
    }
    @Test func isolationAndDirectionalMarksCannotHideNumericEdges() {
        #expect(MadarInlineText.joined(["\u{2068}۱۲\u{2069} ", "التالي"]) == "\u{2068}۱۲\u{2069}، التالي")
        #expect(MadarInlineText.joined(["الصفحة", "\u{200F} \u{2067}٣\u{2069}"]) == "الصفحة، \u{200F} \u{2067}٣\u{2069}")
    }
}
