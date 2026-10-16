import XCTest

@MainActor final class MoneyLogUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testArcadeMonthSelectionSearchAndSource() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "cards", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let log = app.buttons["money-log-open"]; XCTAssertTrue(log.waitForExistence(timeout: 10)); for _ in 0..<8 where !log.isHittable { app.swipeUp(velocity: .slow) }; log.tap()
        XCTAssertTrue(app.otherElements["money-log-arcade"].waitForExistence(timeout: 10)); shot(app, "M5-V13-log-4-L")
        let movement = app.buttons["money-log-row-متجر الأجهزة"]; XCTAssertTrue(movement.waitForExistence(timeout: 5))
        for _ in 0..<4 where !movement.isHittable { app.swipeUp(velocity: .slow) }; movement.tap()
        XCTAssertTrue(app.staticTexts["خارج الميزانية"].waitForExistence(timeout: 5) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "خارج الميزانية")).firstMatch.exists); shot(app, "M5-V13-log-source-L"); app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let mode = app.buttons["money-log-mode"]; XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.tap()
        XCTAssertTrue(app.otherElements["money-log-month-grid"].waitForExistence(timeout: 5)); shot(app, "M5-V13-log-4x-L")
        let previous = app.buttons["money-log-day-2026-10-15"]; XCTAssertTrue(previous.exists); previous.tap()
        XCTAssertTrue(app.otherElements["money-log-detail"].exists)
        app.swipeDown(velocity: .fast)
        app.buttons["money-log-search-open"].tap()
        let field = app.textFields["money-log-search"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("غيرموجود\n")
        XCTAssertTrue(app.staticTexts["money-log-empty"].waitForExistence(timeout: 5))
        app.buttons["مسح البحث"].tap(); XCTAssertTrue(app.otherElements["money-log-month-grid"].exists)
        app.buttons["money-log-filter-transfers"].tap()
        XCTAssertTrue(app.staticTexts["money-log-empty"].waitForExistence(timeout: 5))
        app.buttons["money-log-filter-all"].tap()
        let restored = app.buttons["money-log-row-مصروف"]
        for _ in 0..<6 where !restored.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        let months = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'money-log-month-'"))
        XCTAssertGreaterThanOrEqual(months.count, 2)
        for _ in 0..<5 where !months.element(boundBy: 0).isHittable { app.swipeDown(velocity: .fast) }
        let currentID = months.element(boundBy: 0).identifier
        months.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["money-log-day-2026-10-16"].waitForNonExistence(timeout: 5))
        app.buttons[currentID].tap()
        XCTAssertTrue(app.buttons["money-log-day-2026-10-16"].waitForExistence(timeout: 5))
    }
}
