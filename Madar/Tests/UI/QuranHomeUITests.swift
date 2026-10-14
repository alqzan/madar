import XCTest

@MainActor final class QuranHomeUITests: XCTestCase {
    func testHomeLevelsDetailsAndDraftResumeAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), store = UUID().uuidString
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        attach(app, "M2-V01-home-L")
        app.swipeUp()
        XCTAssertTrue(app.otherElements["quran-log14"].exists)
        attach(app, "M2-V01-home-scrolled-L")
        app.swipeDown()
        app.buttons["quran-step-hifz"].tap()
        XCTAssertTrue(app.buttons["تمّ"].waitForExistence(timeout: 5)); app.buttons["تمّ"].tap()
        let deep = app.buttons["quran-level-hifz-deep"]; deep.tap()
        waitSelected(app.buttons["quran-level-hifz-deep"])
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-level-hifz-deep"].waitForExistence(timeout: 20)); waitSelected(app.buttons["quran-level-hifz-deep"])
        app.buttons["quran-level-hifz-medium"].tap()
        app.buttons["quran-begin"].tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        let resume = app.buttons["quran-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), app.debugDescription); resume.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15))
        app.terminate()
    }
    private func waitSelected(_ button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "محدد"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
