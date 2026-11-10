import Foundation
import MadarQuran
import XCTest
import CoreText
import CoreGraphics

@MainActor
final class QuranResourceCatalogTests: XCTestCase {
    func testBundled1439MapCoversTheCompleteMushaf() throws {
        let catalog = try QuranResourceCatalog.bundled()

        XCTAssertEqual(catalog.ayahs.count, 6_236)
        XCTAssertNotNil(QuranResourceCatalog.bundledFontURL())
        XCTAssertNil(catalog.ayah(id: 0))
        XCTAssertNil(catalog.ayah(id: 6_237))
        XCTAssertEqual(catalog.ayahs(on: 1).map(\.ayahID), Array(1...7))
        XCTAssertEqual(catalog.ayahs(on: 285).map(\.ayahID), Array(2_057...2_067))
        XCTAssertEqual(catalog.ayahs(on: 604).map(\.ayahID), Array(6_222...6_236))

        let juzStarts = [
            1, 149, 260, 385, 517, 641, 751, 900, 1_042, 1_201,
            1_329, 1_479, 1_649, 1_803, 2_030, 2_215, 2_484, 2_674,
            2_876, 3_215, 3_386, 3_564, 3_733, 4_090, 4_265, 4_511,
            4_706, 5_105, 5_242, 5_673,
        ]
        let segments = try catalog.juzCycleSegments()
        XCTAssertEqual(segments.count, 30)
        XCTAssertEqual(segments.map(\.ayahs.first), juzStarts)
        XCTAssertEqual(segments.map(\.ayahs.last), Array(juzStarts.dropFirst()).map { $0 - 1 } + [6_236])
    }

    func testCanonicalPageLineBoundariesComeFromTheBundledMap() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let firstPage = catalog.ayahs(on: 1)
        let page285 = catalog.ayahs(on: 285)
        let lastPage = catalog.ayahs(on: 604)

