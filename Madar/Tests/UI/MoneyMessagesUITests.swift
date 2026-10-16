import XCTest

/// M5-V05: synthetic Shortcut messages through the real intake; «اعتمد الواضح» skips the duplicate, the statement
/// updates its card once, and an unread message is ignored from «تحتاج نظرة».
@MainActor final class MoneyMessagesUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testClearDraftsStatementAndLookAreDecidedHere() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "messages",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        let review = app.descendants(matching: .any)["money-messages-review"]
        let clear = app.buttons["money-confirm-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(review.label.contains("٦"), review.label)
        XCTAssertTrue(clear.label.contains("(٣)"), clear.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-draft-duplicate"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-statement"].exists)
        shot(app, "M5-V05-msg-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V05-msg-s1-L")
        for _ in 0..<3 where !clear.isHittable { app.swipeUp(velocity: .slow) }
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 10))
        XCTAssertTrue(review.label.contains("٣"), review.label)
        let spent = app.descendants(matching: .any)["money-messages-spent"]
        XCTAssertTrue(spent.label.contains("٢") && spent.label.contains("٦٠٫٥٠"), spent.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-messages-incoming"].label.contains("١٢٠"))
        app.swipeDown(velocity: .fast)
        let apply = app.buttons["money-statement-apply"]; XCTAssertTrue(apply.waitForExistence(timeout: 5)); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10)); XCTAssertTrue(review.label.contains("٢"), review.label)
        let ignore = app.buttons["money-look-ignore"]; for _ in 0..<3 where !ignore.isHittable { app.swipeUp(velocity: .slow) }
        ignore.tap(); XCTAssertTrue(ignore.waitForNonExistence(timeout: 10))
        XCTAssertTrue(review.label.contains("١"), review.label)
        app.swipeDown(velocity: .fast); shot(app, "M5-V05-msg-decided-L")
    }
}
