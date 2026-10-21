import XCTest
@MainActor final class MoneyFirstRunUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testFirstRunGuideChecksOnlyNewShortcutIntakeAndManualAccountRoute() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MONEY_FIXTURE":"empty","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout:20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout:10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let guide = app.buttons["money-guide-open"]; XCTAssertTrue(guide.waitForExistence(timeout:10)); shot(app,"M5-V24-first-L"); guide.tap(); XCTAssertTrue(app.staticTexts["تُعدّها مرة لكل بنك"].waitForExistence(timeout:5)); shot(app,"M5-V24-guide-L")
        let start = app.buttons["money-guide-start"]; for _ in 0..<8 where !start.isHittable { app.swipeUp(velocity:.slow) }; start.tap()
        XCTAssertTrue(app.staticTexts["money-guide-status"].label.contains("بانتظار")); app.buttons["money-guide-check"].tap(); XCTAssertTrue(app.staticTexts["money-guide-status"].label.contains("لم تصل")); shot(app,"M5-V24-guide-s1-L")
        let close = app.buttons["money-guide-close"]; for _ in 0..<8 where !close.isHittable { app.swipeDown(velocity:.slow) }; close.tap()
        let account = app.buttons["money-first-account"]; XCTAssertTrue(account.waitForExistence(timeout:5)); account.tap(); XCTAssertTrue(app.buttons["money-accounts-add"].waitForExistence(timeout:5))
    }
}
