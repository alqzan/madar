import XCTest

@MainActor final class MoneySettingsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-settings-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<12 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.staticTexts["money-settings-preview"].waitForExistence(timeout: 10)); return app
    }
    private func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) { for _ in 0..<6 where !element.isHittable { if up { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .fast) } } }
    func testDailyTomorrowUndoFlexibleCycleAndBigThreshold() {
        continueAfterFailure = false
        let app = open("expense"), preview = app.staticTexts["money-settings-preview"]
        XCTAssertTrue(preview.label.contains("٤٠٠")); shot(app, "M5-V20-daily-L")
        app.buttons["money-settings-plus"].tap(); XCTAssertTrue(preview.label.contains("٤١٠"))
        let save = app.buttons["money-settings-daily-save"]; reach(save, app: app); save.tap()
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "٤٠٠"), evaluatedWith: preview); waitForExpectations(timeout: 5)
        let cycle = app.buttons["money-settings-page-2"]; reach(cycle, app: app, up: false); cycle.tap(); shot(app, "M5-V20-cycle-L")
        let flexible = app.switches["money-settings-flexible"]; reach(flexible, app: app); flexible.tap()
        XCTAssertTrue(app.datePickers["money-settings-first-date"].exists); shot(app, "M5-V20-flexible-L")
        let cycleSave = app.buttons["money-settings-cycle-save"]; reach(cycleSave, app: app); cycleSave.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: flexible); waitForExpectations(timeout: 5)
        let room = app.buttons["money-settings-page-5"]; reach(room, app: app, up: false); room.tap()
        let rule = app.segmentedControls["money-settings-big-rule"]; XCTAssertTrue(rule.waitForExistence(timeout: 5)); rule.buttons["مبلغ"].tap()
        let amount = app.textFields["money-settings-big-amount"]; XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        let n = (amount.value as? String)?.count ?? 7; amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: n) + "1200.50")
        app.buttons["money-settings-keyboard-done"].tap()
        let bigSave = app.buttons["money-settings-big-save"]; reach(bigSave, app: app); bigSave.tap()
        let threshold = app.staticTexts["money-settings-big-threshold"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "٥٠"), evaluatedWith: threshold); waitForExpectations(timeout: 5)
        shot(app, "M5-V20-threshold-L")
        let reset = app.buttons["money-settings-reset"]; reach(reset, app: app); reset.tap()
        expectation(for: NSPredicate(format: "selected == 1"), evaluatedWith: rule.buttons["يوميات"]); waitForExpectations(timeout: 5)
    }
    func testHiddenAndUnsetDaily() {
        continueAfterFailure = false
        let hidden = open("hidden"); XCTAssertTrue(hidden.staticTexts["money-settings-preview"].label.contains("•••")); XCTAssertFalse(hidden.textFields["money-settings-allowance"].exists); shot(hidden, "M5-V20-hidden-L"); hidden.terminate()
        let empty = open("empty"); XCTAssertFalse(empty.buttons["money-settings-daily-save"].isEnabled); shot(empty, "M5-V20-unset-L")
    }
}
