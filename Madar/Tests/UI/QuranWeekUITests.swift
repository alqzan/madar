import XCTest

@MainActor final class QuranWeekUITests: XCTestCase {
    func testWeeklyRingsTotalsDayDetailsAndReturnAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-week-open"]
        for _ in 0..<3 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable, app.debugDescription); entry.tap()
        XCTAssertTrue(app.staticTexts["quran-week-hifz"].waitForExistence(timeout: 10))
        XCTAssertEqual(plain(app.staticTexts["quran-week-hifz"].label), "٦ أوجه")
        XCTAssertEqual(plain(app.staticTexts["quran-week-review"].label), "٢٧٠ وجهًا")
        XCTAssertEqual(app.staticTexts["quran-week-work"].label, "٥ من ٦")
        XCTAssertTrue(app.staticTexts["quran-week-closed"].label.contains("١ من ٦"))
        attach(app, "M2-V08-week-L")
        app.swipeUp(); attach(app, "M2-V08-week-scrolled-L"); app.swipeDown()
        app.buttons["quran-week-day-2026-10-14"].tap()
        XCTAssertTrue(app.staticTexts["quran-week-day-review"].waitForExistence(timeout: 5))
        XCTAssertTrue(plain(app.staticTexts["quran-week-day-review"].label).contains("٢٧٠ وجهًا"))
        attach(app, "M2-V08-day-L")
        app.buttons["تمّ"].tap(); app.buttons["quran-week-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10))
        app.terminate()
    }
    func testFailedWeeklyReloadHidesStaleTotalsAndCanRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_WEEK_READ_FAILURE_AFTER_FIRST": "1"]
        app.launch(); XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-week-open"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["quran-week-retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["quran-week-work"].exists, "A stale weekly summary must not survive a failed reload.")
        app.buttons["quran-week-retry"].tap()
        XCTAssertTrue(app.staticTexts["quran-week-hifz"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    private func plain(_ value: String) -> String { String(value.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }) }
    private func attach(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
