import Foundation

/// RU1: a separator must not put a middle dot beside a digit, including when
/// a formatter surrounds that digit with bidi isolation or whitespace.
public enum MadarInlineText {
    public static func joined(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.reduce("") { result, next in
            guard !result.isEmpty else { return next }
            func edgeDigit(_ value: String, reversed: Bool) -> Bool {
                let scalars = reversed ? Array(value.unicodeScalars.reversed()) : Array(value.unicodeScalars)
                let scalar = scalars.first {
                    !CharacterSet.whitespacesAndNewlines.contains($0) &&
                    $0.properties.generalCategory != .format
                }
                return scalar.map { Character(String($0)).wholeNumberValue != nil } ?? false
            }
            let separator = edgeDigit(result, reversed: true) || edgeDigit(next, reversed: false) ? "، " : " · "
            return result + separator + next
        }
    }
}
