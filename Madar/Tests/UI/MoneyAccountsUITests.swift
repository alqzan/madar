import XCTest

@MainActor final class MoneyAccountsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-accounts-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.staticTexts["money-accounts-net"].waitForExistence(timeout: 10)); return app
    }
    func testTreeSourcesProtectedCheckpointAndAddNotMineWithUndo() {
        continueAfterFailure = false
        let app = open("accounts"), net = app.staticTexts["money-accounts-net"]
        let before = net.label; XCTAssertFalse(before.contains("•••")); shot(app, "M5-V19-accounts-L")
        app.buttons["money-account-الحساب الجاري"].tap()
        let name = app.textFields["money-account-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["money-account-owned"].isEnabled)
        XCTAssertFalse(app.textFields["money-account-opening"].isEnabled)
        shot(app, "M5-V19-checkpoint-L")
        app.buttons["money-account-editor-close"].tap()
        app.buttons["money-account-source-الحساب الجاري"].tap()
        XCTAssertTrue(app.staticTexts["رصيد بداية أدخلته"].waitForExistence(timeout: 5)); shot(app, "M5-V19-source-L")
        app.swipeDown(velocity: .fast)
        app.buttons["money-accounts-add"].tap()
        let field = app.textFields["money-account-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("حساب الأسرة")
        let bank = app.textFields["money-account-bank"]; bank.tap(); bank.typeText("مصرف الاختبار")
        app.buttons["money-account-keyboard-done"].tap()
        app.switches["money-account-owned"].tap()
        let opening = app.textFields["money-account-opening"]; opening.tap(); opening.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "1000")
        app.buttons["money-account-keyboard-done"].tap()
        let save = app.buttons["money-account-save"]; for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }; shot(app, "M5-V19-add-L"); save.tap()
        XCTAssertTrue(app.buttons["money-account-حساب الأسرة"].waitForExistence(timeout: 10)); XCTAssertEqual(net.label, before)
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertFalse(app.buttons["money-account-حساب الأسرة"].exists); XCTAssertEqual(net.label, before)
    }
    func testHiddenAndEmpty() {
        continueAfterFailure = false
        let hidden = open("hidden"); XCTAssertTrue(hidden.staticTexts["money-accounts-net"].label.contains("•••")); shot(hidden, "M5-V19-hidden-L")
        hidden.buttons["money-accounts-reveal"].tap(); XCTAssertFalse(hidden.staticTexts["money-accounts-net"].label.contains("•••")); hidden.terminate()
        let empty = open("empty"); XCTAssertTrue(empty.staticTexts["money-accounts-empty"].exists); shot(empty, "M5-V19-empty-L")
    }
}
