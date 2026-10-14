import CoreText
import Foundation
import XCTest
@testable import MadarQuran

final class QuranPrintedGlyphTests: XCTestCase {
    func testAllOriginalPageFontsCoverEveryBoundPrintedGlyph() throws {
        let printed = try QuranPrintedGlyphs.bundled(), catalog = try QuranResourceCatalog.bundled()
        var words = 0, markers = 0
        for page in printed.pages {
            let url = try QuranPrintedGlyphs.fontURL(page: page.page)
            let descriptors = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
            let descriptor = try XCTUnwrap(descriptors.first)
            let font = CTFontCreateWithFontDescriptor(descriptor, 23.3, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, page.fontName)
            let characters = Array(Set(page.entries.flatMap { $0.glyphs.utf16 }.filter { $0 != 32 })).sorted()
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count), "Page \(page.page)")
            XCTAssertFalse(glyphs.contains(0))
            let layout = try XCTUnwrap(catalog.layout?.page(page.page))
            for line in layout.lines {
                let values = page.entries.filter { $0.line == line.number }
                XCTAssertEqual(values.filter { $0.wordIndex != nil }.map { "\($0.ayahID):\($0.wordIndex!)" }, line.words.map { "\($0.ayahID):\($0.wordIndex)" })
                XCTAssertEqual(values.filter { $0.wordIndex == nil }.map(\.ayahID), line.ayahEnds)
            }
            words += page.entries.filter { $0.wordIndex != nil }.count
            markers += page.entries.filter { $0.wordIndex == nil }.count
        }
        XCTAssertEqual(words, 77_429); XCTAssertEqual(markers, 6_236)
        XCTAssertEqual(printed.pages[284].fontName, "QCF2285")
        XCTAssertEqual(printed.pages[284].entries.first?.glyphs, "ﱁ")
        XCTAssertEqual(printed.pages[284].entries.first?.ayahID, 2_057)
    }
}
