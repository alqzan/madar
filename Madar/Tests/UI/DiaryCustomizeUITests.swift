import XCTest

@MainActor final class DiaryCustomizeUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); return app
    }
    /// 12 Nov: the home shapes are gone (no shape picker), the layout toggles still persist, search and reset still work.
    func testLayoutPersistenceSearchResetAndNoShapePicker() throws {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["diary-customize"].waitForExistence(timeout: 25)); app.buttons["diary-customize"].tap()
        XCTAssertTrue(app.buttons["diary-customize-section-home"].waitForExistence(timeout: 10))
        capture(app, "M3-V04-customize-L")
        XCTAssertFalse(app.buttons["option-notes.homeShape-echoes"].exists || app.buttons["option-notes.homeShape-margin"].exists, "The home has one shape; no picker")
        let toggle = app.switches["diary-block-days"]; reveal(toggle, app); toggle.tap()
        let back = app.buttons["diary-customize-back"]; reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["diary-recent-days"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.descendants(matching: .any)["diary-recent-days"].exists)
        app.buttons["diary-customize"].tap()
        let search = app.textFields["diary-customize-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("الهامش")
        let brown = app.buttons["option-notes.secondInk-brown"]; reveal(brown, app); brown.tap()
        search.tap()
        let value = (search.value as? String) ?? ""; search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)); search.typeText("\n")
        let reset = app.buttons["diary-customize-reset"]; reveal(reset, app, down: true); reset.tap()
        XCTAssertTrue(app.buttons["diary-customize-reset-confirm"].firstMatch.waitForExistence(timeout: 5)); app.buttons["diary-customize-reset-confirm"].firstMatch.tap()
        XCTAssertFalse(app.buttons.matching(identifier: "undo-button").firstMatch.waitForExistence(timeout: 2), "A reset shows no undo chip")
        reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["diary-recent-days"].waitForExistence(timeout: 10), "Reset brings the hidden part back")
    }
    func testWindowReordersOnlyVisibleParts() throws {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["diary-customize"].waitForExistence(timeout: 25)); app.buttons["diary-customize"].tap()
        let parts = app.descendants(matching: .any)["diary-preview-parts"]
        XCTAssertTrue(parts.waitForExistence(timeout: 10)); XCTAssertTrue(parts.label.contains("٣ أجزاء ظاهرة"), parts.label)
        XCTAssertFalse(app.switches["diary-block-thatDay"].exists)
        XCTAssertFalse(app.switches["diary-block-sinceThatDay"].exists)
        capture(app, "OR-10-window-customize-L")
        let upDays = app.buttons["diary-block-up-days"]
        reveal(upDays, app); upDays.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: upDays)], timeout: 8) == .completed)
        let back = app.buttons["diary-customize-back"]
        reveal(back, app, down: true); back.tap()
        func checkOrder() {
            let days = app.descendants(matching: .any)["diary-recent-days"]
            let years = app.descendants(matching: .any)["diary-years"]
            XCTAssertTrue(days.waitForExistence(timeout: 20)); XCTAssertTrue(years.exists)
            XCTAssertLessThan(days.frame.minY, years.frame.minY)
        }
        checkOrder(); capture(app, "OR-10-days-first-L")
        app.terminate(); app.launch(); checkOrder()
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<8 where !element.isHittable { if down { app.swipeDown() } else { app.swipeUp() } }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
