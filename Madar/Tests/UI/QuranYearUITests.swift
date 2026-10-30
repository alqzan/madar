import XCTest

@MainActor final class QuranYearUITests: XCTestCase {
    func testYearActivitySwitchAndMonthDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        for _ in 0..<4 { if app.buttons["quran-week-open"].isHittable { break }; app.swipeUp() }
        app.buttons["quran-week-open"].tap(); app.buttons["quran-log-year"].tap()
        XCTAssertTrue(app.staticTexts["quran-year-active"].waitForExistence(timeout: 10))
        capture(app, "M2-V09-year-L")
        app.segmentedControls["quran-year-kind"].buttons["الحفظ"].tap()
        let month = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quran-year-month-")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5)); month.tap()
        XCTAssertTrue(app.buttons["تمّ"].waitForExistence(timeout: 5)); capture(app, "M2-V09-month-L"); app.buttons["تمّ"].tap()
        app.buttons["quran-screen-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10))
    }
    func testFailedYearReloadHidesStaleTotalsAndCanRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_YEAR_READ_FAILURE_AFTER_FIRST": "1"]
        app.launch(); XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-week-open"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap(); app.buttons["quran-log-year"].tap()
        XCTAssertTrue(app.buttons["quran-year-retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["quran-year-active"].exists, "A stale yearly summary must not survive a failed reload.")
        app.buttons["quran-year-retry"].tap()
        XCTAssertTrue(app.staticTexts["quran-year-active"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
