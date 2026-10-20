import Foundation

/// Exact, conservative source matching for salary suggestions. The bank sender is never used as a source.
public enum SalarySourceMatcher {
    public static func key(_ counterparty: String?) -> String? {
        guard let counterparty else { return nil }
        let normalized = BankDedupe.normalize(counterparty)
        guard !normalized.isEmpty,
              normalized.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return normalized
    }

    public static func matches(_ counterparty: String?, learnedKeys: Set<String>) -> Bool {
        guard let key = key(counterparty) else { return false }
        return learnedKeys.contains(key)
    }
}
