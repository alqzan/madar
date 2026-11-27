import XCTest

@MainActor final class MoneyReconcileUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openReconcile(fixture: String, writeHoldMS: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        if let writeHoldMS { app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"] = String(writeHoldMS) }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        // The settings home lists rooms by their doors now; the search still offers the money room itself (as MoneyAccountsUITests).
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10)); money.tap()
        let open = app.buttons["money-reconcile-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); for _ in 0..<10 where !open.isHittable { app.swipeUp(velocity: .slow) }; open.tap()
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func selectAccount(_ name: String, in app: XCUIApplication) {
        let account = app.buttons["money-reconcile-row-" + name]
        revealAboveSave(account, in: app)
        account.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selected = app.buttons["money-reconcile-account"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", name), object: selected)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, app.debugDescription)
    }
    private func revealAboveSave(_ element: XCUIElement, in app: XCUIApplication) {
        let save = app.buttons["money-reconcile-save"]
        // iOS 27 lists a full-screen «شريط الأدوات» above the sheet, so XCUITest calls rows under it not hittable although
        // a finger reaches them (checked by hand, 27 Nov): require the row on screen and above the pinned save instead.
        func clear() -> Bool { element.exists && element.frame.minY > 60 && element.frame.midY < save.frame.minY }
        for _ in 0..<8 where !clear() { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertGreaterThan(element.frame.minY, 60, app.debugDescription)
        XCTAssertLessThan(element.frame.midY, save.frame.minY, app.debugDescription)
    }

    func testRecordNameTheDifferencesAndSettleInOneUndo() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcile")
        // The newest bank message printed a balance 320 below the book; the line opens on it, and a 320 draft is named.
        let sentence = element(app, "money-reconcile-sentence"); XCTAssertTrue(sentence.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab-customize"].exists, "The room bar must clear the pinned save button while matching.")
        XCTAssertTrue(app.buttons["money-reconcile-save"].isHittable)
        XCTAssertTrue(sentence.label.contains("عندك أقل"), sentence.label)
        XCTAssertTrue(element(app, "money-reconcile-delta").label.contains("٣٢٠"))
        XCTAssertTrue(element(app, "money-reconcile-from-message").exists)
        XCTAssertTrue(element(app, "money-reconcile-hint").exists, "The difference equals the waiting draft")
        XCTAssertTrue(element(app, "money-reconcile-status").label.contains("مرّ"))
        XCTAssertFalse(app.buttons["money-reconcile-name-missedSpend"].isSelected, "No name is chosen for the user")
        app.buttons["money-reconcile-name-missedSpend"].tap()
        XCTAssertTrue(element(app, "money-reconcile-name-caption").label.contains("أخرى"))
        // The wallet matches the bank; the travel card owes 120 more.
        selectAccount("المحفظة الرقمية", in: app)
        app.buttons["money-reconcile-nudge-10"].tap(); app.buttons["money-reconcile-nudge--10"].tap()
        XCTAssertTrue(sentence.label.contains("يطابق"), sentence.label)
        selectAccount("بطاقة السفر", in: app)
        for step in ["100", "10", "10"] { app.buttons["money-reconcile-nudge-" + step].tap() }
        XCTAssertTrue(element(app, "money-reconcile-sentence").label.contains("عليك أكثر"))
        XCTAssertTrue(app.buttons["money-reconcile-name-missedSpend"].exists, "A card that owes more can be missed spending")
        app.buttons["money-reconcile-name-unexplained"].tap()
        selectAccount("الحساب الجاري", in: app)
        XCTAssertTrue(app.buttons["money-reconcile-name-missedSpend"].isSelected)
        XCTAssertTrue(app.buttons["money-reconcile-save"].label.contains("تسويتان"), app.buttons["money-reconcile-save"].label)
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["money-reconcile-close"].waitForExistence(timeout: 5))
        shot(app, "M5-V15-rec-L")
        let openCount = element(app, "money-reconcile-open-count")
        revealAboveSave(openCount, in: app)
        XCTAssertTrue(openCount.label.contains("لا فروق مفتوحة"))
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

    func testReconciliationStaysOpenWhileSaving() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcile", writeHoldMS: 5000)
        let close = app.buttons["money-reconcile-close"]
        let save = app.buttons["money-reconcile-save"]
        XCTAssertTrue(close.exists); XCTAssertTrue(close.isEnabled)
        XCTAssertTrue(app.buttons["money-reconcile-name-missedSpend"].exists)
        app.buttons["money-reconcile-name-missedSpend"].tap()
        XCTAssertTrue(save.isEnabled)
        shot(app, "M5-V15-reconcile-save-idle-L")
        save.tap()
        XCTAssertFalse(close.isEnabled); XCTAssertFalse(save.isEnabled)
        shot(app, "M5-V15-reconcile-save-pending-L")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        XCTAssertTrue(close.exists); XCTAssertFalse(close.isEnabled); XCTAssertFalse(save.isEnabled)
        let status = element(app, "money-reconcile-status")
        let settled = NSPredicate(format: "label CONTAINS %@", "آخر مطابقة")
        expectation(for: settled, evaluatedWith: status); waitForExpectations(timeout: 12)
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: close)
        waitForExpectations(timeout: 5)
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

    func testProviderDifferenceRemainsAnOpenScheduleReview() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcile")
        let tamara = app.buttons["money-reconcile-row-تمارا"]
        XCTAssertTrue(tamara.waitForExistence(timeout: 10))
        for _ in 0..<8 where !tamara.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(tamara.isHittable)
        XCTAssertTrue(tamara.label.contains("١٬٢٠٠"), tamara.label)
        tamara.tap()
        let providerField = element(app, "money-reconcile-bank-field")
        XCTAssertTrue(providerField.waitForExistence(timeout: 5))
        providerField.tap(); providerField.typeText("1250.00")
        XCTAssertTrue(element(app, "money-reconcile-sentence").label.contains("المزود يطلب أكثر"))
        XCTAssertTrue(element(app, "money-reconcile-installment-note").exists)
        XCTAssertFalse(app.buttons["money-reconcile-name-missedSpend"].exists)
        XCTAssertFalse(app.buttons["money-reconcile-name-unexplained"].exists)
        shot(app, "M5-V15-bnpl-open-L")
    }

    func testInvalidObservedAmountCannotSaveThePreviousBalance() throws {
        continueAfterFailure = false
        let app = openReconcile(fixture: "reconcile")
        let tamara = app.buttons["money-reconcile-row-تمارا"]
        XCTAssertTrue(tamara.waitForExistence(timeout: 10))
        for _ in 0..<8 where !tamara.isHittable { app.swipeUp(velocity: .slow) }
        tamara.tap()
        let bank = element(app, "money-reconcile-bank-field")
        XCTAssertTrue(bank.waitForExistence(timeout: 5))
        bank.tap()
        bank.typeText("1,500")
        let sentence = element(app, "money-reconcile-sentence")
        XCTAssertTrue(sentence.label.contains("٣٠٠"), sentence.label)
        let save = app.buttons["money-reconcile-save"]
        XCTAssertTrue(save.isEnabled)

        bank.typeText(".12.3")
        let note = element(app, "money-reconcile-note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "The previous valid balance must not be written for malformed input.")

        bank.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Correcting the amount makes the draft saveable again.")
    }
}
