import XCTest

@MainActor final class MoneyBudgetUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func open(_ app: XCUIApplication) {
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10)); money.tap()
        let tray = app.buttons["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let budget = app.buttons["money-budget-open"]; XCTAssertTrue(budget.waitForExistence(timeout: 10))
        for _ in 0..<6 where !budget.isHittable { app.swipeUp(velocity: .slow) }
        budget.tap()
        XCTAssertTrue(app.staticTexts["money-budget-excluded-total"].waitForExistence(timeout: 10))
    }
    func testStampLiftUndoAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "budget", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        open(app)
        let row = app.buttons["money-budget-row-مقهى الزاوية"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let dailyBefore = app.staticTexts["money-budget-daily-total"].label
        shot(app, "M5-V11-ign-before-L")
        for _ in 0..<4 where !row.isHittable { app.swipeUp(velocity: .slow) }
        row.tap()
        let confirm = app.buttons["money-budget-confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot(app, "M5-V11-ign-b-L")
        app.buttons["إلغاء"].tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5)); XCTAssertTrue(row.label.contains("داخل الميزانية"))
        row.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10)); XCTAssertTrue(row.label.contains("خارج الميزانية"), row.label)
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "داخل الميزانية").evaluate(with: row))
        row.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))
        app.terminate(); open(app)
        XCTAssertTrue(row.label.contains("خارج الميزانية"), row.label)
        shot(app, "M5-V11-ign-L")
        XCTAssertNotEqual(app.staticTexts["money-budget-daily-total"].label, dailyBefore)
        for _ in 0..<4 where !row.isHittable { app.swipeUp(velocity: .slow) }; row.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertTrue(confirm.label.contains("ارفع الختم")); confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10)); XCTAssertTrue(row.label.contains("داخل الميزانية"))
        app.swipeDown(velocity: .fast)
        XCTAssertEqual(app.staticTexts["money-budget-daily-total"].label, dailyBefore)
    }
}
