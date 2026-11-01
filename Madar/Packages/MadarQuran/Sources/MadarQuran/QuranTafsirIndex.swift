import CryptoKit
import Foundation

public struct QuranTafsirBookMetadata: Codable, Equatable, Sendable {
    public let bookID: Int
    public let title: String
    public let author: String
    public let turathURL: String
    public let shamelaURL: String

    public init(bookID: Int, title: String, author: String, turathURL: String, shamelaURL: String) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.turathURL = turathURL
        self.shamelaURL = shamelaURL
    }
}

public struct QuranTafsirPageReference: Codable, Equatable, Sendable, Identifiable {
    /// Turath/Shamela's page id (one-based within the downloaded book), not the printed page.
    public let id: Int
    public let volume: String
    public let printedPage: String

    public init(id: Int, volume: String, printedPage: String) {
        self.id = id
        self.volume = volume
        self.printedPage = printedPage
    }
}

public struct QuranTafsirPassage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let surahID: Int
    public let firstAyahID: Int
    public let lastAyahID: Int
    public let pages: [QuranTafsirPageReference]
    public let text: String

    public init(id: String, surahID: Int, firstAyahID: Int, lastAyahID: Int, pages: [QuranTafsirPageReference], text: String) {
        self.id = id
        self.surahID = surahID
        self.firstAyahID = firstAyahID
        self.lastAyahID = lastAyahID
        self.pages = pages
        self.text = text
    }

    public func contains(ayahID: Int) -> Bool { (firstAyahID...lastAyahID).contains(ayahID) }
}

public struct QuranTafsirIndex: Codable, Equatable, Sendable {
    public let version: Int
    public let metadata: QuranTafsirBookMetadata
    public let passages: [QuranTafsirPassage]

    public init(metadata: QuranTafsirBookMetadata, passages: [QuranTafsirPassage]) {
        self.version = 1
        self.metadata = metadata
        self.passages = passages
    }

    public var coveredAyahIDs: Set<Int> {
        Set(passages.flatMap { $0.firstAyahID...$0.lastAyahID })
    }

    public func passages(forAyahID ayahID: Int) -> [QuranTafsirPassage] {
        passages.filter { $0.contains(ayahID: ayahID) }
    }

