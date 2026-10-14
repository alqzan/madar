import Foundation
import MadarCore

public struct QuranWordToken: Equatable, Sendable {
    public let wordIndex: Int
    public let text: String
    /// UTF-16 offsets into the source ayah text, suitable for attributed-text hit testing.
    public let utf16Range: Range<Int>
    public let lineNumber: Int?

    init(wordIndex: Int, text: String, utf16Range: Range<Int>, lineNumber: Int? = nil) {
        self.wordIndex = wordIndex
        self.text = text
        self.utf16Range = utf16Range
        self.lineNumber = lineNumber
    }
}

public struct QuranAyahResourceRecord: Decodable, Equatable, Sendable {
    public let id: Int
    public let juz: Int
    public let page: Int
    public let surahID: Int
    public let surahNameEnglish: String
    public let surahNameArabic: String
    public let lineStart: Int
    public let lineEnd: Int
    public let ayahNumber: Int
    public let uthmaniText: String
    public let searchText: String
    var mappedTokens: [QuranWordToken]? = nil

    public var ayahID: Int { id }

    public var wordTokens: [QuranWordToken] {
        if let mappedTokens { return mappedTokens }
        var visibleEnd = uthmaniText.endIndex
        if let last = uthmaniText.last, isAyahEndMark(last) {
            visibleEnd = uthmaniText.index(before: visibleEnd)
            while visibleEnd > uthmaniText.startIndex,
                  uthmaniText[uthmaniText.index(before: visibleEnd)].isWhitespace {
                visibleEnd = uthmaniText.index(before: visibleEnd)
            }
        }

        let visibleText = uthmaniText[..<visibleEnd]
        var result: [QuranWordToken] = []
        var wordStart: String.Index?
        var cursor = visibleText.startIndex

        while cursor < visibleText.endIndex {
            let next = visibleText.index(after: cursor)
            if visibleText[cursor].isWhitespace {
                if let start = wordStart {
                    appendToken(from: start, to: cursor, in: uthmaniText, into: &result)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = cursor
            }
            cursor = next
        }

        if let start = wordStart {
            appendToken(from: start, to: visibleText.endIndex, in: uthmaniText, into: &result)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case juz = "jozz"
        case page
        case surahID = "sura_no"
        case surahNameEnglish = "sura_name_en"
        case surahNameArabic = "sura_name_ar"
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case ayahNumber = "aya_no"
        case uthmaniText = "aya_text"
        case searchText = "aya_text_emlaey"
    }

    private func appendToken(from start: String.Index, to end: String.Index, in source: String, into result: inout [QuranWordToken]) {
        let range = start..<end
        let text = String(source[range])
        // The source puts rub el hizb on its own between ayahs at some juz boundaries.
        // It is a display marker, not a Quran word, and must not shift word indexes.
        guard text != "\u{06DE}" else { return }
        let lower = start.utf16Offset(in: source)
        let upper = end.utf16Offset(in: source)
        result.append(QuranWordToken(
            wordIndex: result.count,
            text: text,
            utf16Range: lower..<upper
        ))
    }

    private func isAyahEndMark(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return false }
        // The source font also uses FD00...FD1D for ayah numbers 257...286.
        return (0xFC00...0xFD1D).contains(Int(scalar.value))
    }
}

public enum QuranResourceCatalogError: Error, Equatable {
    case missingBundledData
    case malformedData
    case invalidAyah(Int)
    case incompletePages
    case incompleteSurahs
    case incompleteJuz
    case invalidLayout(Int)
    case missingResource(String)
    case checksumMismatch(String)
    case invalidManifest
}

public struct QuranResourceCatalog: Sendable {
    public static let expectedAyahCount = 6_236
    public static let expectedPageCount = 604

    public let ayahs: [QuranAyahResourceRecord]
    public let layout: QuranMushafLayout?
    private let indexByAyahID: [Int: Int]
    private let indexesByPage: [Int: [Int]]

