import XCTest

/// M5-V07: rules read from data; a conflict becomes a rule with one tap; a merchant moves and is forgotten.
@MainActor final class MoneyRulesUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testConflictMoveAndForget() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "rules",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let open = app.buttons["money-rules-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<4 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()
        let count = app.descendants(matching: .any)["money-rules-count"]; XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(count.label.contains("٥"), count.label)
        let option = app.buttons["money-conflict-option"].firstMatch; XCTAssertTrue(option.exists)
        shot(app, "M5-V07-mer-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V07-mer-s1-L"); app.swipeDown(velocity: .fast)
        option.tap()
        XCTAssertTrue(app.buttons["money-conflict-option"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(count.label.contains("٦"), count.label)
        let rule = app.buttons["money-rule-مقهى الزاوية"]; XCTAssertTrue(rule.waitForExistence(timeout: 5)); rule.tap()
        let move = app.buttons["money-rule-move-بقالة"]; XCTAssertTrue(move.waitForExistence(timeout: 5)); shot(app, "M5-V07-mer-open-L"); move.tap()
        XCTAssertTrue(rule.waitForNonExistence(timeout: 10), "Moved under بقالة")
        app.buttons["money-lantern-بقالة"].tap()
        XCTAssertTrue(rule.waitForExistence(timeout: 5)); rule.tap()
        let forget = app.buttons["money-rule-forget"]; XCTAssertTrue(forget.waitForExistence(timeout: 5)); forget.tap()
        XCTAssertTrue(rule.waitForNonExistence(timeout: 10)); XCTAssertTrue(count.label.contains("٥"), count.label)
    }
}
