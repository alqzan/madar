import XCTest

@MainActor final class DiaryCustomizeUITests: XCTestCase {
    func testShapesLayoutPersistenceSearchResetAndUndo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-customize"].waitForExistence(timeout: 25)); app.buttons["diary-customize"].tap()
        XCTAssertTrue(app.buttons["diary-customize-section-home"].waitForExistence(timeout: 10))
        capture(app, "M3-V04-customize-L")
        let toggle = app.switches["diary-block-days"]; reveal(toggle, app); toggle.tap()
        let echo = app.buttons["option-notes.homeShape-echoes"]; reveal(echo, app); capture(app, "M3-V04-customize-scrolled-L"); echo.tap()
        let back = app.buttons["diary-customize-back"]; reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-echo-1y"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-echo-1y"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["diary-recent-days"].exists)
        app.buttons["diary-customize"].tap()
        let search = app.textFields["diary-customize-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("الهامش")
        let brown = app.buttons["option-notes.secondInk-brown"]; reveal(brown, app); brown.tap()
        search.tap()
        // Clear without relying on the localized edit menu.
        let value = (search.value as? String) ?? ""; search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)); search.typeText("\n")
        let reset = app.buttons["diary-customize-reset"]; reveal(reset, app, down: true); reset.tap()
        XCTAssertTrue(app.buttons["diary-customize-reset-confirm"].firstMatch.waitForExistence(timeout: 5)); app.buttons["diary-customize-reset-confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "undo-button").firstMatch.waitForExistence(timeout: 8))
        let undo = try XCTUnwrap(app.buttons.matching(identifier: "undo-button").allElementsBoundByIndex.first { $0.isHittable }); undo.tap()
        reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-echo-1y"].waitForExistence(timeout: 10))
        app.buttons["diary-customize"].tap()
        let margin = app.buttons["option-notes.homeShape-margin"]; reveal(margin, app); margin.tap()
        reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-add-margin"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<8 where !element.isHittable { if down { app.swipeDown() } else { app.swipeUp() } }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
