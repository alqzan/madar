import XCTest
@testable import Madar

/// Owner, 30 Oct 2026: «أكمل القراءة» names the book on the stand everywhere; the stand survives a relaunch.
final class MihbaraStandTests: XCTestCase {
    private func book(_ shelf: String) -> MihbaraBook { MihbaraBook(id: UUID(), title: shelf, author: "", shelf: shelf, pages: nil, page: nil, finished: nil, updated: .distantPast) }
    private func defaults() -> UserDefaults { let d = UserDefaults(suiteName: "stand-\(UUID())")!; return d }

    func testSavedBookWinsOverShelfOrderAndSurvivesARelaunch() {
        let d = defaults(), first = book("reading"), second = book("reading"), later = book("later")
        let books = [first, later, second]
        XCTAssertEqual(MihbaraStand.pick(from: books, d)?.id, first.id)
        MihbaraStand.save(second.id, d)
        XCTAssertEqual(MihbaraStand.pick(from: books, d)?.id, second.id)
        XCTAssertEqual(MihbaraStand.savedID(d), second.id)
    }
    func testBookLeavingTheReadingShelfFallsBackAndNothingReadingIsNil() {
        let d = defaults(), first = book("reading"), moved = book("later")
        MihbaraStand.save(moved.id, d)
        XCTAssertEqual(MihbaraStand.pick(from: [moved, first], d)?.id, first.id)
        XCTAssertNil(MihbaraStand.pick(from: [moved], d))
    }
    func testThisSessionsChoiceBeatsTheSavedOne() {
        let d = defaults(), a = book("reading"), b = book("reading")
        MihbaraStand.save(a.id, d)
        XCTAssertEqual(MihbaraStand.pick(from: [a, b], preferred: b.id, d)?.id, b.id)
    }
}
