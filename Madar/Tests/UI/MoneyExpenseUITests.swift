import XCTest

@MainActor final class MoneyExpenseUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openExpense(_ fixture: String = "expense") -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let tripExpense = app.buttons["money-travel-expense"]
        if tripExpense.waitForExistence(timeout: 3) {
            for _ in 0..<8 where !tripExpense.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(tripExpense.isHittable, app.debugDescription); tripExpense.tap()
        } else {
            let door = app.buttons["money-expense-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        }
        XCTAssertTrue(app.buttons["money-expense-key-4"].waitForExistence(timeout: 10)); return app
    }
    func testClosePromptsBeforeDiscardingExpenseDraft() {
        continueAfterFailure = false
        let app = openExpense()
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap()
        let amount = app.staticTexts["money-expense-amount"].label
        app.buttons["money-expense-close"].tap()
        let keep = app.buttons["money-expense-continue"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 8), app.debugDescription); shot(app, "AU-95-expense-discard-prompt-L"); keep.tap()
        XCTAssertEqual(app.staticTexts["money-expense-amount"].label, amount, "Continuing keeps the amount entered in the calculator.")
        app.buttons["money-expense-close"].tap()
        let discard = app.buttons["money-expense-discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription); discard.tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testCalculatorSplitSaveAndUndo() {
        continueAfterFailure = false
        let app = openExpense()
        XCTAssertFalse(app.buttons["money-expense-save"].isEnabled)
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap()
        app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        let after = app.staticTexts["money-expense-after"]; XCTAssertTrue(after.waitForExistence(timeout: 5)); let before = after.label
        shot(app, "M5-V17-add-L")
        app.buttons["money-expense-share-quarter"].tap()
        XCTAssertNotEqual(after.label, before)
        app.buttons["money-expense-diary"].tap()
        shot(app, "M5-V17-split-L")
        let save = app.buttons["money-expense-save"]; for _ in 0..<3 where !save.isHittable { app.swipeUp(velocity: .slow) }; save.tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 10))
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        app.buttons["money-expense-open"].tap()
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap(); app.buttons["money-expense-merchant-مقهى الزاوية"].tap()
        XCTAssertEqual(app.staticTexts["money-expense-after"].label, before)
        app.buttons["money-expense-method-كاش"].tap()
        XCTAssertTrue(app.staticTexts["احتُسب عند السحب؛ لن يُخصم من يومك مرة أخرى."].exists)
        shot(app, "M5-V17-cash-L")
    }
    func testEmptyStoreExplainsPaymentSource() {
        continueAfterFailure = false
        let app = openExpense("empty")
        XCTAssertTrue(app.staticTexts["أضف حسابًا من «الحسابات» أو بطاقة من «البطاقات» أولًا."].exists)
        app.buttons["money-expense-key-4"].tap(); XCTAssertFalse(app.buttons["money-expense-save"].isEnabled)
        shot(app, "M5-V17-empty-L")
    }

    func testQueuedMoneyExpenseSeedsPresentInFIFOOrderWithoutSaving() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00",
            "MADAR_UI_MONEY_FIFO_HARNESS": "1"]
        app.launch()
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 20), app.debugDescription); customize.tap()
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]
        XCTAssertTrue(money.waitForExistence(timeout: 8), app.debugDescription); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 15), app.debugDescription)
        let open = app.buttons["money-expense-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15), app.debugDescription)
        if !open.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(open.isHittable, app.debugDescription); open.tap()
        let amount = app.staticTexts["money-expense-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 12), app.debugDescription)
        let firstAmount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "١٨"), object: amount)
        XCTAssertEqual(XCTWaiter.wait(for: [firstAmount], timeout: 8), .completed, app.debugDescription)
        let firstMerchant = app.buttons["money-expense-merchant-edit"]
        let firstMerchantLabel = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "طلب أول"), object: firstMerchant)
        XCTAssertEqual(XCTWaiter.wait(for: [firstMerchantLabel], timeout: 8), .completed, app.debugDescription)
        app.buttons["money-expense-test-queue-two"].tap()
        XCTAssertTrue(amount.label.contains("١٨"), "New Capture requests must not replace the open expense.")

        app.buttons["money-expense-close"].tap()
        let discard = app.buttons["money-expense-discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription); discard.tap()
        let secondAmount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "٧"), object: amount)
        XCTAssertEqual(XCTWaiter.wait(for: [secondAmount], timeout: 15), .completed, app.debugDescription)
        let secondMerchant = app.buttons["money-expense-merchant-edit"]
        let secondMerchantLabel = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "طلب ثانٍ"), object: secondMerchant)
        XCTAssertEqual(XCTWaiter.wait(for: [secondMerchantLabel], timeout: 8), .completed, app.debugDescription)

        app.buttons["money-expense-close"].tap()
        let discardSecond = app.buttons["money-expense-discard"].firstMatch
        XCTAssertTrue(discardSecond.waitForExistence(timeout: 8), app.debugDescription); discardSecond.tap()
        let thirdAmount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "٢٣"), object: amount)
        XCTAssertEqual(XCTWaiter.wait(for: [thirdAmount], timeout: 15), .completed, app.debugDescription)
        let thirdMerchantLabel = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "طلب ثالث"), object: secondMerchant)
        XCTAssertEqual(XCTWaiter.wait(for: [thirdMerchantLabel], timeout: 8), .completed, app.debugDescription)
        app.buttons["money-expense-close"].tap()
        app.buttons["money-expense-discard"].firstMatch.tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["undo-button"].exists, "Opening queued drafts must never save them.")
        app.terminate()
    }

    private func enterTripDuplicate(_ app: XCUIApplication) {
        for key in ["4", "2", "5"] { app.buttons["money-expense-key-" + key].tap() }
        let merchant = app.buttons["money-expense-merchant-TripTest"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<6 where !merchant.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(merchant.isHittable, app.debugDescription); merchant.tap()
    }

    func testTripCurrencyDuplicateHintMatchesStoredCurrency() {
        continueAfterFailure = false
        let app = openExpense("travelDupTRY")
        enterTripDuplicate(app)
        let hint = app.staticTexts["money-expense-duplicate"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !hint.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(hint.isHittable, app.debugDescription)
        shot(app, "M5-V17-duplicate-trip-currency-L")
    }

    func testTripCurrencyDuplicateHintIgnoresHomeCurrencyMatch() {
        continueAfterFailure = false
        let app = openExpense("travelDupSAR")
        enterTripDuplicate(app)
        XCTAssertFalse(app.staticTexts["money-expense-duplicate"].exists, app.debugDescription)
    }
}
