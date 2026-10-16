import XCTest

/// M5-V10: categories and limits open from the money home's limits block; a raised limit is saved and shown.
@MainActor final class MoneyCategoriesUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testShelvesAndLimitEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()
        let shelf = app.buttons["money-shelf-مطاعم"]; XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "M5-V10-cat-L")
        let value = app.staticTexts["money-limit-value"], save = app.buttons["money-limit-save"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }
        let before = value.label
        app.buttons["money-limit-plus"].tap()
        XCTAssertNotEqual(value.label, before)
        shot(app, "M5-V10-cat-s1-L")
        app.buttons["money-limit-save"].tap()
        app.swipeDown(velocity: .slow); app.swipeDown(velocity: .slow)
        let saved = app.buttons["money-shelf-مطاعم"]
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "٣٬١٠٠").evaluate(with: saved) || saved.label.contains("3,100") || saved.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("٣٬١٠٠") }, saved.debugDescription)
    }
}
