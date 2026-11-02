import XCTest

/// Owner revision: every purchase chooses independently; merchant rules are not shown as a money-room feature.
@MainActor final class MoneyRulesUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testMoneyMessagesExplainPerPurchaseCategoryAndHideMerchantRulesDoor() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "rules",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertFalse(app.buttons["money-rules-open"].exists)
        let perPurchase = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لكل عملية تصنيفها")).firstMatch
        for _ in 0..<8 where !perPurchase.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(perPurchase.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M5-per-purchase-category-copy-L")
    }
}
