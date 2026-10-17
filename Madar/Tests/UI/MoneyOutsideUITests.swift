import XCTest
@MainActor final class MoneyOutsideUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testLobbyHiddenWidgetAndExpenseControlShareTheBuiltMoneyRoom() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MONEY_FIXTURE":"expense","MADAR_UI_HABIT_FIXTURE":"showcase","MADAR_UI_NOW":"2026-10-17T12:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"]
        app.launch(); let lobby = app.tabBars.buttons["البهو"]; XCTAssertTrue(lobby.waitForExistence(timeout:20)); lobby.tap()
        let money = app.otherElements["bahw-block-mal"]; XCTAssertTrue(money.waitForExistence(timeout:10)); shot(app,"M5-X01-lobby-L")
        for _ in 0..<4 where !money.isHittable { app.swipeUp(velocity:.slow) }; for _ in 0..<3 where money.frame.maxY > app.frame.height - 100 { app.swipeUp(velocity: .slow) }; shot(app,"M5-X01-lobby-s1-L"); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout:10)); app.buttons["money-back"].tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout:5)); search.tap(); search.typeText("خارج التطبيق"); app.buttons["room-widgets-gallery"].tap()
        let widget = app.descendants(matching: .any).matching(identifier: "room-widget-money").firstMatch; XCTAssertTrue(widget.waitForExistence(timeout:5)); for _ in 0..<5 where !widget.isHittable { app.swipeUp(velocity:.slow) }; XCTAssertTrue((widget.label + widget.staticTexts.allElementsBoundByIndex.map(\.label).joined()).contains("•••"), widget.debugDescription); for _ in 0..<3 where widget.frame.maxY > app.frame.height - 60 { app.swipeUp(velocity: .slow) }; shot(app,"M5-X01-widget-L")
        let lock = app.buttons["room-widgets-lock"]; for _ in 0..<6 where !lock.isHittable { app.swipeDown(velocity:.slow) }; lock.tap(); XCTAssertTrue(app.staticTexts["lock-widgets-title"].waitForExistence(timeout:5)); shot(app,"M5-X01-lock-L")
        let control = app.buttons["control-preview-money"]; for _ in 0..<5 where !control.isHittable { app.swipeUp(velocity:.slow) }; shot(app,"M5-X01-control-L"); control.tap()
        let key = app.buttons["money-expense-key-4"]; XCTAssertTrue(key.waitForExistence(timeout:10)); key.tap(); app.buttons["money-expense-key-2"].tap(); app.buttons["money-expense-merchant-مقهى الزاوية"].tap(); shot(app,"M5-X01-expense-L")
        let save = app.buttons["money-expense-save"]; for _ in 0..<4 where !save.isHittable { app.swipeUp(velocity:.slow) }; save.tap(); let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout:10)); undo.tap()
    }
    func testLargeMoneyBlockShowsOwnedEnvelopesLimitsAndReserve() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MONEY_FIXTURE":"expense","MADAR_UI_MONEY_BLOCK_SIZE":"4x4","MADAR_UI_HABIT_FIXTURE":"showcase","MADAR_UI_NOW":"2026-10-17T12:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"]
        app.launch(); let lobby = app.tabBars.buttons["البهو"]; XCTAssertTrue(lobby.waitForExistence(timeout:20)); lobby.tap()
        let money = app.otherElements["bahw-block-mal"]; XCTAssertTrue(money.waitForExistence(timeout:10))
        for _ in 0..<5 where money.frame.maxY > app.frame.height - 90 { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(money.staticTexts["الاحتياطي"].exists); XCTAssertTrue(money.staticTexts["الإيجار"].exists); XCTAssertTrue(money.staticTexts["المحجوز"].exists)
        shot(app,"M5-X01-lobby-large-L")
    }

}
