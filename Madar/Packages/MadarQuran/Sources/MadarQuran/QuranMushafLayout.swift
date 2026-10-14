import Foundation

public struct QuranLayoutWord: Decodable, Equatable, Sendable {
    public let ayahID: Int
    public let wordIndex: Int
    public let lowerUTF16: Int
    public let upperUTF16: Int
}

public struct QuranLayoutLine: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable { case ayah, surah, basmala }
    public let number: Int
    public let kind: Kind
    public let surahID: Int?
    public let words: [QuranLayoutWord]
    public let ayahEnds: [Int]
}

public struct QuranLayoutPage: Decodable, Equatable, Sendable {
    public let page: Int
    public let lines: [QuranLayoutLine]
}

/// Logical word placements in the owner's 1439 text. Native text layout supplies
/// the final hit rectangles; no QCF presentation code is drawn in another font.
public struct QuranMushafLayout: Decodable, Equatable, Sendable {
    public let version: Int
    public let edition: Int
    public let pages: [QuranLayoutPage]

    static func bundled() throws -> Self {
        let data = try QuranResourceManifest.bundled().verifiedData(at: "Quran1439/layout.json")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func page(_ number: Int) -> QuranLayoutPage? {
        guard pages.indices.contains(number - 1), pages[number - 1].page == number else { return nil }
        return pages[number - 1]
    }

    func bind(to ayahs: inout [QuranAyahResourceRecord]) throws {
        guard version == 1, edition == 1439, pages.count == 604, ayahs.count == 6236 else {
            throw QuranResourceCatalogError.invalidLayout(0)
        }
        var wordsByAyah: [Int: [(QuranLayoutWord, Int)]] = [:]
        var endings = Set<Int>()
        var titles = Set<Int>()
        var basmalas = Set<Int>()
        for (offset, page) in pages.enumerated() {
            guard page.page == offset + 1, page.lines.count == (page.page <= 2 ? 8 : 15) else {
                throw QuranResourceCatalogError.invalidLayout(page.page)
            }
            for (lineOffset, line) in page.lines.enumerated() {
                guard line.number == lineOffset + 1 else { throw QuranResourceCatalogError.invalidLayout(page.page) }
                if line.kind != .ayah {
                    guard let surah = line.surahID, (1...114).contains(surah), line.words.isEmpty,
                          line.ayahEnds.isEmpty else { throw QuranResourceCatalogError.invalidLayout(page.page) }
                    if line.kind == .surah {
                        guard titles.insert(surah).inserted else { throw QuranResourceCatalogError.invalidLayout(page.page) }
                    } else {
                        guard surah != 1, surah != 9, basmalas.insert(surah).inserted else {
                            throw QuranResourceCatalogError.invalidLayout(page.page)
                        }
                    }
                }
                for word in line.words {
                    guard line.kind == .ayah, (1...ayahs.count).contains(word.ayahID) else {
                        throw QuranResourceCatalogError.invalidLayout(page.page)
                    }
                    let ayah = ayahs[word.ayahID - 1]
                    guard ayah.page == page.page, (ayah.lineStart...ayah.lineEnd).contains(line.number) else {
                        throw QuranResourceCatalogError.invalidLayout(page.page)
                    }
                    wordsByAyah[word.ayahID, default: []].append((word, line.number))
                }
                for id in line.ayahEnds {
                    guard line.kind == .ayah, (1...ayahs.count).contains(id), endings.insert(id).inserted,
                          ayahs[id - 1].page == page.page, ayahs[id - 1].lineEnd == line.number else {
                        throw QuranResourceCatalogError.invalidLayout(page.page)
                    }
                }
            }
        }
        guard endings.count == 6236, titles == Set(1...114), basmalas == Set(2...114).subtracting([9]) else {
            throw QuranResourceCatalogError.invalidLayout(0)
        }
        for i in ayahs.indices {
            let ayah = ayahs[i]
            let source = ayah.uthmaniText as NSString
            let placed = wordsByAyah[ayah.id, default: []]
            guard !placed.isEmpty, placed.first?.1 == ayah.lineStart else {
                throw QuranResourceCatalogError.invalidLayout(ayah.page)
            }
            var tokens: [QuranWordToken] = []
            var cursor = 0
            for (index, item) in placed.enumerated() {
                let (word, line) = item
                guard word.wordIndex == index, word.lowerUTF16 >= cursor,
                      word.upperUTF16 > word.lowerUTF16, word.upperUTF16 <= source.length else {
                    throw QuranResourceCatalogError.invalidLayout(ayah.page)
                }
                for offset in cursor..<word.lowerUTF16 where !Self.isDecorationOrSpace(source.character(at: offset)) {
                    throw QuranResourceCatalogError.invalidLayout(ayah.page)
                }
                let range = word.lowerUTF16..<word.upperUTF16
                let text = source.substring(with: NSRange(location: range.lowerBound, length: range.count))
                guard !text.unicodeScalars.contains(where: { (0xFC00...0xFD1D).contains(Int($0.value)) }) else {
                    throw QuranResourceCatalogError.invalidLayout(ayah.page)
                }
                tokens.append(QuranWordToken(wordIndex: index, text: text, utf16Range: range, lineNumber: line))
                cursor = word.upperUTF16
            }
            for offset in cursor..<source.length where !Self.isDecorationOrSpace(source.character(at: offset)) {
                throw QuranResourceCatalogError.invalidLayout(ayah.page)
            }
            ayahs[i].mappedTokens = tokens
        }
    }

    private static func isDecorationOrSpace(_ unit: unichar) -> Bool {
        if (0xFC00...0xFD1D).contains(Int(unit)) || unit == 0x06DE { return true }
        guard let scalar = UnicodeScalar(Int(unit)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
