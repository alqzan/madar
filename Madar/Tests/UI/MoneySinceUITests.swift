import XCTest

/// M5-V06: after days away «منذ آخر زيارة» opens first, reads the salary and the silent Shortcut from data, and closes for the day.
@MainActor final class MoneySinceUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testSinceLastVisitOpensFirstThenOnlyOncePerDay() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "since",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        XCTAssertTrue(app.staticTexts["money-since-title"].waitForExistence(timeout: 15), app.debugDescription)
        let headline = app.staticTexts["money-since-headline"]; XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertTrue(headline.label.contains("نزل الراتب") && headline.label.contains("١٥٬٠٠٠"), headline.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-since-silent"].exists, "Last Shortcut message four days ago")
        let secondaryDay = app.staticTexts["money-since-secondary-day-2026-10-16"]
        XCTAssertTrue(secondaryDay.waitForExistence(timeout: 5))
        XCTAssertTrue(secondaryDay.label.contains("١٦"), secondaryDay.label)
        XCTAssertTrue(app.buttons["money-since-day-2026-10-16"].label.contains("أكتوبر"))
        shot(app, "M5-V06-since-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V06-since-s1-L")
        app.swipeUp(velocity: .slow); shot(app, "M5-V06-since-s2-L")
        let done = app.buttons["money-since-done"]; for _ in 0..<3 where !done.isHittable { app.swipeUp(velocity: .slow) }
        done.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10))
        app.buttons["money-back"].tap()
        XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["money-since-title"].waitForExistence(timeout: 3), "Seen today: the home opens directly")
    }
}
