import XCTest

@MainActor final class MoneyHomeUITests: XCTestCase {
    func app(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    func open(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testHomeReadsActualCycleAndHasNoUnbuiltDoors() throws {
        continueAfterFailure = false; let app = app("showcase"); open(app)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("١٤٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("٤٠٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"), app.staticTexts["money-available"].label)
        XCTAssertTrue(app.descendants(matching: .any)["money-scroll-chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-pending"].exists)
        XCTAssertFalse(app.buttons["سجّل مصروفًا"].exists); XCTAssertFalse(app.buttons["التحليل"].exists)
        shot(app, "M5-V01-home-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V01-home-s1-L")
        XCTAssertTrue(app.staticTexts["الالتزامات"].exists)
        app.buttons["money-back"].tap(); XCTAssertTrue(app.buttons["money-open"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app); XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
    }
    func testEmptyAndHiddenAmountsAreHonest() throws {
        continueAfterFailure = false; var app = app("empty"); open(app)
        XCTAssertTrue(app.descendants(matching: .any)["money-empty"].exists); XCTAssertFalse(app.staticTexts["money-available"].exists)
        shot(app, "M5-V01-empty-L"); app.terminate()
        app = self.app("hidden"); open(app)
        XCTAssertEqual(app.staticTexts["money-available"].label, "•••")
        shot(app, "M5-V01-hidden-L"); app.buttons["money-reveal"].tap()
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
        app.buttons["money-back"].tap(); app.buttons["money-open"].tap()
        XCTAssertEqual(app.staticTexts["money-available"].label, "•••")
    }
}
