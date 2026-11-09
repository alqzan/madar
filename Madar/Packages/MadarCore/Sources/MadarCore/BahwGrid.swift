import Foundation

/// §7.1 lobby grid: four columns; sizes icon 1×1, small 2×2, wide 4×2, large 4×4 (columns × rows).
/// Packing is dense first-fit, row by row, starting from the right (column 0 is the rightmost).
public enum BahwBlockSize: String, CaseIterable, Sendable {
    case icon = "1x1", small = "2x2", wide = "4x2", large = "4x4"
    public var columns: Int { switch self { case .icon: 1; case .small: 2; case .wide, .large: 4 } }
    public var rows: Int { switch self { case .icon: 1; case .small, .wide: 2; case .large: 4 } }
}

public struct BahwPlacement: Equatable, Sendable {
    public let id: String
    public let size: BahwBlockSize
    public let row: Int
    /// Counted from the right edge.
    public let column: Int
}

public enum BahwGrid {
    /// `columns` is 4 on iPhone; iPad uses 8, so two wide cards or four small ones share a row at the same card size.
    public static func pack(_ blocks: [(id: String, size: BahwBlockSize)], columns: Int = 4) -> [BahwPlacement] {
        var filled = Set<[Int]>(), placements: [BahwPlacement] = []
        for block in blocks {
            var row = 0
            search: while true {
                for column in 0...max(0, columns - block.size.columns) {
                    let cells = (row..<row + block.size.rows).flatMap { r in (column..<column + block.size.columns).map { [r, $0] } }
                    if cells.allSatisfy({ !filled.contains($0) }) {
                        cells.forEach { filled.insert($0) }
                        placements.append(.init(id: block.id, size: block.size, row: row, column: column))
                        break search
                    }
                }
                row += 1
            }
        }
        return placements
    }
    public static func rows(_ placements: [BahwPlacement]) -> Int { placements.map { $0.row + $0.size.rows }.max() ?? 0 }
}
