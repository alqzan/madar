import XCTest
@testable import MadarQuran
final class QuranHizbMapTests: XCTestCase {
    func testPrintedHalvesAndOfficialJuzCoverEachAyahExactlyOnce() throws {
        let catalog=try QuranResourceCatalog.bundled(),segments=try catalog.hizbSegments()
        XCTAssertEqual(segments.count,60)
        let expected=[(2,75),(2,203),(3,15),(3,171),(4,88),(5,27),(6,36),(7,1),(7,171),(9,34),(10,26),(11,84),(13,19),(16,51),(17,99),(20,1),(22,1),(24,21),(26,111),(28,51),(31,22),(34,24),(37,145),(40,41),(43,24),(48,18),(55,1),(62,1),(72,1),(87,1)]
        for (i,pair) in expected.enumerated() {
            let ayah=try XCTUnwrap(catalog.ayah(id:segments[i*2+1].ayahs.first))
            XCTAssertEqual(ayah.surahID,pair.0);XCTAssertEqual(ayah.ayahNumber,pair.1)
        }
        let ids=segments.flatMap { Array($0.ayahs.first...$0.ayahs.last) }
        XCTAssertEqual(ids,Array(1...6236))
        XCTAssertEqual(catalog.ayah(id:segments[6].ayahs.first)?.ayahNumber,92) // Preserve official juz 4.
        for (j,s) in try catalog.juzCycleSegments().enumerated() { XCTAssertEqual(segments[j*2].ayahs.first,s.ayahs.first);XCTAssertEqual(segments[j*2+1].ayahs.last,s.ayahs.last) }
    }
}
