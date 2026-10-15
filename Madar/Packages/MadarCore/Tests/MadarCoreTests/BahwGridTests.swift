import Testing
@testable import MadarCore

/// §7.1: four columns, dense first-fit row by row from the right.
@Suite struct BahwGridTests {
    @Test func defaultBuiltBlocksPackDenselyFromTheRight() {
        // Default order with only built rooms: prayer wide, Quran small, year wide, upcoming wide, diary small.
        let placed = BahwGrid.pack([("salah", .wide), ("quran", .small), ("year", .wide), ("upcoming", .wide), ("notes", .small)])
        #expect(placed.map { [$0.row, $0.column] } == [[0, 0], [2, 0], [4, 0], [6, 0], [2, 2]])
        #expect(BahwGrid.rows(placed) == 8)
    }
    @Test func iconsFillTheFirstGapBeforeNewRows() {
        let placed = BahwGrid.pack([("a", .small), ("b", .icon), ("c", .wide), ("d", .icon)])
        #expect(placed.map { [$0.row, $0.column] } == [[0, 0], [0, 2], [2, 0], [0, 3]])
    }
}
