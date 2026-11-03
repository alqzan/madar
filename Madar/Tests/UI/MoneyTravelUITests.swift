import XCTest

@MainActor final class MoneyTravelUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reach(_ app: XCUIApplication, _ button: XCUIElement) {
        let shortcut = app.buttons["tab-mihbara"]
        for _ in 0..<6 {
            let bottom = shortcut.exists ? shortcut.frame.minY - 8 : app.frame.maxY - 90
            if button.isHittable && button.frame.maxY < bottom { return }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(button.isHittable)
    }
    private func open(_ fixture: String, store: String = UUID().uuidString, failTravelReadOnce: Bool = false, writeHoldMS: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        if failTravelReadOnce { app.launchEnvironment["MADAR_UI_MONEY_TRAVEL_READ_FAILURE_ONCE"] = "1" }
        if let writeHoldMS { app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"] = String(writeHoldMS) }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        if failTravelReadOnce { XCTAssertTrue(app.staticTexts["money-travel-read-error"].waitForExistence(timeout: 10)) }
        else { XCTAssertTrue(app.staticTexts["money-travel-remaining"].waitForExistence(timeout: 10)) }
        return app
    }
    func testTripDetectionFailureDoesNotPretendThereIsNoTrip() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "travel", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00", "MADAR_UI_MONEY_TRIP_DETECTION_FAILURE_ONCE": "1"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let failure = app.staticTexts["money-trip-detection-error"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["money-title"].exists)
        app.buttons["money-trip-detection-retry"].tap()
        XCTAssertTrue(app.staticTexts["money-travel-remaining"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testTripReadFailureOffersRetry() {
        continueAfterFailure = false
        let app = open("travel", failTravelReadOnce: true)
        XCTAssertTrue(app.staticTexts["money-travel-read-error"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["money-travel-retry"].tap()
        XCTAssertTrue(app.staticTexts["money-travel-remaining"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testTicketRateSaveUndoExpenseAndReport() {
        continueAfterFailure = false
        let store = UUID().uuidString, app = open("travel", store: store)
        XCTAssertFalse(app.staticTexts["money-travel-remaining"].label.contains("—")); shot(app, "M5-V21-travel-L")
        app.buttons["money-travel-rate"].tap()
        let field = app.textFields["money-trip-rate-input"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "0.2")
        app.buttons["money-trip-keyboard-done"].tap(); XCTAssertTrue(app.staticTexts["money-trip-rate-preview"].label.contains("٢٠")); shot(app, "M5-V21-rate-L")
        app.buttons["money-trip-rate-save"].tap()
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        let report = app.buttons["money-travel-report"]; reach(app, report); shot(app, "M5-V21-travel-s1-L"); report.tap()
        let closeReport = app.buttons["money-trip-report-close"]
        XCTAssertTrue(closeReport.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["تقرير رحلة إسطنبول"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(identifier: "زيارة البرج").firstMatch.waitForExistence(timeout: 5))
        shot(app, "M5-V21-report-L"); closeReport.tap()
        let expense = app.buttons["money-travel-expense"]; reach(app, expense); expense.tap()
        XCTAssertTrue(app.segmentedControls["money-expense-currency"].waitForExistence(timeout: 5))
        app.buttons["money-expense-key-4"].tap(); app.buttons["money-expense-key-2"].tap()
        shot(app, "M5-V21-expense-L")
        let save = app.buttons["money-expense-save"]; reach(app, save); save.tap()
        XCTAssertTrue(app.staticTexts["money-travel-remaining"].waitForExistence(timeout: 10)); app.terminate()
        let relaunched = open("travel", store: store); XCTAssertTrue(relaunched.staticTexts["money-travel-remaining"].exists)
    }
    func testFundTripAndRepricePreviewBothHaveOneUndo() {
        continueAfterFailure = false
        let app = open("travel"), remaining = app.staticTexts["money-travel-remaining"], original = remaining.label
        let fund = app.buttons["money-travel-fund"]; for _ in 0..<4 where !fund.isHittable { app.swipeUp(velocity: .slow) }; fund.tap()
        let amount = app.textFields["money-trip-fund-input"]; XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let available = app.staticTexts["money-trip-fund-available"]
        XCTAssertTrue(available.label.contains("الفائض") && available.label.contains("٢٬٦٠٠") && available.label.contains("ريال"), available.label)
        amount.tap(); amount.typeText("10000"); app.buttons["money-trip-keyboard-done"].tap()
        let hint = app.staticTexts["money-trip-fund-hint"], save = app.buttons["money-trip-fund-save"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5)); XCTAssertTrue(hint.label.contains("الفائض")); XCTAssertFalse(save.isEnabled)
        shot(app, "M5-V21-funding-shortfall-L")
        let sources = app.segmentedControls["money-trip-fund-source"]
        sources.buttons["الاحتياطي"].tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5)); XCTAssertTrue(save.isEnabled)
        sources.buttons["الفائض"].tap(); XCTAssertTrue(hint.waitForExistence(timeout: 5)); XCTAssertFalse(save.isEnabled)
        amount.tap(); amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "100"); app.buttons["money-trip-keyboard-done"].tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5)); XCTAssertTrue(save.isEnabled)
        shot(app, "M5-V21-fund-L"); app.buttons["money-trip-fund-save"].tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5)); XCTAssertNotEqual(remaining.label, original); app.buttons["تراجع"].tap(); XCTAssertEqual(remaining.label, original)
        for _ in 0..<4 where !app.buttons["money-travel-rate"].isHittable { app.swipeDown(velocity: .slow) }; app.buttons["money-travel-rate"].tap()
        let rate = app.textFields["money-trip-rate-input"]; XCTAssertTrue(rate.waitForExistence(timeout: 5)); rate.tap(); rate.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "0.2"); app.buttons["money-trip-keyboard-done"].tap(); app.buttons["money-trip-rate-save"].tap()
        XCTAssertTrue(remaining.waitForExistence(timeout: 5)); let beforeReprice = remaining.label
        app.buttons["money-travel-rate"].tap(); app.buttons["money-trip-reprice-preview"].tap(); let apply = app.buttons["money-trip-reprice-apply"]; XCTAssertTrue(apply.waitForExistence(timeout: 5)); shot(app, "M5-V21-reprice-L"); apply.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5)); XCTAssertNotEqual(remaining.label, beforeReprice); app.buttons["تراجع"].tap(); XCTAssertEqual(remaining.label, beforeReprice)
    }

    func testTripRateFundingAndRepriceStayOpenWhileSaving() {
        continueAfterFailure = false
        let app = open("travel", writeHoldMS: 5000)

        app.buttons["money-travel-rate"].tap()
        let rateClose = app.buttons["money-trip-rate-close"]
        let rate = app.textFields["money-trip-rate-input"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap(); rate.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "0.2")
        app.buttons["money-trip-keyboard-done"].tap()
        let rateSave = app.buttons["money-trip-rate-save"]
        shot(app, "M5-V21-rate-save-idle-L")
        rateSave.tap()
        XCTAssertTrue(rateClose.exists); XCTAssertFalse(rateClose.isEnabled); XCTAssertFalse(rateSave.isEnabled)
        shot(app, "M5-V21-rate-save-pending-L")
        app.swipeDown()
        XCTAssertTrue(rateClose.exists); XCTAssertFalse(rateClose.isEnabled); XCTAssertFalse(rateSave.isEnabled)
        XCTAssertTrue(rateClose.waitForNonExistence(timeout: 12), app.debugDescription)

        let fund = app.buttons["money-travel-fund"]; reach(app, fund); fund.tap()
        let fundClose = app.buttons["money-trip-fund-close"]
        let amount = app.textFields["money-trip-fund-input"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap(); amount.typeText("100")
        app.buttons["money-trip-keyboard-done"].tap()
        let fundSave = app.buttons["money-trip-fund-save"]; reach(app, fundSave)
        XCTAssertTrue(fundSave.isEnabled)
        shot(app, "M5-V21-fund-save-idle-L")
        fundSave.tap()
        XCTAssertTrue(fundClose.exists); XCTAssertFalse(fundClose.isEnabled); XCTAssertFalse(fundSave.isEnabled)
        shot(app, "M5-V21-fund-save-pending-L")
        app.swipeDown()
        XCTAssertTrue(fundClose.exists); XCTAssertFalse(fundClose.isEnabled); XCTAssertFalse(fundSave.isEnabled)
        XCTAssertTrue(fundClose.waitForNonExistence(timeout: 12), app.debugDescription)

        app.buttons["money-travel-rate"].tap()
        let previewButton = app.buttons["money-trip-reprice-preview"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 8), app.debugDescription)
        previewButton.tap()
        let previewClose = app.buttons["money-trip-reprice-close"]
        let apply = app.buttons["money-trip-reprice-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        shot(app, "M5-V21-reprice-save-idle-L")
        apply.tap()
        XCTAssertTrue(previewClose.exists); XCTAssertFalse(previewClose.isEnabled); XCTAssertFalse(apply.isEnabled)
        shot(app, "M5-V21-reprice-save-pending-L")
        app.swipeDown()
        XCTAssertTrue(previewClose.exists); XCTAssertFalse(previewClose.isEnabled); XCTAssertFalse(apply.isEnabled)
        XCTAssertTrue(previewClose.waitForNonExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(rateClose.waitForNonExistence(timeout: 5), app.debugDescription)
    }
    func testMissingRateAndHiddenAmounts() {
        continueAfterFailure = false
        let hidden = open("travelHidden"); XCTAssertEqual(hidden.staticTexts["money-travel-remaining"].label, "•••"); shot(hidden, "M5-V21-hidden-L")
        hidden.buttons["money-travel-reveal"].tap(); XCTAssertNotEqual(hidden.staticTexts["money-travel-remaining"].label, "•••"); hidden.terminate()
        let missing = open("travelMissing"); XCTAssertTrue(missing.buttons["money-travel-missing-rate"].exists); shot(missing, "M5-V21-missing-L")
    }

    func testTwoCountriesKeepOneBudgetAndTheirOriginalCurrencies() {
        continueAfterFailure = false
        let store = UUID().uuidString, app = open("travelMultiLeg", store: store)
        let legs = app.staticTexts["money-travel-legs"]
        XCTAssertEqual(legs.label, "إسطنبول ← باريس")
        let units = app.segmentedControls["money-travel-units"]
        units.buttons["ريال"].tap()
        let balance = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "وفي الرحلة ")).firstMatch
        // SAR 5,000 − TRY 2,310 at 0.1 − EUR 25 at 4 = SAR 4,669.
        XCTAssertTrue(balance.label.contains("٤٬٦٦٩"), balance.label)
        units.buttons["يورو"].tap()
        XCTAssertTrue(balance.label.contains("١٬١٦٧٫٢٥"), balance.label)
        units.buttons["ريال"].tap()
        shot(app, "OR-09-two-country-ticket-L")
        let report = app.buttons["money-travel-report"]; reach(app, report); report.tap()
        let close = app.buttons["money-trip-report-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["تقرير رحلة إسطنبول وباريس"].exists)
        XCTAssertTrue(app.staticTexts["زيارة البرج"].exists)
        XCTAssertTrue(app.staticTexts["متحف باريس"].exists)
        let start = app.descendants(matching: .any).matching(identifier: "money-trip-report-start").firstMatch
        XCTAssertTrue(start.label.contains("١٤ أكتوبر"), start.label)
        shot(app, "OR-09-two-currency-report-L")
        let sheet = app.descendants(matching: .any).matching(identifier: "money-travel-report-sheet").firstMatch
        let originals = sheet.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-travel-original-"))
        XCTAssertEqual(originals.count, 4)
        let labels = originals.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("١٬٢٦٥") && $0.contains("ليرة") }, labels.description)
        XCTAssertTrue(labels.contains { $0.contains("٢٥") && $0.contains("يورو") }, labels.description)
        close.tap()
        let ledger = app.buttons["money-travel-ledger"]; reach(app, ledger)
        XCTAssertEqual(ledger.label, "ارجع لمالي"); ledger.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10))
        app.terminate()
        let reopened = open("travelMultiLeg", store: store)
        XCTAssertEqual(reopened.staticTexts["money-travel-legs"].label, "إسطنبول ← باريس")
        reopened.segmentedControls["money-travel-units"].buttons["ريال"].tap()
        XCTAssertTrue(reopened.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "وفي الرحلة ")).firstMatch.label.contains("٤٬٦٦٩"))
    }

    func testTwoCountryReportKeepsOriginalAmountsHiddenUntilReveal() {
        continueAfterFailure = false
        let app = open("travelMultiLegHidden")
        XCTAssertEqual(app.staticTexts["money-travel-remaining"].label, "•••")
        let report = app.buttons["money-travel-report"]; reach(app, report); report.tap()
        let close = app.buttons["money-trip-report-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let sheet = app.descendants(matching: .any).matching(identifier: "money-travel-report-sheet").firstMatch
        let originals = sheet.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-travel-original-"))
        XCTAssertEqual(originals.count, 0)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "٤٬٦٦٩")).firstMatch.exists)
        shot(app, "OR-09-two-country-hidden-report-L")
        close.tap()
        let reveal = app.buttons["money-travel-reveal"]
        for _ in 0..<6 where !reveal.isHittable { app.swipeDown(velocity: .slow) }
        reveal.tap()
        app.segmentedControls["money-travel-units"].buttons["ريال"].tap()
        reach(app, report); report.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(originals.count, 4)
        shot(app, "OR-09-two-country-revealed-report-L")
    }
}
