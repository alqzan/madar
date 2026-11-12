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
        XCTAssertFalse(app.descendants(matching: .any)["diary-recent-days"].exists)
        app.buttons["diary-customize"].tap()
        let search = app.textFields["diary-customize-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("الهامش")
        let brown = app.buttons["option-notes.secondInk-brown"]; reveal(brown, app); brown.tap()
        search.tap()
        // Clear without relying on the localized edit menu.
        let value = (search.value as? String) ?? ""; search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)); search.typeText("\n")
        let reset = app.buttons["diary-customize-reset"]; reveal(reset, app, down: true); reset.tap()
        XCTAssertTrue(app.buttons["diary-customize-reset-confirm"].firstMatch.waitForExistence(timeout: 5)); app.buttons["diary-customize-reset-confirm"].firstMatch.tap()
        // Owner 5 Nov: a settings reset is simply done (no undo chip; only removals offer one). The echoes home shape goes back to the default.
        XCTAssertFalse(app.buttons.matching(identifier: "undo-button").firstMatch.waitForExistence(timeout: 2), "A reset shows no undo chip")
        reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10) || app.diaryOpener.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["diary-echo-1y"].exists, "The echoes shape is gone after the reset")
        app.buttons["diary-customize"].tap()
        let margin = app.buttons["option-notes.homeShape-margin"]; reveal(margin, app); margin.tap()
        reveal(back, app, down: true); back.tap()
        XCTAssertTrue(app.buttons["diary-add-margin"].waitForExistence(timeout: 10))
    }
    func testWindowReordersOnlyVisiblePartsAndKeepsMarginOptions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
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
            let year = app.buttons["diary-year-2025-10-15"]
            XCTAssertTrue(days.waitForExistence(timeout: 20)); XCTAssertTrue(year.exists)
            XCTAssertLessThan(days.frame.minY, year.frame.minY)
        }
        checkOrder(); capture(app, "OR-10-days-first-L")
        app.terminate(); app.launch(); checkOrder()
        app.buttons["diary-customize"].tap()
        let echoes = app.buttons["option-notes.homeShape-echoes"]
        reveal(echoes, app); echoes.tap()
        XCTAssertFalse(app.buttons["diary-block-up-days"].exists)
        XCTAssertFalse(app.switches["diary-block-thatDay"].exists)
        let margin = app.buttons["option-notes.homeShape-margin"]
        reveal(margin, app); margin.tap()
        let thatDay = app.switches["diary-block-thatDay"]
        reveal(thatDay, app, down: true)
        XCTAssertTrue(app.switches["diary-block-sinceThatDay"].exists)
        XCTAssertFalse(app.buttons["diary-block-up-days"].exists)
        capture(app, "OR-10-margin-options-L")
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<8 where !element.isHittable { if down { app.swipeDown() } else { app.swipeUp() } }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
