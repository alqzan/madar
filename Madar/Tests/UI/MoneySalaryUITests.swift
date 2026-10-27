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
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10))
        for _ in 0..<12 where !tray.isHittable { app.swipeDown(velocity: .slow) }
        tray.tap()
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
        let comparison = app.descendants(matching: .any)["money-salary-daily-comparison"]
        for _ in 0..<4 where !comparison.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(comparison.isHittable)
        XCTAssertTrue(comparison.staticTexts["السابقة"].exists)
        XCTAssertTrue(comparison.staticTexts["هذه الدورة"].exists)
        shot(app, "M5-V08-sal-s1-L")
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
        XCTAssertTrue(app.descendants(matching: .any)["money-salary-history"].exists)
        shot(app, "M5-V08-sal-s2-L")
        let confirm = app.buttons["money-salary-confirm"]; for _ in 0..<4 where !confirm.isHittable { app.swipeDown(velocity: .slow) }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(draft.waitForNonExistence(timeout: 10), "The salary is confirmed and leaves the review list")
    }
    func testDailyComparisonWaitsForMoneyReveal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "salary",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-27T09:00:00+03:00"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("المال\n")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let settings = app.buttons["money-settings-open"]; XCTAssertTrue(settings.waitForExistence(timeout: 10))
        for _ in 0..<12 where !settings.isHittable { app.swipeUp(velocity: .slow) }
        settings.tap()
        let room = app.buttons["money-settings-page-5"]; XCTAssertTrue(room.waitForExistence(timeout: 10)); room.tap()
        let hidden = app.switches["إخفاؤها حتى ألمسها"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 10))
        for _ in 0..<6 where !hidden.isHittable { app.swipeUp(velocity: .slow) }
        if hidden.value as? String != "1" { hidden.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND enabled == true", "1"), object: hidden)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        let close = app.buttons["money-settings-close"]
        for _ in 0..<6 where !close.isHittable { app.swipeDown(velocity: .slow) }
        close.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10))
        for _ in 0..<12 where !tray.isHittable { app.swipeDown(velocity: .slow) }
        tray.tap()
        let draft = app.descendants(matching: .any)["money-draft-راتب"]; XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.buttons["money-draft-confirm"].tap()
        let daily = app.staticTexts["money-salary-daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10)); XCTAssertEqual(daily.label, "•••")
        let comparison = app.descendants(matching: .any)["money-salary-daily-comparison"]
        XCTAssertFalse(comparison.exists, "Hidden money must not expose the relative daily amounts in a chart")
        shot(app, "OR-24-salary-hidden-L")
        let reveal = app.buttons["أظهر الأرقام"]
        for _ in 0..<5 where !reveal.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reveal.isHittable); reveal.tap()
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))
        for _ in 0..<6 where !comparison.isHittable { app.swipeUp(velocity: .slow) }
        shot(app, "OR-24-salary-comparison-revealed-L")
    }

}