    public init(ayahs: [QuranAyahResourceRecord], layout: QuranMushafLayout? = nil) throws {
        guard ayahs.count == Self.expectedAyahCount else {
            throw QuranResourceCatalogError.malformedData
        }

        var previousPage = 0
        var previousJuz = 0
        var expectedAyahBySurah: [Int: Int] = [:]
        var pageSet = Set<Int>()
        var surahSet = Set<Int>()
        var juzSet = Set<Int>()
        var idIndexes: [Int: Int] = [:]
        var pageIndexes: [Int: [Int]] = [:]

        for (offset, ayah) in ayahs.enumerated() {
            guard ayah.id == offset + 1,
                  (1...114).contains(ayah.surahID),
                  ayah.ayahNumber == expectedAyahBySurah[ayah.surahID, default: 1],
                  (1...Self.expectedPageCount).contains(ayah.page),
                  ayah.page >= previousPage,
                  (1...30).contains(ayah.juz),
                  ayah.juz >= previousJuz,
                  (1...15).contains(ayah.lineStart),
                  (ayah.lineStart...15).contains(ayah.lineEnd),
                  !ayah.uthmaniText.isEmpty,
                  !ayah.searchText.isEmpty,
                  !ayah.wordTokens.isEmpty else {
                throw QuranResourceCatalogError.invalidAyah(offset + 1)
            }

            expectedAyahBySurah[ayah.surahID, default: 1] += 1
            pageSet.insert(ayah.page)
            surahSet.insert(ayah.surahID)
            juzSet.insert(ayah.juz)
            idIndexes[ayah.id] = offset
            pageIndexes[ayah.page, default: []].append(offset)
            previousPage = ayah.page
            previousJuz = ayah.juz
        }

        guard pageSet == Set(1...Self.expectedPageCount) else {
            throw QuranResourceCatalogError.incompletePages
        }
        guard surahSet == Set(1...114) else {
            throw QuranResourceCatalogError.incompleteSurahs
        }
        guard juzSet == Set(1...30) else {
            throw QuranResourceCatalogError.incompleteJuz
        }

        var mappedAyahs = ayahs
        if let layout {
            try layout.bind(to: &mappedAyahs)
        }
        self.ayahs = mappedAyahs
        self.layout = layout
        self.indexByAyahID = idIndexes
        self.indexesByPage = pageIndexes
    }

    public static func bundled() throws -> QuranResourceCatalog {
        try QuranResourceManifest.bundled().verifyFiles()
        guard let url = Bundle.module.url(
            forResource: "hafsData_v2-0",
            withExtension: "json",
            subdirectory: "UthmanicHafs_v2-0"
        ) else {
            throw QuranResourceCatalogError.missingBundledData
        }

        do {
            let data = try Data(contentsOf: url)
            let ayahs = try JSONDecoder().decode([QuranAyahResourceRecord].self, from: data)
            return try QuranResourceCatalog(ayahs: ayahs, layout: QuranMushafLayout.bundled())
        } catch let error as QuranResourceCatalogError {
            throw error
        } catch {
            throw QuranResourceCatalogError.malformedData
        }
    }

    public static func bundledFontURL() -> URL? {
        Bundle.module.url(
            forResource: "uthmanic_hafs_v20",
            withExtension: "ttf",
            subdirectory: "UthmanicHafs_v2-0"
        )
    }

    public func ayah(id: Int) -> QuranAyahResourceRecord? {
        guard let index = indexByAyahID[id] else { return nil }
        return ayahs[index]
    }

    public func ayahs(on page: Int) -> [QuranAyahResourceRecord] {
        (indexesByPage[page] ?? []).map { ayahs[$0] }
    }

    public func juzCycleSegments() throws -> [QuranCycleSegment] {
        let recordsByJuz = Dictionary(grouping: ayahs, by: \.juz)
        return try (1...30).map { number in
            guard let records = recordsByJuz[number],
                  let first = records.first?.ayahID,
                  let last = records.last?.ayahID else {
                throw QuranResourceCatalogError.incompleteJuz
            }
            return QuranCycleSegment(
                number: number,
                ayahs: try QuranAyahRange(first: first, last: last)
            )
        }
    }
}
