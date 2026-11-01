import XCTest

@MainActor final class MoneyBigExpenseUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testMixedInstallmentsReserveAndAtomicUndo() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-expense-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.buttons["money-expense-key-4"].waitForExistence(timeout: 10))
        for key in ["4", "8", "0", "0"] { app.buttons["money-expense-key-" + key].tap() }
        app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        let save = app.buttons["money-expense-save"]; for _ in 0..<3 where !save.isHittable { app.swipeUp(velocity: .slow) }; save.tap()
        XCTAssertTrue(app.buttons["money-big-mode-mixed"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["money-big-effect"].label.contains("لا يقل"))
        shot(app, "M5-V18-mixed-L")
        app.buttons["money-big-mode-installments"].tap(); shot(app, "M5-V18-installments-L")
        app.buttons["money-big-envelope-الطوارئ"].tap()
        XCTAssertTrue(app.buttons["money-big-save"].isEnabled)
        app.buttons["money-big-mode-reserve"].tap(); XCTAssertTrue(app.staticTexts["money-big-effect"].label.contains("يبقى"))
        shot(app, "M5-V18-reserve-L")
        app.buttons["money-big-mode-mixed"].tap()
        let adopt = app.buttons["money-big-save"]; for _ in 0..<4 where !adopt.isHittable { app.swipeUp(velocity: .slow) }; adopt.tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 10))
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertFalse(app.buttons["money-big-save"].exists)
    }

    func testBigExpenseCoverStaysOpenWhileSaving() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00", "MADAR_UI_MONEY_WRITE_HOLD_MS": "5000"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-expense-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.buttons["money-expense-key-4"].waitForExistence(timeout: 10))
        for key in ["4", "8", "0", "0"] { app.buttons["money-expense-key-" + key].tap() }
        app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        let expenseSave = app.buttons["money-expense-save"]; for _ in 0..<3 where !expenseSave.isHittable { app.swipeUp(velocity: .slow) }; expenseSave.tap()
        let mode = app.buttons["money-big-mode-mixed"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription)
        let close = app.buttons["money-big-close"]
        let save = app.buttons["money-big-save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(close.isEnabled); XCTAssertTrue(save.isEnabled)
        shot(app, "M5-V18-big-save-idle-L")
        save.tap()
        XCTAssertTrue(mode.exists, app.debugDescription)
        XCTAssertFalse(close.isEnabled); XCTAssertFalse(save.isEnabled)
        shot(app, "M5-V18-big-save-pending-L")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        XCTAssertTrue(mode.exists, app.debugDescription)
        XCTAssertFalse(close.isEnabled); XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(mode.waitForNonExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(door.waitForExistence(timeout: 5))
    }
}