    public static func decodeTurathJSON(
        _ data: Data,
        metadata: QuranTafsirBookMetadata,
        catalog: QuranResourceCatalog
    ) throws -> QuranTafsirIndex {
        let source = try TurathTafsirSource(data: data)
        let allChapters = chapterNumbers(in: source.headings, catalog: catalog)
        var seenSections = Set<String>()
        let chapters = allChapters.filter { seenSections.insert("\($0.surahID):\($0.firstNumber)").inserted }
        let fallback = inferredWholeSurahPassages(source: source, chapters: chapters, metadata: metadata, catalog: catalog)
        let fallbackPages = Set(fallback.flatMap { $0.pages.map(\.id) })
        var result = fallback

        for (position, chapter) in chapters.enumerated() {
            let next = chapters.dropFirst(position + 1).first
            let finalVerse: Int
            if let next, next.surahID == chapter.surahID, next.firstNumber > chapter.firstNumber {
                finalVerse = next.firstNumber - 1
            } else {
                finalVerse = chapter.verseCount
            }
            guard finalVerse >= chapter.firstNumber else { continue }

            let textEndPage = next?.pageIndex ?? source.contentEndPageIndex
            let endPage = max(chapter.pageIndex, textEndPage)
            let nextSpan = next.flatMap { source.titleSpans[$0.tocID] }
            let startSpan = source.titleSpans[chapter.tocID]
            let firstAyahID = chapter.firstAyahID
            let lastAyahID = firstAyahID + finalVerse - chapter.firstNumber
            var pageReferences: [QuranTafsirPageReference] = []
            var parts: [String] = []

            for pageID in chapter.pageIndex...endPage {
                guard source.pages.indices.contains(pageID - 1), !fallbackPages.contains(pageID) else { continue }
                let page = source.pages[pageID - 1]
                if isSurahTitlePage(page.text) { continue }
                let raw = page.text as NSString
                let lower = pageID == chapter.pageIndex ? startSpan?.range.upperBound ?? 0 : 0
                let upper: Int
                if pageID == next?.pageIndex, let nextSpan {
                    upper = nextSpan.range.location
                } else {
                    upper = raw.length
                }
                guard lower <= upper, upper <= raw.length else { continue }
                let plain = plainText(raw.substring(with: NSRange(location: lower, length: upper - lower)))
                guard !plain.isEmpty else { continue }
                parts.append(plain)
                pageReferences.append(.init(id: pageID, volume: page.volume, printedPage: page.printedPage))
            }

            let text = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            result.append(.init(
                id: "\(metadata.bookID)-\(firstAyahID)-\(lastAyahID)-\(chapter.pageIndex)",
                surahID: chapter.surahID,
                firstAyahID: firstAyahID,
                lastAyahID: lastAyahID,
                pages: uniquePages(pageReferences),
                text: text
            ))
        }

        let mappedAyahs = Set(result.flatMap { $0.firstAyahID...$0.lastAyahID })
        result.append(contentsOf: explicitReferencePassages(
            source: source,
            headings: source.headings,
            metadata: metadata,
            catalog: catalog,
            excludingAyahs: mappedAyahs
        ))

        let index = QuranTafsirIndex(metadata: metadata, passages: result.sorted {
            if $0.firstAyahID != $1.firstAyahID { return $0.firstAyahID < $1.firstAyahID }
            return ($0.pages.first?.id ?? 0) < ($1.pages.first?.id ?? 0)
        })
        guard !index.passages.isEmpty else { throw QuranTafsirIndexError.noVerseSections }
        return index
    }

    public static func bundledSaadi(catalog: QuranResourceCatalog) throws -> QuranTafsirIndex {
        let manifest = try QuranTafsirResourceManifest.bundled()
        let data = try manifest.saadiData()
        let metadata = QuranTafsirBookMetadata(
            bookID: manifest.saadiBookID,
            title: manifest.saadiTitle,
            author: manifest.saadiAuthor,
            turathURL: manifest.saadiTurathURL,
            shamelaURL: manifest.saadiShamelaURL
        )
        let index = try decodeTurathJSON(data, metadata: metadata, catalog: catalog)
        guard index.coveredAyahIDs.count == QuranResourceCatalog.expectedAyahCount else {
            throw QuranTafsirIndexError.incompleteBundledCoverage(index.coveredAyahIDs.count)
        }
        return index
    }
}

public enum QuranTafsirIndexError: Error, Equatable {
    case malformedSource
    case noVerseSections
    case incompleteBundledCoverage(Int)
    case missingResource
    case resourceChecksumMismatch
}

public enum QuranWirdReferenceResourceError: Error, Equatable {
    case missingResource
}

public enum QuranWirdReferenceResource {
    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "QuranWirdReferenceExcerpts", withExtension: "json") else {
            throw QuranWirdReferenceResourceError.missingResource
        }
        return try Data(contentsOf: url)
    }
}

private struct QuranTafsirResourceManifest: Decodable {
    let bookID: Int
    let title: String
    let author: String
    let turathURL: String
    let shamelaURL: String
    let resourcePath: String
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case bookID = "bookId"
        case title
        case author
        case turathURL = "turathUrl"
        case shamelaURL = "shamelaUrl"
        case resourcePath
        case sha256
    }

    var saadiBookID: Int { bookID }
    var saadiTitle: String { title }
    var saadiAuthor: String { author }
    var saadiTurathURL: String { turathURL }
    var saadiShamelaURL: String { shamelaURL }

    static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "QuranTafsirResourceManifest", withExtension: "json") else {
            throw QuranTafsirIndexError.missingResource
        }
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
        catch { throw QuranTafsirIndexError.malformedSource }
    }

    func saadiData() throws -> Data {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent(resourcePath) else {
            throw QuranTafsirIndexError.missingResource
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw QuranTafsirIndexError.missingResource }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw QuranTafsirIndexError.resourceChecksumMismatch }
        return data
    }
}

