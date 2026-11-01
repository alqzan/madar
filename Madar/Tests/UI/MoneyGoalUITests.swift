import XCTest
@MainActor final class MoneyGoalUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ fixture: String = "goal", writeHoldMS: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE":"L", "MADAR_UI_THEME":"light", "MADAR_UI_NOW":"2026-10-17T12:00:00+03:00"]
        if let writeHoldMS { app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"] = String(writeHoldMS) }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10))
        for _ in 0..<12 where !money.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(money.isHittable); money.tap()
        let door = app.buttons["money-goal-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.buttons["money-goal-plan-0"].waitForExistence(timeout: 10)); return app
    }
    func testGoalConfirmationStaysOpenWhileSaving() throws {
        continueAfterFailure = false
        let app = open(writeHoldMS: 5000)
        let create = app.buttons["money-goal-create"]
        for _ in 0..<8 where !create.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(create.isEnabled, app.debugDescription)
        create.tap()
        let confirm = app.buttons["money-goal-confirm"], back = app.buttons["money-goal-back"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertTrue(back.exists); XCTAssertTrue(back.isEnabled)
        shot(app, "M5-V23-confirm-idle-L")
        confirm.tap()
        XCTAssertFalse(confirm.isEnabled); XCTAssertFalse(back.isEnabled)
        shot(app, "M5-V23-confirm-pending-L")
        app.swipeDown()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(confirm.isEnabled); XCTAssertFalse(back.isEnabled)
        XCTAssertTrue(app.buttons["money-goal-open"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertFalse(confirm.exists)
    }
    func testEditablePlansPreviewCreationAndUndo() {
        continueAfterFailure = false
        let app = open(); shot(app,"M5-V23-medium-L")
        app.buttons["money-goal-plan-1"].tap(); XCTAssertTrue(app.staticTexts["money-goal-completion"].exists || app.otherElements["money-goal-completion"].exists)
        let adjust = app.buttons["money-goal-adjust"]; for _ in 0..<4 where !adjust.isHittable { app.swipeUp(velocity: .slow) }; shot(app,"M5-V23-medium-s1-L"); adjust.tap()
        let daily = app.textFields["money-goal-daily"]; XCTAssertTrue(daily.waitForExistence(timeout: 5)); shot(app, "M5-V23-editor-L"); daily.tap(); daily.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "75")
        let done = app.buttons["money-goal-editor-done"]; if !done.isHittable { app.swipeUp() }; done.tap()
        let create = app.buttons["money-goal-create"]; for _ in 0..<4 where !create.isHittable { app.swipeUp(velocity: .slow) }; create.tap()
        let confirm = app.buttons["money-goal-confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 5)); shot(app,"M5-V23-preview-L"); confirm.tap()
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 10)); undo.tap(); XCTAssertTrue(app.buttons["money-goal-open"].exists)
    }
    func testSmallAndLargeYearSuggestionsAndExistingPayments() {
        continueAfterFailure = false
        let app = open()
        func change(_ amount: String) {
            let edit = app.buttons["money-goal-edit"]; for _ in 0..<5 where !edit.isHittable { app.swipeDown(velocity: .slow) }; edit.tap()
            let field = app.textFields["money-goal-amount"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count:14) + amount)
            let done = app.buttons["money-goal-editor-done"]; for _ in 0..<3 where !done.isHittable { app.swipeUp(velocity: .slow) }; done.tap()
        }
        change("2000"); app.buttons["money-goal-plan-0"].tap(); shot(app,"M5-V23-small-L")
        change("80000"); let year = app.buttons["money-goal-year"]; for _ in 0..<4 where !year.isHittable { app.swipeUp(velocity: .slow) }; year.tap(); shot(app,"M5-V23-large-s1-L")
        let paid = app.buttons["money-goal-paid"]; paid.tap(); XCTAssertTrue(app.buttons["money-goal-paid-done"].waitForExistence(timeout:5)); shot(app,"M5-V23-paid-L"); app.buttons["money-goal-paid-done"].tap()
        for _ in 0..<5 where !app.buttons["money-goal-edit"].isHittable { app.swipeDown(velocity:.slow) }; shot(app,"M5-V23-large-L")
    }
}
