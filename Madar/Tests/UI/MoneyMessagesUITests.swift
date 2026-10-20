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

    func testSalarySourceIsLearnedOnlyAfterConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "salarySourceFlow",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-27T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["راتب مقترح"].exists, "The source has not been learned before the owner's first confirmation")

        let firstIncoming = app.descendants(matching: .any)["money-draft-confirm"].firstMatch
        XCTAssertTrue(firstIncoming.waitForExistence(timeout: 10), app.debugDescription); firstIncoming.tap()
        let chooseSalary = app.buttons["اعتبره راتبًا"]; XCTAssertTrue(chooseSalary.waitForExistence(timeout: 5), app.debugDescription); chooseSalary.tap()
        let salaryConfirm = app.buttons["money-salary-confirm"]; XCTAssertTrue(salaryConfirm.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !salaryConfirm.isHittable { app.swipeUp(velocity: .slow) }
        salaryConfirm.tap()

        let firstSuggestion = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "راتب مقترح")).firstMatch
        XCTAssertTrue(firstSuggestion.waitForExistence(timeout: 10), app.debugDescription)

        // A fresh app session clears the transient undo banner while proving the learned source persisted.
        app.terminate(); app.launchEnvironment["MADAR_UI_NOW"] = "2026-10-27T20:11:00+03:00"; app.launch()
        let resumedTab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(resumedTab.waitForExistence(timeout: 20)); resumedTab.tap()
        let resumedSearch = app.textFields["settings-search"]; XCTAssertTrue(resumedSearch.waitForExistence(timeout: 10)); resumedSearch.tap(); resumedSearch.typeText("المال")
        let resumedMoney = app.buttons["money-open"]; XCTAssertTrue(resumedMoney.waitForExistence(timeout: 5)); resumedMoney.tap()
        let resumedTray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(resumedTray.waitForExistence(timeout: 10)); resumedTray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        let suggestion = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "راتب مقترح")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 { app.swipeDown(velocity: .slow) }
        shot(app, "M5-V27-msg-salary-source-L")
        let suggestionCard = app.otherElements["money-draft-شركة المدار"].firstMatch
        let suggestedMenu = suggestionCard.buttons["money-draft-confirm"]
        XCTAssertTrue(suggestedMenu.waitForExistence(timeout: 5)); suggestedMenu.tap()
        XCTAssertTrue(app.buttons["راجع الراتب المقترح"].waitForExistence(timeout: 5))
        let incomeChoice = app.buttons["اعتمده كدخل"]; XCTAssertTrue(incomeChoice.exists); incomeChoice.tap()
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 10), "A salary suggestion can still be explicitly confirmed as ordinary income")
    }
}