private struct TurathTafsirSource {
    struct Page {
        let text: String
        let volume: String
        let printedPage: String
    }

    struct Heading {
        let title: String
        let level: Int
        let pageIndex: Int
    }

    struct TitleSpan {
        let range: NSRange
    }

    struct Chapter {
        let surahID: Int
        let firstNumber: Int
        let verseCount: Int
        let firstAyahID: Int
        let pageIndex: Int
        let tocID: Int
    }

    let pages: [Page]
    let headings: [Heading]
    let titleSpans: [Int: TitleSpan]
    let contentEndPageIndex: Int

    init(data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawPages = root["pages"] as? [[String: Any]], !rawPages.isEmpty else {
            throw QuranTafsirIndexError.malformedSource
        }

        let parsedPages = rawPages.map { raw in
            Page(
                text: raw["text"] as? String ?? "",
                volume: (raw["vol"] as? String) ?? (raw["vol"] as? Int).map(String.init) ?? "",
                printedPage: (raw["page"] as? String) ?? (raw["page"] as? Int).map(String.init) ?? ""
            )
        }
        pages = parsedPages

        var candidates: [[[String: Any]]] = []
        for (key, value) in root where key != "pages" {
            guard let dictionary = value as? [String: Any] else { continue }
            for inner in dictionary.values {
                if let list = inner as? [[String: Any]], list.first?["title"] != nil, list.first?["page"] != nil {
                    candidates.append(list)
                }
            }
        }
        guard let rawHeadings = candidates.max(by: { $0.count < $1.count }), !rawHeadings.isEmpty else {
            throw QuranTafsirIndexError.malformedSource
        }
        let parsedHeadings: [Heading] = rawHeadings.compactMap { raw -> Heading? in
            guard let title = raw["title"] as? String,
                  let page = raw["page"] as? Int,
                  (1...parsedPages.count).contains(page) else { return nil }
            return Heading(title: title, level: max(1, raw["level"] as? Int ?? 1), pageIndex: page)
        }
        guard !parsedHeadings.isEmpty else { throw QuranTafsirIndexError.malformedSource }
        headings = parsedHeadings

        var spans: [Int: TitleSpan] = [:]
        for page in parsedPages {
            let source = page.text as NSString
            for match in Self.titleSpanRegex.matches(in: page.text, range: NSRange(location: 0, length: source.length)) {
                guard let id = Int(source.substring(with: match.range(at: 1))) else { continue }
                spans[id] = TitleSpan(range: match.range)
            }
        }
        titleSpans = spans
        contentEndPageIndex = parsedHeadings.last?.pageIndex ?? parsedPages.count
    }

