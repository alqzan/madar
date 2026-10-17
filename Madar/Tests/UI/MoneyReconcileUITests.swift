import XCTest

@MainActor final class MoneyReconcileUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openReconcile(fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let open = app.buttons["money-reconcile-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); for _ in 0..<10 where !open.isHittable { app.swipeUp(velocity: .slow) }; open.tap()
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testRecordNameTheDifferencesAndSettleInOneUndo() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcile")
        // The newest bank message printed a balance 320 below the book; the line opens on it, and a 320 draft is named.
        let sentence = element(app, "money-reconcile-sentence"); XCTAssertTrue(sentence.waitForExistence(timeout: 10))
        XCTAssertTrue(sentence.label.contains("عندك أقل"), sentence.label)
        XCTAssertTrue(element(app, "money-reconcile-delta").label.contains("٣٢٠"))
        XCTAssertTrue(element(app, "money-reconcile-from-message").exists)
        XCTAssertTrue(element(app, "money-reconcile-hint").exists, "The difference equals the waiting draft")
        XCTAssertTrue(element(app, "money-reconcile-status").label.contains("مرّ"))
        XCTAssertFalse(app.buttons["money-reconcile-name-missedSpend"].isSelected, "No name is chosen for the user")
        app.buttons["money-reconcile-name-missedSpend"].tap()
        XCTAssertTrue(element(app, "money-reconcile-name-caption").label.contains("أخرى"))
        // The wallet matches the bank; the travel card owes 120 more.
        app.buttons["money-reconcile-row-المحفظة الرقمية"].tap()
        app.buttons["money-reconcile-nudge-10"].tap(); app.buttons["money-reconcile-nudge--10"].tap()
        XCTAssertTrue(element(app, "money-reconcile-sentence").label.contains("يطابق"))
        app.buttons["money-reconcile-row-بطاقة السفر"].tap()
        for step in ["100", "10", "10"] { app.buttons["money-reconcile-nudge-" + step].tap() }
        XCTAssertTrue(element(app, "money-reconcile-sentence").label.contains("عليك أكثر"))
        XCTAssertTrue(app.buttons["money-reconcile-name-missedSpend"].exists, "A card that owes more can be missed spending")
        app.buttons["money-reconcile-name-unexplained"].tap()
        app.buttons["money-reconcile-row-الحساب الجاري"].tap()
        XCTAssertTrue(app.buttons["money-reconcile-name-missedSpend"].isSelected)
        XCTAssertTrue(app.buttons["money-reconcile-save"].label.contains("تسويتان"), app.buttons["money-reconcile-save"].label)
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["money-reconcile-close"].waitForExistence(timeout: 5)); sleep(1)
        shot(app, "M5-V15-rec-L")
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(element(app, "money-reconcile-open-count").label.contains("٠"))
        shot(app, "M5-V15-rec-s1-L")
        app.buttons["money-reconcile-save"].tap()
        // Written: the book now matches, the line starts afresh and the record is dated today.
        let status = element(app, "money-reconcile-status")
        let settled = NSPredicate(format: "label CONTAINS %@", "آخر مطابقة")
        expectation(for: settled, evaluatedWith: status); waitForExpectations(timeout: 10)
        XCTAssertFalse(element(app, "money-reconcile-hint").exists)
        app.swipeDown(velocity: .fast)
        shot(app, "M5-V15-rec-saved-L")
    }

    func testHiddenAmountsAndEmptyStore() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcileHidden")
        let expected = element(app, "money-reconcile-expected"); XCTAssertTrue(expected.waitForExistence(timeout: 10))
        XCTAssertTrue(expected.label.contains("•••"))
        XCTAssertFalse(app.buttons["money-reconcile-nudge-10"].isEnabled, "Nothing is edited while amounts are hidden")
        XCTAssertFalse(app.buttons["money-reconcile-save"].isEnabled)
        XCTAssertFalse(app.buttons["money-reconcile-name-missedSpend"].isEnabled)
        shot(app, "M5-V15-hidden-L")
        app.buttons["money-reconcile-reveal"].tap()
        XCTAssertFalse(element(app, "money-reconcile-expected").label.contains("•••"))
        app.terminate()

        let empty = openReconcile(fixture: "empty")
        XCTAssertTrue(element(empty, "money-reconcile-empty").waitForExistence(timeout: 10))
        XCTAssertFalse(empty.buttons["money-reconcile-save"].exists)
        shot(empty, "M5-V15-empty-L")
    }
}
