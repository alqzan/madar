import XCTest

/// M5-V08: ✓ on a salary draft opens «نزل الراتب»; the report reads the same plan the command writes, and
/// «اعتمد الراتب وافتح الدورة» opens the cycle and clears the draft.
@MainActor final class MoneySalaryUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testSalaryReportOpensTheCycle() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "salary",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-27T09:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let draft = app.descendants(matching: .any)["money-draft-راتب"]; XCTAssertTrue(draft.waitForExistence(timeout: 10), app.debugDescription)
        draft.buttons["money-draft-confirm"].tap()
        let cycle = app.staticTexts["money-salary-cycle"]; XCTAssertTrue(cycle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(cycle.label.hasPrefix("دورة "), cycle.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-salary-rating"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-salary-carry"].exists, "The closing cycle's carry is shown")
        shot(app, "M5-V08-sal-L")
        let entry = app.buttons["money-salary-entry-dailies"]; app.swipeUp(velocity: .slow); for _ in 0..<3 where !entry.isHittable { app.swipeUp(velocity: .slow) }
        entry.tap(); XCTAssertTrue(app.staticTexts["money-salary-explanation"].waitForExistence(timeout: 5))
        entry.tap(); app.swipeUp(velocity: .slow)
        shot(app, "M5-V08-sal-s1-L")
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
        XCTAssertTrue(app.descendants(matching: .any)["money-salary-history"].exists)
        shot(app, "M5-V08-sal-s2-L")
        let confirm = app.buttons["money-salary-confirm"]; for _ in 0..<4 where !confirm.isHittable { app.swipeDown(velocity: .slow) }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(draft.waitForNonExistence(timeout: 10), "The salary is confirmed and leaves the review list")
    }
}