    private static let titleSpanRegex = try! NSRegularExpression(
        pattern: #"<span\b(?=[^>]*\bdata-type=[\"']?title[\"']?)(?=[^>]*\bid=[\"']?toc-(\d+)[\"']?)[^>]*>.*?</span>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
}

private func chapterNumbers(in headings: [TurathTafsirSource.Heading], catalog: QuranResourceCatalog) -> [TurathTafsirSource.Chapter] {
    var surahIDsByName: [String: Int] = [:]
    var counts: [Int: Int] = [:]
    var firstIDs: [Int: Int] = [:]
    for ayah in catalog.ayahs {
        surahIDsByName[normalizeArabicTitle(ayah.surahNameArabic)] = ayah.surahID
        counts[ayah.surahID, default: 0] += 1
        if firstIDs[ayah.surahID] == nil { firstIDs[ayah.surahID] = ayah.id }
    }
    // One Turath heading omits the hamza in «الهمزة»; the surrounding source pages carry the complete 1–9 range.
    surahIDsByName[normalizeArabicTitle("الهمزة")] = 104

    var currentSurahID: Int?
    var chapters: [TurathTafsirSource.Chapter] = []
    for (offset, heading) in headings.enumerated() {
        if heading.level == 1, let surahID = surahID(forHeading: heading.title, names: surahIDsByName) {
            currentSurahID = surahID
            continue
        }
        guard let currentSurahID,
              let firstNumber = headingVerseRange(in: heading.title)?.lowerBound,
              firstNumber <= counts[currentSurahID, default: 0],
              let surahFirstAyahID = firstIDs[currentSurahID] else { continue }
        let firstAyahID = surahFirstAyahID + firstNumber - 1
        chapters.append(.init(
            surahID: currentSurahID,
            firstNumber: firstNumber,
            verseCount: counts[currentSurahID, default: 0],
            firstAyahID: firstAyahID,
            pageIndex: heading.pageIndex,
            tocID: offset + 1
        ))
    }
    return chapters
}

private struct TurathSurahSection {
    let surahID: Int
    let pageIndex: Int
    let tocID: Int
    let verseCount: Int
    let firstAyahID: Int
}

private func explicitReferencePassages(
    source: TurathTafsirSource,
    headings: [TurathTafsirSource.Heading],
    metadata: QuranTafsirBookMetadata,
    catalog: QuranResourceCatalog,
    excludingAyahs: Set<Int>
) -> [QuranTafsirPassage] {
    guard excludingAyahs.count < QuranResourceCatalog.expectedAyahCount else { return [] }
    var names: [String: Int] = [:]
    for ayah in catalog.ayahs { names[normalizeArabicTitle(ayah.surahNameArabic)] = ayah.surahID }
    let sections = headings.enumerated().compactMap { offset, heading -> TurathSurahSection? in
        guard heading.level == 1,
              let surahID = surahID(forHeading: heading.title, names: names),
              let first = catalog.ayahs.first(where: { $0.surahID == surahID }),
              let last = catalog.ayahs.last(where: { $0.surahID == surahID }) else { return nil }
        return TurathSurahSection(
            surahID: surahID,
            pageIndex: heading.pageIndex,
            tocID: offset + 1,
            verseCount: last.ayahNumber,
            firstAyahID: first.id
        )
    }
    guard !sections.isEmpty else { return [] }

    let reference = try! NSRegularExpression(pattern: #"\[([^\]\n:]{1,40})\s*:\s*([٠-٩0-9]+)\s*\]"#)
    var result: [QuranTafsirPassage] = []
    var seen = Set<String>()

    for (offset, section) in sections.enumerated() {
        let next = sections.dropFirst(offset + 1).first
        let endPage = max(section.pageIndex, (next?.pageIndex ?? source.contentEndPageIndex) - (next == nil ? 0 : 1))
        let startSpan = source.titleSpans[section.tocID]
        let nextSpan = next.flatMap { source.titleSpans[$0.tocID] }

        for pageID in section.pageIndex...endPage {
            guard source.pages.indices.contains(pageID - 1) else { continue }
            let page = source.pages[pageID - 1]
            let raw = page.text as NSString
            let lower = pageID == section.pageIndex ? startSpan?.range.upperBound ?? 0 : 0
            let upper = pageID == next?.pageIndex ? nextSpan?.range.location ?? raw.length : raw.length
            guard lower <= upper, upper <= raw.length else { continue }
            let text = plainText(raw.substring(with: NSRange(location: lower, length: upper - lower)))
            let nsText = text as NSString
            let matches = reference.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            for (matchIndex, match) in matches.enumerated() {
                let sourceName = normalizeArabicTitle(nsText.substring(with: match.range(at: 1)))
                guard surahID(forHeading: sourceName, names: names) == section.surahID,
                      let verseNumber = decimalNumber(nsText.substring(with: match.range(at: 2))),
                      verseNumber <= section.verseCount else { continue }
                let ayahID = section.firstAyahID + verseNumber - 1
                guard !excludingAyahs.contains(ayahID) else { continue }

                let paragraphStartMatch = nsText.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: match.range.location))
                let paragraphStart = paragraphStartMatch.location == NSNotFound ? 0 : NSMaxRange(paragraphStartMatch)
                let paragraphEndMatch = nsText.range(of: "\n", range: NSRange(location: NSMaxRange(match.range), length: nsText.length - NSMaxRange(match.range)))
                let paragraphEnd = paragraphEndMatch.location == NSNotFound ? nsText.length : paragraphEndMatch.location
                let paragraph = nsText.substring(with: NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = "\(ayahID):\(pageID):\(paragraph)"
                guard !paragraph.isEmpty, seen.insert(identity).inserted else { continue }

                result.append(.init(
                    id: "\(metadata.bookID)-\(ayahID)-\(ayahID)-\(pageID)-\(matchIndex)",
                    surahID: section.surahID,
                    firstAyahID: ayahID,
                    lastAyahID: ayahID,
                    pages: [.init(id: pageID, volume: page.volume, printedPage: page.printedPage)],
                    text: paragraph
                ))
            }
        }
    }
    return result
}

private func surahID(forHeading source: String, names: [String: Int]) -> Int? {
    var title = normalizeArabicTitle(source)
    title = title.components(separatedBy: " وهي ").first ?? title
    for prefix in ["تفسير سورة ", "سورة "] where title.hasPrefix(prefix) {
        title = String(title.dropFirst(prefix.count))
        break
    }
    if title.hasPrefix("تفسير السورة التي يذكر فيها ") { title = String(title.dropFirst("تفسير السورة التي يذكر فيها ".count)) }
    if title == "الماعون" { return 107 }
    if let exact = names[title] { return exact }

    let aliases: [String: Int] = [
        "سبحان": 17, "القتال": 47, "ن": 68, "سال سائل": 70,
        "والتين والزيتون": 95, "اقرا": 96, "لم يكن": 98,
        "اذا زلزلت": 99, "ويل لكل همزه لمزه": 104, "لايلاف قريش": 106,
        "قل ياايها الكافرون": 109, "اذا جاء نصر الله والفتح": 110, "تبت": 111,
    ]
    return aliases[title]
}

private func inferredWholeSurahPassages(
    source: TurathTafsirSource,
    chapters: [TurathTafsirSource.Chapter],
    metadata: QuranTafsirBookMetadata,
    catalog: QuranResourceCatalog
) -> [QuranTafsirPassage] {
    let chapterSurahs = Set(chapters.map(\.surahID))
    let allSurahs = Set(catalog.ayahs.map(\.surahID))
    let missingSurahs = allSurahs.subtracting(chapterSurahs)
    guard !missingSurahs.isEmpty else { return [] }
    var result: [QuranTafsirPassage] = []

    for surahID in missingSurahs.sorted() {
        guard let first = catalog.ayahs.first(where: { $0.surahID == surahID }),
              let last = catalog.ayahs.last(where: { $0.surahID == surahID }),
              let previous = chapters.filter({ $0.surahID < surahID }).map(\.pageIndex).max(),
              let next = chapters.filter({ $0.surahID > surahID }).map(\.pageIndex).min(),
              previous < next else { continue }

        for pageID in (previous + 1)..<next {
            guard source.pages.indices.contains(pageID - 1) else { continue }
            let page = source.pages[pageID - 1]
            guard let explicitRange = leadingRange(in: page.text),
                  explicitRange.lowerBound == 1,
                  explicitRange.upperBound == last.ayahNumber,
                  containsAyahs(first: first, last: last, in: page.text, catalog: catalog) else { continue }
            let text = plainText(page.text)
            guard !text.isEmpty else { continue }
            result.append(.init(
                id: "\(metadata.bookID)-\(first.id)-\(last.id)-\(pageID)",
                surahID: surahID,
                firstAyahID: first.id,
                lastAyahID: last.id,
                pages: [.init(id: pageID, volume: page.volume, printedPage: page.printedPage)],
                text: text
            ))
            break
        }
    }
    return result
}

private func containsAyahs(first: QuranAyahResourceRecord, last: QuranAyahResourceRecord, in source: String, catalog: QuranResourceCatalog) -> Bool {
    let normalizedSource = normalizeVerseText(plainText(source))
    var cursor = normalizedSource.startIndex
    for ayahID in first.id...last.id {
        guard let ayah = catalog.ayah(id: ayahID) else { return false }
        let target = normalizeVerseText(ayah.searchText)
        guard !target.isEmpty, let match = normalizedSource.range(of: target, range: cursor..<normalizedSource.endIndex) else { return false }
        cursor = match.upperBound
    }
    return true
}

private func leadingRange(in source: String) -> ClosedRange<Int>? {
    let text = plainText(source)
    let pattern = try! NSRegularExpression(pattern: #"^\s*[﴿]?\s*([0-9٠-٩]+)\s*﴾?\s*[-–]\s*[﴿]?\s*([0-9٠-٩]+)\s*﴾?"#)
    let ns = text as NSString
    guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
          let first = decimalNumber(ns.substring(with: match.range(at: 1))),
          let last = decimalNumber(ns.substring(with: match.range(at: 2))),
          first <= last else { return nil }
    return first...last
}

private func headingVerseRange(in title: String) -> ClosedRange<Int>? {
    if let range = leadingRange(in: title) { return range }
    guard let number = arabicNumber(title) else { return nil }
    return number...number
}

private func uniquePages(_ pages: [QuranTafsirPageReference]) -> [QuranTafsirPageReference] {
    var seen = Set<Int>()
    return pages.filter { seen.insert($0.id).inserted }
}

private func isSurahTitlePage(_ source: String) -> Bool {
    let lines = plainText(source).split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard let first = lines.first else { return false }
    let normalized = normalizeArabicTitle(first)
    return (normalized.hasPrefix("تفسير سورة ") || normalized.hasPrefix("تفسير ")) && lines.count <= 2
}

private func arabicNumber(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "﴿﴾ \t\n\r"))
    return decimalNumber(trimmed)
}

