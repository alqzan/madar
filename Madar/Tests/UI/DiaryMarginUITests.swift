import XCTest

@MainActor final class DiaryMarginUITests: XCTestCase {
    func testMarginHasOriginalDatedReplyAndTodayReferenceAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "margin", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-add-margin"].waitForExistence(timeout: 25))
        capture(app, "M3-V03-margin-L")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43)))
        capture(app, "M3-V03-margin-scrolled-L")
        app.swipeDown()
        app.buttons["diary-another-memory"].tap()
        XCTAssertTrue(app.staticTexts["مشينا بعد المغرب، والجو صار يحتمل."].waitForExistence(timeout: 8))
        app.buttons["diary-add-margin"].tap()
        let text = app.textViews["diary-editor-text"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.typeText("ما زلت أذكر ذلك المساء.")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["ما زلت أذكر ذلك المساء."].waitForExistence(timeout: 10))
        capture(app, "M3-V03-dated-reply-L")
        app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ما زلت أذكر ذلك المساء.")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-another-memory"].waitForExistence(timeout: 25)); app.buttons["diary-another-memory"].tap()
        XCTAssertTrue(app.staticTexts["ما زلت أذكر ذلك المساء."].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
