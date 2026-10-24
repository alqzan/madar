import Foundation
import CoreGraphics

/// Page-space lines, with a top-left origin. Only their sequence changes; the
/// logical characters inside an Arabic line must never be reversed.
enum PDFTextReadingOrder {
    struct Line {
        let text: String
        let bounds: CGRect
    }

    static func text(_ lines: [Line], rightToLeft: Bool) -> String {
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return "" }
        // Invalid geometry cannot justify discarding or rearranging source text.
        guard usable.allSatisfy({ !$0.bounds.isNull && !$0.bounds.isInfinite && $0.bounds.width > 0 && $0.bounds.height > 0 }) else {
            return usable.map(\.text).joined(separator: "\n")
        }
        return blocks(usable, rightToLeft: rightToLeft).map { $0.map(\.text).joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private static func blocks(_ lines: [Line], rightToLeft: Bool) -> [[Line]] {
        guard lines.count > 1 else { return [lines] }
        let heights = lines.map { $0.bounds.height }.sorted()
        let height = heights[heights.count / 2]
        // Prefer a clear column gutter to paragraph gaps within the columns.
        // A full-width heading blocks that gutter, so isolate its horizontal band first.
        if let split = gap(lines, vertical: true, minimum: height * 1.2), split.0.count >= 2, split.1.count >= 2 {
            let first = rightToLeft ? split.1 : split.0, second = rightToLeft ? split.0 : split.1
            return blocks(first, rightToLeft: rightToLeft) + blocks(second, rightToLeft: rightToLeft)
        }
        if let split = gap(lines, vertical: false, minimum: height * 0.7) {
            return blocks(split.0, rightToLeft: rightToLeft) + blocks(split.1, rightToLeft: rightToLeft)
        }
        // Group overlapping baselines before ordering line fragments. A pairwise
        // "near enough" comparator is not transitive and can scramble three lines.
        let sorted = lines.enumerated().sorted {
            $0.element.bounds.midY == $1.element.bounds.midY ? $0.offset < $1.offset : $0.element.bounds.midY < $1.element.bounds.midY
        }.map(\.element)
        var rows: [[Line]] = []
        for line in sorted {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.bounds.midY - line.bounds.midY) < min(anchor.bounds.height, line.bounds.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        return [rows.flatMap { row in
            row.enumerated().sorted {
                if $0.element.bounds.minX == $1.element.bounds.minX { return $0.offset < $1.offset }
                return rightToLeft ? $0.element.bounds.minX > $1.element.bounds.minX : $0.element.bounds.minX < $1.element.bounds.minX
            }.map(\.element)
        }]
    }

    /// The widest empty strip spanning the region. No line crosses the cut.
    private static func gap(_ lines: [Line], vertical: Bool, minimum: CGFloat) -> ([Line], [Line])? {
        let lower: (Line) -> CGFloat = { vertical ? $0.bounds.minX : $0.bounds.minY }
        let upper: (Line) -> CGFloat = { vertical ? $0.bounds.maxX : $0.bounds.maxY }
        let sorted = lines.sorted { lower($0) < lower($1) }
        var end = upper(sorted[0]), best: (width: CGFloat, cut: CGFloat)?
        for line in sorted.dropFirst() {
            let width = lower(line) - end
            if width > minimum, width > (best?.width ?? 0) { best = (width, end + width / 2) }
            end = max(end, upper(line))
        }
        guard let best else { return nil }
        let first = lines.filter { upper($0) < best.cut }
        let second = lines.filter { lower($0) > best.cut }
        guard !first.isEmpty, !second.isEmpty, first.count + second.count == lines.count else { return nil }
        return (first, second)
    }
}