private func decimalNumber(_ text: String) -> Int? {
    guard !text.isEmpty else { return nil }
    let digits = text.compactMap { character -> String? in
        guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
        return String(value)
    }
    guard digits.count == text.count else { return nil }
    return Int(digits.joined())
}

private func normalizeArabicTitle(_ source: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in source.unicodeScalars {
        let value = scalar.value
        if (0x064B...0x065F).contains(value) || value == 0x0670 || (0x06D6...0x06ED).contains(value) || value == 0x0640 { continue }
        switch value {
        case 0x0622, 0x0623, 0x0625, 0x0671: result.append("ا")
        case 0x0649: result.append("ي")
        case 0x0648, 0x064A, 0x0621...0x064A, 0x0660...0x0669, 0x06F0...0x06F9: result.append(scalar)
        default:
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { result.append(" ") }
        }
    }
    return String(result).split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func normalizeVerseText(_ source: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in source.unicodeScalars {
        let value = scalar.value
        if (0x064B...0x065F).contains(value) || value == 0x0670 || (0x06D6...0x06ED).contains(value) || value == 0x0640 { continue }
        switch value {
        case 0x0622, 0x0623, 0x0625, 0x0671: result.append("ا")
        case 0x0649: result.append("ي")
        case 0x0621...0x064A: result.append(scalar)
        default:
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { result.append(" ") }
        }
    }
    return String(result).split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func plainText(_ source: String) -> String {
    var value = source
    for (pattern, replacement) in [
        (#"<br\s*/?>"#, "\n"),
        (#"</(?:p|div|h[1-6]|li|section)>"#, "\n"),
        (#"<[^>]+>"#, "")
    ] {
        value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    for (entity, replacement) in [
        ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
        ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")
    ] {
        value = value.replacingOccurrences(of: entity, with: replacement)
    }
    return value
        .replacingOccurrences(of: "\u{00a0}", with: " ")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}
