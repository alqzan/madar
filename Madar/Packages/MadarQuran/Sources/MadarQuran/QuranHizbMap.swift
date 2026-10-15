import Foundation

/// Even starts transcribed from the Complex's Hafs39 printed marginal labels.
/// Odd starts use the unchanged official Hafs 2.0 juz field, including its 3:92/9:93 choices.
public extension QuranResourceCatalog {
    func hizbSegments() throws -> [QuranCycleSegment] {
        struct Source: Decodable { struct Start: Decodable { let number: Int; let ayahID: Int; let surah: Int; let ayah: Int; let page: Int; let line: Int }; let evenStarts: [Start] }
        let data = try QuranResourceManifest.bundled().verifiedData(at: "Quran1439/hizb-starts.json")
        let starts = try JSONDecoder().decode(Source.self, from: data).evenStarts
        guard starts.map(\.number) == Array(stride(from: 2, through: 60, by: 2)) else { throw QuranResourceCatalogError.malformedData }
        let juz = try juzCycleSegments()
        var ordered: [(Int, Int)] = []
        for (i, start) in starts.enumerated() {
            guard let record = ayah(id: start.ayahID), record.surahID == start.surah, record.ayahNumber == start.ayah,
                  record.page == start.page, record.lineStart == start.line,
                  start.ayahID > juz[i].ayahs.first, start.ayahID <= juz[i].ayahs.last else { throw QuranResourceCatalogError.malformedData }
            ordered += [(2 * i + 1, juz[i].ayahs.first), (start.number, start.ayahID)]
        }
        return try ordered.enumerated().map { index, start in
            QuranCycleSegment(number: start.0, ayahs: try QuranAyahRange(first: start.1, last: index + 1 < ordered.count ? ordered[index + 1].1 - 1 : 6236))
        }
    }
}
