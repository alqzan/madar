import XCTest

/// Owner, 9 Nov 2026: «لازم اضغط على الكلمه الي فيها الزر… لو ضغطت على الاخضر مايضبط». A filled button must take a tap
/// anywhere on its colour, not only on its words: this taps the green «التالي» near its edge, far from the text.
final class ButtonEdgeTapUITests: XCTestCase {
    func testQuranSetupNextTakesATapOnItsEdge() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense",
                                 "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00", "MADAR_UI_START_TAB": "quran"]
        app.launch()
        let start = app.buttons["quran-start-plan"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let title = app.staticTexts["quran-setup-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "«ابدأ خطة الحفظ» must open from its edge.")
        let first = title.label
        let next = app.buttons["quran-setup-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        let moved = NSPredicate { _, _ in title.label != first }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 5)
    }
}
