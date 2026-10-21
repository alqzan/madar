import Foundation

/// Turath and file titles carry more than a book's name: the editor («- ت السواس»), the edition («- ط دار المعرفة»),
/// where it was printed («(مطبوع ضمن …)»، «- ضمن «…»»), an alternative name («= الجواب الكافي»), and a classical
/// rhymed subtitle. The shelf shows the name a reader knows the book by; the full title stays on the book card.
public enum BookTitle {
    public struct Parts: Equatable, Sendable {
        /// The title without edition noise: «زاد المعاد في هدي خير العباد».
        public var main: String
        /// The name it is known by, short enough for a spine: «زاد المعاد».
        public var short: String
        /// Edition, editor or alternative name, for a small line: «ت السواس»، «الجواب الكافي».
        public var note: String?
    }

    public static func parts(_ raw: String) -> Parts {
        var main = raw.replacingOccurrences(of: "\u{200F}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        var notes: [String] = []
        // «(مطبوع ضمن …)» and any other trailing bracket.
        if main.hasSuffix(")"), let open = main.lastIndex(of: "("), open > main.startIndex {
            let inner = main[main.index(after: open)..<main.index(before: main.endIndex)].trimmingCharacters(in: .whitespaces)
            main = String(main[..<open]).trimmingCharacters(in: .whitespaces)
            if !inner.hasPrefix("مطبوع") { notes.append(inner) }
        }
        // « - ت …», « - ط …», « - ضمن …», « - name»: everything after the first spaced dash is about the edition.
        for dash in [" - ", " – ", " — "] {
            if let range = main.range(of: dash), main.distance(from: main.startIndex, to: range.lowerBound) >= 3 {
                let tail = String(main[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                main = String(main[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty, !tail.hasPrefix("ضمن") { notes.append(tail) }
                break
            }
        }
        // « = alternative name»: keep the first name, offer the second as the note.
        if let range = main.range(of: " = ") {
            let alternative = String(main[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            main = String(main[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !alternative.isEmpty { notes.insert(alternative, at: 0) }
        }
        if main.isEmpty { main = raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Parts(main: main, short: short(main), note: notes.first)
    }

    /// A long classical title is two rhymed halves joined by «في»، «فيما»، «من»، «على»، «إلى»، «عن» or a «و» word;
    /// the first half is the name. A cut never leaves fewer than two words.
    static func short(_ main: String) -> String {
        let beforeColon = main.split(separator: "،", maxSplits: 1).first.map(String.init) ?? main
        let words = beforeColon.split(separator: " ").map(String.init)
        guard words.count > 4 else { return beforeColon.trimmingCharacters(in: .whitespaces) }
        let joins: Set<String> = ["في", "فيما", "من", "على", "إلى", "عن"]
        for index in 2..<words.count {
            let word = words[index]
            if joins.contains(word) || (word.hasPrefix("و") && word.count > 3 && !words[index - 1].hasPrefix("و")) {
                return words[..<index].joined(separator: " ")
            }
        }
        return beforeColon
    }
}
