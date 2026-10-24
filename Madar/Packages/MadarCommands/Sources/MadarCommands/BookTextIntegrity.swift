import Foundation
import MadarQuran

/// Findings are hints for the import review, never permission to rewrite a book.
public enum BookTextIntegrity {
    public static func needsInspection(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { scalar in
            scalar.value == 0xFFFD || (0xE000...0xF8FF).contains(scalar.value)
                || (0xF0000...0xFFFFD).contains(scalar.value) || (0x100000...0x10FFFD).contains(scalar.value)
                || (scalar.value < 0x20 && ![9, 10, 13].contains(scalar.value))
        }) { return true }
        // At least two consecutive UTF-8 Arabic byte pairs misread as Latin-1/CP1252.
        // One Scandinavian Ø or a normal mixed Arabic/English paragraph is not a finding.
        return text.range(of: #"(?:[ØÙ][\u0080-\u00BF\u0152\u0153\u0160\u0161\u0178\u017D\u017E\u0192\u02C6\u02DC\u2013-\u2026\u2030\u2039\u203A\u20AC\u2122]){2,}"#,
                          options: .regularExpression) != nil
    }
}

/// A conservative exact-word index: whole ayahs of at least four words and twenty
/// letters. It recognizes spelling/diacritic variants, never fuzzy or partial ayahs.
/// Ranges refer to the original UTF-16 text; normalized text must not be displayed.
public struct QuranQuotationIndex: Sendable {
    public let patterns: [[String]]
    private let byFirstWord: [String: [[String]]]
    private static let wordExpression = try! NSRegularExpression(pattern: #"[\p{L}\p{M}ـ]+"#)
    private static let bundledResult: Result<QuranQuotationIndex, Error> = Result {
        let catalog = try QuranResourceCatalog.bundled()
        return QuranQuotationIndex(ayahTexts: catalog.ayahs.flatMap { [$0.searchText, $0.uthmaniText] })
    }
    public static func bundled() throws -> Self { try bundledResult.get() }

    public init(ayahTexts: [String]) {
        let unique = Set(ayahTexts.map { Self.words(in: $0).map(\.value) }
            .filter { $0.count >= 4 && $0.joined().count >= 20 }.map { $0.joined(separator: " ") })
        patterns = unique.sorted().map { $0.split(separator: " ").map(String.init) }
        byFirstWord = Dictionary(grouping: patterns, by: { $0[0] })
    }

    public func matches(in text: String) -> [NSRange] {
        let words = Self.words(in: text)
        var result: [NSRange] = [], index = 0
        while index < words.count {
            let longest = (byFirstWord[words[index].value] ?? []).filter { pattern in
                index + pattern.count <= words.count && pattern.enumerated().allSatisfy { words[index + $0.offset].value == $0.element }
            }.map(\.count).max() ?? 0
            if longest > 0 {
                let first = words[index].range, last = words[index + longest - 1].range
                result.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location))
                index += longest
            } else { index += 1 }
        }
        return result
    }

    public func unmarkedCount(in text: String) -> Int {
        let withoutMarked = text.replacingOccurrences(of: "﴿[^﴾]*﴾", with: "\n", options: .regularExpression)
        return withoutMarked.components(separatedBy: .newlines).reduce(0) { $0 + matches(in: $1).count }
    }

    private static func words(in text: String) -> [(value: String, range: NSRange)] {
        let source = text as NSString
        return wordExpression.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let value = normalize(source.substring(with: match.range))
            return value.isEmpty ? nil : (value, match.range)
        }
    }

    public static func normalize(_ word: String) -> String {
        let scalars = word.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !CharacterSet.nonBaseCharacters.contains($0) && $0.value != 0x0640
        }
        return String(String.UnicodeScalarView(scalars)).replacingOccurrences(of: "ٱ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
    }
}
