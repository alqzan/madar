import Foundation

public enum PaperBookPageSource: String, Codable, Equatable, Sendable {
    case entered
    case estimated
    case unknown
}

public struct PaperBookChapter: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var page: Int?
    public var pageSource: PaperBookPageSource

    public init(id: UUID = UUID(), title: String, page: Int? = nil, pageSource: PaperBookPageSource = .unknown) {
        self.id = id
        self.title = title
        self.page = page
        self.pageSource = pageSource
    }
}

public enum PaperBookIndex {
    public static let maximumChapters = 300
    public static let maximumEncodedBytes = 65_536

    /// Returns the normalized ISBN-13 digits only, including the required checksum.
    public static func normalizedISBN13(_ raw: String) -> String? {
        var digits = ""
        for character in raw {
            if let value = character.wholeNumberValue, (0...9).contains(value) {
                digits.append(String(value))
            } else if character.isWhitespace || character == "-" || character == "‐" || character == "‑" {
                continue
            } else {
                return nil
            }
        }
        guard digits.count == 13, digits.hasPrefix("978") || digits.hasPrefix("979") else { return nil }
        let values = digits.compactMap(\.wholeNumberValue)
        let checksum = values.prefix(12).enumerated().reduce(0) { total, item in
            total + item.element * (item.offset.isMultiple(of: 2) ? 1 : 3)
        }
        guard (10 - checksum % 10) % 10 == values[12] else { return nil }
        return digits
    }

    public static func isValid(_ chapters: [PaperBookChapter], pages: Int?) -> Bool {
        guard chapters.count <= maximumChapters, pages.map({ (1...100_000).contains($0) }) ?? true else { return false }
        var previousPage = 0
        for chapter in chapters {
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 200 else { return false }
            switch (chapter.pageSource, chapter.page) {
            case (.unknown, nil):
                continue
            case (.entered, let page?), (.estimated, let page?):
                guard page >= 1, page <= 100_000, pages.map({ page <= $0 }) ?? true, page >= previousPage else { return false }
                previousPage = page
            default:
                return false
            }
        }
        return true
    }

    public static func encode(_ chapters: [PaperBookChapter], pages: Int?) -> Data? {
        guard isValid(chapters, pages: pages) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(chapters), data.count <= maximumEncodedBytes else { return nil }
        return data
    }

    public static func decode(_ data: Data, pages: Int?) -> [PaperBookChapter]? {
        guard data.count <= maximumEncodedBytes,
              let chapters = try? JSONDecoder().decode([PaperBookChapter].self, from: data),
              isValid(chapters, pages: pages) else { return nil }
        return chapters
    }

    /// Keeps only clear trailing page candidates; OCR values remain estimates until the reader confirms them.
    public static func chapters(fromOCRLines lines: [String], totalPages: Int?) -> [PaperBookChapter] {
        var result: [PaperBookChapter] = []
        var seen = Set<String>()
        for rawLine in lines.prefix(1_000) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard let last = parts.last else { continue }
            let pageText = last.trimmingCharacters(in: CharacterSet(charactersIn: ".,:؛،()[]{}"))
            guard let page = integer(pageText), page > 0,
                  totalPages.map({ page <= $0 }) ?? (page <= 100_000),
                  parts.count > 1 else { continue }
            let title = parts.dropLast().joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".…,:؛،—–- "))
            guard !title.isEmpty, title.count <= 200 else { continue }
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(.init(title: title, page: page, pageSource: .estimated))
            if result.count == maximumChapters { break }
        }
        return result
    }

    private static func integer(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        var digits = ""
        for character in text {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            digits.append(String(value))
        }
        return Int(digits)
    }
}
