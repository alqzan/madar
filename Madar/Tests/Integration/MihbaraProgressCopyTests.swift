import XCTest
@testable import Madar

/// AU-95: a book opened but barely moved is still «لم تبدأه بعد» (nil), never «قرأت منه ٠٪»; the end is held at ٩٩٪.
final class MihbaraProgressCopyTests: XCTestCase {
    func testProgressPercentKeepsNotStartedAndHoldsTheEnd() {
        XCTAssertNil(MihbaraCopy.progressPercent(nil))
        XCTAssertNil(MihbaraCopy.progressPercent(0))
        XCTAssertNil(MihbaraCopy.progressPercent(0.002))
        XCTAssertEqual(MihbaraCopy.progressPercent(0.006), 1)
        XCTAssertEqual(MihbaraCopy.progressPercent(0.5), 50)
        XCTAssertEqual(MihbaraCopy.progressPercent(0.995), 99)
        XCTAssertEqual(MihbaraCopy.progressPercent(1), 100)
    }
}
