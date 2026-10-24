import Foundation
import Testing
@testable import MadarCommands

struct BookTextIntegrityTests {
    @Test(arguments: ["نص\u{FFFD} مفقود", "حرف \u{E012}", "Ø§Ù„ÙƒØªØ§Ø¨", "سطر\u{01}آخر"])
    func suspiciousSymbolsAreReportedWithoutRepair(_ text: String) {
        #expect(BookTextIntegrity.needsInspection(text))
    }

    @Test(arguments: ["كتاب عربي سليمٌ\nوالسطر الثاني.", "عربي English 2026 معًا", "Øresund — a Scandinavian name", "نصّ\u{200D} موصول"])
    func ordinaryTextDoesNotGetAnEncodingWarning(_ text: String) {
        #expect(!BookTextIntegrity.needsInspection(text))
    }

    @Test func fullAyahsKeepOriginalRangesAndShortPhrasesStayOrdinary() throws {
        let index = try QuranQuotationIndex.bundled()
        let quote = "لَقَدْ خَلَقْنَا الْإِنْسَانَ فِي أَحْسَنِ تَقْوِيمٍ"
        let source = "قال: " + quote + "، ثم علّق الكاتب."
        let ranges = index.matches(in: source)
        #expect(ranges.count == 1)
        let range = try #require(ranges.first)
        #expect((source as NSString).substring(with: range) == quote)
        #expect(index.matches(in: "وكتب المؤلف: قل هو الله أحد.").isEmpty, "Short phrases need explicit brackets")
        #expect(index.matches(in: "لقد خلقنا الإنسان في تقويم أحسن").isEmpty, "Word order is part of the exact match")
        #expect(index.unmarkedCount(in: "﴿" + quote + "﴾ ثم " + quote) == 1)
        #expect(index.unmarkedCount(in: "لقد خلقنا الإنسان\nفي أحسن تقويم") == 0, "Do not combine unrelated paragraphs")
    }
}
