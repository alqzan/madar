import XCTest

@MainActor final class MoneySettingsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ fixture: String, writeHoldMS: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        if let writeHoldMS { app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"] = String(writeHoldMS) }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10)); money.tap()
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
    func testSettingsStayOpenWhileSaving() {
        continueAfterFailure = false
        let app = open("expense", writeHoldMS: 5000)
        let preview = app.staticTexts["money-settings-preview"]
        let close = app.buttons["money-settings-close"]
        XCTAssertTrue(preview.label.contains("٤٠٠")); XCTAssertTrue(close.isEnabled)
        shot(app, "M5-V20-settings-save-idle-L")
        app.buttons["money-settings-plus"].tap()
        XCTAssertTrue(preview.label.contains("٤١٠"))
        let save = app.buttons["money-settings-daily-save"]; reach(save, app: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertFalse(save.isEnabled); XCTAssertFalse(close.isEnabled)
        shot(app, "M5-V20-settings-save-pending-L")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(preview.waitForExistence(timeout: 2)); XCTAssertFalse(close.isEnabled)
        let closeEnabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [closeEnabled], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5))
    }
    func testBigExpenseDraftSurvivesFigureStyleChange() throws {
        continueAfterFailure = false
        let app = open("expense")
        let room = app.buttons["money-settings-page-5"]; reach(room, app: app, up: false); room.tap()
        let rule = app.segmentedControls["money-settings-big-rule"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5)); rule.buttons["مبلغ"].tap()
        let amount = app.textFields["money-settings-big-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        let count = (amount.value as? String)?.count ?? 7
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + "1200.50")
        let done = app.buttons["money-settings-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        let draft = try XCTUnwrap(amount.value as? String)
        let style = app.segmentedControls["money-settings-figure-style"]
        XCTAssertTrue(style.waitForExistence(timeout: 5)); reach(style, app: app)
        let modern = style.buttons["حديثة"]
        modern.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == 1"), object: modern)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        XCTAssertEqual(amount.value as? String, draft, "Changing a display-only setting must keep the unsaved threshold draft.")
        shot(app, "AU-80-big-expense-draft-kept-L")
        app.terminate()
    }
}
