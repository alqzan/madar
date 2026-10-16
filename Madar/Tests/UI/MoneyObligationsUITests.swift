import XCTest

/// M5-V09: the obligations room opens from the money home; adding a bill puts it on its shelf.
@MainActor final class MoneyObligationsUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testObligationsThreadLadderShelvesAndAdd() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-obligations-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()
        let total = app.staticTexts["money-obligations-total"]; XCTAssertTrue(total.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["money-obligation-detail"].exists)
        shot(app, "M5-V09-obl-L")
        app.swipeUp(velocity: .slow); shot(app, "M5-V09-obl-s1-L")
        XCTAssertTrue(app.descendants(matching: .any)["money-ladder"].exists)
        let add = app.buttons["money-obligations-add"]; for _ in 0..<3 where !add.isHittable { app.swipeUp(velocity: .slow) }
        add.tap()
        let name = app.textFields["money-obligation-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("الماء")
        let amount = app.textFields["money-obligation-amount"]; amount.tap(); amount.typeText("85")
        XCTAssertTrue(app.descendants(matching: .any)["money-obligation-preview"].waitForExistence(timeout: 5))
        shot(app, "M5-V09-add-L")
        app.buttons["money-obligation-save"].tap()
        let row = app.buttons["money-obligation-row-الماء"]; XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !row.isHittable { app.swipeUp(velocity: .slow) }
        shot(app, "M5-V09-obl-s2-L")
    }
}
