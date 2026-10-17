import XCTest

@MainActor final class MoneyExpenseUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openExpense(_ fixture: String = "expense") -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-expense-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.buttons["money-expense-key-4"].waitForExistence(timeout: 10)); return app
    }
    func testCalculatorSplitSaveAndUndo() {
        continueAfterFailure = false
        let app = openExpense()
        XCTAssertFalse(app.buttons["money-expense-save"].isEnabled)
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap()
        app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        let after = app.staticTexts["money-expense-after"]; XCTAssertTrue(after.waitForExistence(timeout: 5)); let before = after.label
        shot(app, "M5-V17-add-L")
        app.buttons["money-expense-share-quarter"].tap()
        XCTAssertNotEqual(after.label, before)
        app.buttons["money-expense-diary"].tap()
        shot(app, "M5-V17-split-L")
        let save = app.buttons["money-expense-save"]; for _ in 0..<3 where !save.isHittable { app.swipeUp(velocity: .slow) }; save.tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 10))
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        app.buttons["money-expense-open"].tap()
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap(); app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        XCTAssertEqual(app.staticTexts["money-expense-after"].label, before)
        app.buttons["money-expense-method-كاش"].tap()
        XCTAssertTrue(app.staticTexts["احتُسب عند السحب؛ لن يُخصم من يومك مرة أخرى."].exists)
        shot(app, "M5-V17-cash-L")
    }
    func testEmptyStoreExplainsPaymentSource() {
        continueAfterFailure = false
        let app = openExpense("empty")
        XCTAssertTrue(app.staticTexts["أضف حسابًا أو بطاقة من رسائل البنك أولًا."].exists)
        app.buttons["money-expense-key-4"].tap(); XCTAssertFalse(app.buttons["money-expense-save"].isEnabled)
        shot(app, "M5-V17-empty-L")
    }
}
