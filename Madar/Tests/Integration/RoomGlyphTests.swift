import XCTest
import UIKit
@testable import Madar

final class RoomGlyphTests: XCTestCase {
    func testEveryRoomHasDistinctVectorTemplatesAndSelectionVariant() throws {
        var originals = Set<Data>()
        for name in ["MadarPrayer", "MadarQuran", "MadarDiary", "MadarOrbit", "MadarYear", "MadarUpcoming"] {
            let normal = try XCTUnwrap(UIImage(named: name)), selected = try XCTUnwrap(UIImage(named: name + "Selected"))
            XCTAssertGreaterThan(normal.size.width, 0)
            let bytes = try XCTUnwrap(normal.pngData()); originals.insert(bytes)
            XCTAssertNotEqual(bytes, selected.pngData(), name)
        }
        XCTAssertEqual(originals.count, 6)
    }
}
