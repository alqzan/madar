import Foundation

/// The natural identity used by the user's saved vocabulary and sync deduplication.
public enum UserWordIdentity {
    public static func normalizedWord(_ word: String) -> String {
        let lowercased = word.lowercased()
        let stripped = lowercased.unicodeScalars
            .filter { !CharacterSet.nonBaseCharacters.contains($0) && $0.value != 0x0640 }
            .map(String.init).joined()
        return stripped
            .replacingOccurrences(of: "[أإآ]", with: "ا", options: .regularExpression)
    }

    public static func key(language: String, word: String) -> String {
        "\(language):\(normalizedWord(word))"
    }
}