        // The Complex's opening-page illustration shares lines between ayahs;
        // ayah 6 crosses lines 5...6 and ayah 7 occupies 6...8.
        XCTAssertEqual(firstPage.map(\.lineStart), [2, 3, 4, 4, 5, 5, 6])
        XCTAssertEqual(firstPage.map(\.lineEnd), [2, 3, 4, 4, 5, 6, 8])
        XCTAssertEqual(page285.first?.lineStart, 1)
        XCTAssertEqual(page285.first?.lineEnd, 2)
        XCTAssertEqual(page285.last?.lineStart, 15)
        XCTAssertEqual(page285.last?.lineEnd, 15)
        XCTAssertEqual(lastPage.first?.ayahID, 6_222)
        XCTAssertEqual(lastPage.first?.lineStart, 3)
        XCTAssertEqual(lastPage.last?.lineEnd, 15)
    }

    func testWordRangesRetainExactUTF16OffsetsAndExcludeAyahEndGlyph() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let fatihaOpening = try XCTUnwrap(catalog.ayah(id: 1))
        let tokens = fatihaOpening.wordTokens

        XCTAssertEqual(tokens.map(\.text), ["بِسۡمِ", "ٱللَّهِ", "ٱلرَّحۡمَٰنِ", "ٱلرَّحِيمِ"])
        XCTAssertEqual(tokens.map(\.wordIndex), Array(0..<4))
        let source = fatihaOpening.uthmaniText as NSString
        for token in tokens {
            XCTAssertEqual(
                source.substring(with: NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)),
                token.text
            )
            XCTAssertFalse(token.text.unicodeScalars.contains { (0xFC00...0xFD1D).contains(Int($0.value)) })
        }
    }

    func testStandaloneRubElHizbMarkerDoesNotConsumeAWordIndex() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let ayahAtMarker = try XCTUnwrap(catalog.ayah(id: 33))
        let tokens = ayahAtMarker.wordTokens

        XCTAssertEqual(tokens.first?.wordIndex, 0)
        XCTAssertEqual(tokens.first?.text, "إِنَّ")
        XCTAssertFalse(tokens.contains { $0.text == "۞" })
        let first = try XCTUnwrap(tokens.first)
        XCTAssertEqual(
            (ayahAtMarker.uthmaniText as NSString).substring(
                with: NSRange(location: first.utf16Range.lowerBound, length: first.utf16Range.count)
            ),
            "إِنَّ"
        )
    }

    func testSajdahAnnotationStaysAttachedToItsSourceWord() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let sajdahAyah = try XCTUnwrap(catalog.ayah(id: 1_160))
        let finalToken = try XCTUnwrap(sajdahAyah.wordTokens.last)

        XCTAssertTrue(finalToken.text.hasSuffix("۩"))
        XCTAssertFalse(finalToken.text.contains("ﳍ"))
        XCTAssertEqual(
            (sajdahAyah.uthmaniText as NSString).substring(
                with: NSRange(location: finalToken.utf16Range.lowerBound, length: finalToken.utf16Range.count)
            ),
            finalToken.text
        )
    }

    func testAyahNumbers257Through286NeverBecomeWords() throws {
        let catalog = try QuranResourceCatalog.bundled()
        XCTAssertEqual(try XCTUnwrap(catalog.ayah(id: 264)).wordTokens.last?.text, "خَٰلِدُونَ")
        XCTAssertEqual(try XCTUnwrap(catalog.ayah(id: 293)).wordTokens.last?.text, "ٱلۡكَٰفِرِينَ")
        for ayah in catalog.ayahs {
            for word in ayah.wordTokens {
                XCTAssertFalse(word.text.unicodeScalars.contains { (0xFC00...0xFD1D).contains(Int($0.value)) })
            }
        }
    }

    func testWordLayoutPreservesSourceSpellingAcrossCompoundGroups() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let ayah = { (surah: Int, number: Int) in catalog.ayahs.first { $0.surahID == surah && $0.ayahNumber == number }! }
        // Independently checked Quran.com word records for these seven cases.
        XCTAssertEqual(ayah(2, 181).wordTokens[2].text, "بَعۡدَ مَا")
        XCTAssertEqual(ayah(8, 6).wordTokens[3].text, "بَعۡدَ مَا")
        XCTAssertEqual(ayah(13, 37).wordTokens[7].text, "بَعۡدَ مَا")
        XCTAssertEqual(Array(ayah(15, 7).wordTokens.prefix(2)).map(\.text), ["لَّوۡ", "مَا"])
        XCTAssertEqual(Array(ayah(27, 20).wordTokens[3...4]).map(\.text), ["مَا", "لِيَ"])
        XCTAssertEqual(Array(ayah(36, 22).wordTokens.prefix(2)).map(\.text), ["وَمَا", "لِيَ"])
        XCTAssertEqual(ayah(37, 130).wordTokens[2].text, "إِلۡ يَاسِينَ")
        XCTAssertEqual(catalog.ayahs.reduce(0) { $0 + $1.wordTokens.count }, 77_429)
        XCTAssertTrue(catalog.ayahs.allSatisfy { $0.wordTokens.allSatisfy { $0.lineNumber != nil } })
    }

    func testAllLinesHaveOneRoleAndEveryAyahHasAnEndMarker() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let layout = try XCTUnwrap(catalog.layout)
        XCTAssertNil(layout.page(0)); XCTAssertNil(layout.page(605))
        let lines = layout.pages.flatMap(\.lines)
        XCTAssertEqual(lines.filter { $0.kind == .surah }.count, 114)
        XCTAssertEqual(lines.filter { $0.kind == .basmala }.count, 112)
        XCTAssertEqual(lines.flatMap(\.ayahEnds).sorted(), Array(1...6236))
        XCTAssertEqual(layout.pages.filter { $0.lines.count != 15 }.map(\.page), [1, 2])
        // RQ7: use the official KFGQPC boundary, not the API/Tanzil 3:93 boundary.
        XCTAssertEqual(catalog.ayahs.first { $0.juz == 4 }?.ayahID, 385)
        XCTAssertEqual(catalog.ayahs.first { $0.juz == 11 }?.ayahID, 1329)
    }

    func testCorruptWordRangeIsRejectedBeforeThePageCanBeUsed() throws {
        let manifest = try QuranResourceManifest.bundled()
        let raw = try manifest.verifiedData(at: "Quran1439/layout.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var pages = try XCTUnwrap(json["pages"] as? [[String: Any]])
        var lines = try XCTUnwrap(pages[284]["lines"] as? [[String: Any]])
        var words = try XCTUnwrap(lines[0]["words"] as? [[String: Any]])
        words[0]["upperUTF16"] = Int.max
        lines[0]["words"] = words; pages[284]["lines"] = lines; json["pages"] = pages
        let broken = try JSONDecoder().decode(QuranMushafLayout.self, from: JSONSerialization.data(withJSONObject: json))
        let valid = try QuranResourceCatalog.bundled()
        XCTAssertThrowsError(try QuranResourceCatalog(ayahs: valid.ayahs, layout: broken)) { error in
            XCTAssertEqual(error as? QuranResourceCatalogError, .invalidLayout(285))
        }
    }

    func testManifestPinsAllFilesAndSeparates1405ArtworkFromQuranData() throws {
        let manifest = try QuranResourceManifest.bundled()
        try manifest.verifyFiles()
        XCTAssertEqual(manifest.files.count, 610) // four original resources + 604 fonts + glyph binding + printed hizb starts
        XCTAssertEqual(manifest.files.filter { $0.path.hasPrefix("Quran1439/Fonts/") }.count, 604)
        XCTAssertEqual(manifest.files.filter { $0.role == "visualOnly" }.map(\.edition), [1405])
        XCTAssertTrue(manifest.files.filter { $0.role == "quranData" }.allSatisfy { $0.edition == 1439 })
        for name in ["surah-opening"] {
            let svg = String(decoding: try manifest.ornament(named: name), as: UTF8.self)
            XCTAssertEqual(svg.components(separatedBy: "<image ").count - 1, 4)
            XCTAssertFalse(svg.contains("<text"))
        }
        XCTAssertThrowsError(try manifest.verifiedData(at: "missing.json")) { error in
            XCTAssertEqual(error as? QuranResourceCatalogError, .missingResource("missing.json"))
        }
    }

    func testOfficialUnicodeFontHasNoMissingGlyphForAnyBundledAyah() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let url = try XCTUnwrap(QuranResourceCatalog.bundledFontURL())
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphicsFont = try XCTUnwrap(CGFont(provider))
        let font = CTFontCreateWithGraphicsFont(graphicsFont, 24, nil, nil)
        let text = catalog.ayahs.map(\.uthmaniText).joined()
        var characters = Array(Set(text.utf16)).filter { code in
            guard let scalar = UnicodeScalar(Int(code)) else { return true }
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
        XCTAssertFalse(glyphs.contains(0), "Never substitute another font for a missing Quran glyph")
    }
}
