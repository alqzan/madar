import Foundation

/// A Turath set is one EPUB whose printed pages are labelled «ج/ص» (volume/page). The shelf draws one spine per
/// volume and the reader names the volume it is in; both read the volumes from the page labels here.
public enum BookVolumes {
    /// The volume part of a printed-page label: «٢/١٥» → «٢». A label without exactly one slash is not in a set.
    public static func key(_ label: String) -> String? {
        let parts = label.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
        return parts.count == 2 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : nil
    }

    /// The distinct volume keys in reading order; the n-th spine on the shelf is the n-th key.
    public static func order(_ labels: [String]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for key in labels.compactMap(key) where seen.insert(key).inserted { result.append(key) }
        return result
    }

    /// The volume (0-based) a printed page belongs to. A page without a volume label (an introduction, an index)
    /// belongs to the volume before it, or to the first volume.
    public static func volume(ofPage page: Int, labels: [String]) -> Int? {
        guard labels.indices.contains(page) else { return nil }
        let keys = order(labels)
        guard keys.count > 1 else { return nil }
        for label in labels[...page].reversed() { if let k = key(label), let index = keys.firstIndex(of: k) { return index } }
        return 0
    }

    /// Where a tap on a volume's spine opens: nil keeps the saved place (it is inside that volume),
    /// otherwise the first printed page of the volume. Nil too when the book has no such volume.
    public static func startPage(volume: Int, labels: [String], savedPage: Int?) -> Int? {
        let keys = order(labels)
        guard keys.count > 1, keys.indices.contains(volume) else { return nil }
        if let savedPage, self.volume(ofPage: savedPage, labels: labels) == volume { return nil }
        return labels.firstIndex { key($0) == keys[volume] }
    }

    private static let ordinals = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر",
                                   "الحادي عشر", "الثاني عشر", "الثالث عشر", "الرابع عشر", "الخامس عشر", "السادس عشر",
                                   "السابع عشر", "الثامن عشر", "التاسع عشر", "العشرون"]

    /// «الجزء الثاني» for volume index 1; nil past the twentieth, where the caller writes the number.
    public static func name(_ volume: Int) -> String? {
        ordinals.indices.contains(volume) ? "الجزء " + ordinals[volume] : nil
    }
}
