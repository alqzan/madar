import XCTest

@MainActor final class DiaryWindowUITests: XCTestCase {
    private func launch(_ variant: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": variant,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        return app
    }
    func testWindowYearsMarginTodayAndRelaunch() throws {
        continueAfterFailure = false
        let app = launch("home")
        let currentMonth = app.descendants(matching: .any)["diary-current-month"]
        XCTAssertTrue(currentMonth.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(currentMonth.label.contains("أكتوبر"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("ربيع"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("جمادى"), currentMonth.label)
        XCTAssertTrue(app.buttons["diary-year-2025-10-15"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "M3-V01-window-L")
        // OR-10: one card per past year, newest first; a card opens that day, whose «اكتب في هامشها» writes the margin.
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].exists, app.debugDescription)
        XCTAssertLessThan(app.buttons["diary-year-2025-10-15"].frame.minY, app.buttons["diary-year-2024-10-15"].frame.minY)
        XCTAssertFalse(app.buttons["diary-year-previous"].exists)
        app.swipeUp()
        capture(app, "M3-V01-window-scrolled-L")
        app.swipeDown()
        app.buttons["diary-year-2024-10-15"].tap()
        XCTAssertTrue(app.staticTexts["مشينا بعد المغرب، والجو صار يحتمل."].waitForExistence(timeout: 8))
        let margin = app.buttons["diary-day-write"]
        XCTAssertTrue(margin.waitForExistence(timeout: 8)); XCTAssertTrue(margin.label.contains("هامش"), margin.label); margin.tap()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("هامش من يومي")
        capture(app, "M3-V01-margin-editor-L")
        app.buttons["diary-editor-save"].tap()
        if app.buttons["diary-day-close"].waitForExistence(timeout: 5) { app.buttons["diary-day-close"].tap() }
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "هامش من يومي")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap()
        app.buttons["diary-write"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("سطر محفوظ من اليوم")
        capture(app, "M3-V01-text-editor-L")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["سطر محفوظ من اليوم"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-today-L")
    }
    func testFirstDayHasWorkingOneTapKeyboardAndCancelWritesNothing() throws {
        continueAfterFailure = false
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["صفحتك الأولى"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-first-day-L")
        app.buttons["diary-write"].tap()
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textViews["diary-editor-text"].typeText("لن يحفظ")
        app.buttons["diary-editor-cancel"].tap()
        app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["صفحة تنتظر سطرك."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["لن يحفظ"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
