import MadarQuran
import XCTest

final class QuranTafsirIndexTests: XCTestCase {
    func testMapsInlineAyahReferencesWithinSurahSections() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let fixture = #"""
        {
          "toc": { "headings": [
            { "title": "مقدمات", "level": 1, "page": 1 },
            { "title": "تفسير سورة البقرة", "level": 1, "page": 2 },
            { "title": "سورة آل عمران", "level": 1, "page": 3 }
          ] },
          "pages": [
            { "text": "<span data-type=\"title\" id=toc-1>مقدمات</span>\nمقدمة.", "vol": "1", "page": 1 },
            { "text": "<span data-type=\"title\" id=toc-2>تفسير سورة البقرة</span>\nشرح الآية ١٨٧ من البقرة [البقرة: ١٨٧].\nشرح مستقل من سورة أخرى [آل عمران: ١٠٠].", "vol": "2", "page": 68 },
            { "text": "<span data-type=\"title\" id=toc-3>سورة آل عمران</span>\nنص الآية التالية.", "vol": "2", "page": 69 }
          ]
        }
        """#
        let metadata = QuranTafsirBookMetadata(
            bookID: 1_503,
            title: "تفسير ابن كثير",
            author: "ابن كثير",
            turathURL: "https://app.turath.io/book/1503",
            shamelaURL: "https://shamela.ws/book/1503"
        )
        let index = try QuranTafsirIndex.decodeTurathJSON(Data(fixture.utf8), metadata: metadata, catalog: catalog)
        let target = try XCTUnwrap(catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 187 })
        let passage = try XCTUnwrap(index.passages(forAyahID: target.id).first)

        XCTAssertEqual(passage.surahID, 2)
        XCTAssertEqual(passage.firstAyahID, target.id)
        XCTAssertEqual(passage.pages, [.init(id: 2, volume: "2", printedPage: "68")])
        XCTAssertTrue(passage.text.contains("شرح الآية ١٨٧"), passage.text)
        XCTAssertFalse(passage.text.contains("شرح مستقل"), "A nearby citation for another surah must not enter this passage.")
        XCTAssertTrue(index.passages(forAyahID: target.id).allSatisfy { $0.surahID == 2 })
    }

    func testBundledSaadiCoversEveryAyahWithPrintedPageReferences() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let index = try QuranTafsirIndex.bundledSaadi(catalog: catalog)

        XCTAssertEqual(index.metadata.bookID, 42)
        XCTAssertEqual(index.coveredAyahIDs, Set(1...QuranResourceCatalog.expectedAyahCount))
        XCTAssertTrue(index.passages.allSatisfy { !$0.pages.isEmpty && !$0.text.isEmpty })
        XCTAssertTrue(index.passages.allSatisfy { passage in
            guard let first = catalog.ayah(id: passage.firstAyahID),
                  let last = catalog.ayah(id: passage.lastAyahID) else { return false }
            return first.surahID == passage.surahID && last.surahID == passage.surahID
        })

        for ayahID in 1...QuranResourceCatalog.expectedAyahCount {
            XCTAssertEqual(index.passages(forAyahID: ayahID).count, 1, "Ayah \(ayahID) must map to one Saadi passage")
        }

        let alHumazah = try XCTUnwrap(index.passages(forAyahID: 6_180).first)
        XCTAssertEqual(alHumazah.lastAyahID, 6_188)
        XCTAssertEqual(alHumazah.pages.first?.printedPage, "934")
        XCTAssertTrue(alHumazah.text.contains("﴿١ - ٩﴾"))

        let finalAyah = try XCTUnwrap(index.passages(forAyahID: 6_236).first)
        XCTAssertFalse(finalAyah.text.contains("أصول وكليات"))
    }
}
