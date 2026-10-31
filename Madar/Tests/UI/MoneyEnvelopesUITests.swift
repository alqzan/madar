import XCTest

@MainActor final class MoneyEnvelopesUITests: XCTestCase {
    func make(_ fixture: String = "showcase") -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    func open(_ app: XCUIApplication) {
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap(); let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelopes"].waitForExistence(timeout: 10))
    }
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func plainLabel(_ element: XCUIElement) -> String {
        element.label.unicodeScalars.filter { ![0x200E, 0x200F, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value) }.map(String.init).joined()
    }
    private func reachGoal(_ goal: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if goal.isHittable && goal.frame.maxY < app.frame.maxY - 140 { return }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(goal.isHittable && goal.frame.maxY < app.frame.maxY - 140, app.debugDescription)
    }
    func testReservePreviewTargetUndoAndRelaunch() throws {
        continueAfterFailure = false; let app = make(); open(app)
        XCTAssertTrue(app.staticTexts["money-reserve-dailies"].label.contains("٢٥٠"), app.staticTexts["money-reserve-dailies"].label)
        XCTAssertTrue(app.staticTexts["money-reserve-coverage"].label.contains("١٩١"), app.staticTexts["money-reserve-coverage"].label)
        shot(app, "M5-V03-envelopes-L")
        app.buttons["money-reserve-preview-5000000"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-after"].firstMatch.label.contains("٥٠٬٠٠٠"))
        XCTAssertTrue(app.staticTexts["money-envelope-reserve"].label.contains("١٠٠٬٠٠٠"))
        XCTAssertTrue(app.staticTexts["money-reserve-coverage"].label.contains("٩٥"))
        shot(app, "M5-V03-preview-L")
        app.buttons["money-reserve-mode-goal"].tap()
        let input = app.textFields["money-reserve-target-input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("200000")
        app.buttons["money-reserve-target-save"].tap(); XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-target"].firstMatch.label.contains("٢٠٠٬٠٠٠"))
        shot(app, "M5-V03-target-L")
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-target"].firstMatch.waitForNonExistence(timeout: 10))
        app.swipeUp(velocity: .slow); shot(app, "M5-V03-envelopes-surplus-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V03-envelopes-s1-L")
        app.terminate(); app.launch(); open(app)
        XCTAssertFalse(app.descendants(matching: .any)["money-reserve-after"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["money-reserve-target"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["money-envelope-reserve"].label.contains("١٠٠٬٠٠٠"))
    }
    func testReserveGoalSaveRequiresPositiveAmount() throws {
        continueAfterFailure = false; let app = make(); open(app)
        app.buttons["money-reserve-preview-5000000"].tap()
        app.buttons["money-reserve-mode-goal"].tap()
        let input = app.textFields["money-reserve-target-input"], save = app.buttons["money-reserve-target-save"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "An empty reserve goal cannot be saved")
        input.tap(); input.typeText("200000")
        XCTAssertTrue(save.isEnabled, "A positive target enables saving")
        app.terminate()
    }
    func testEnvelopeSavingChangeRequiresPositiveAmount() throws {
        continueAfterFailure = false; let app = make("salary"); open(app)
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-envelope-رحلة الشتاء")).firstMatch
        reachGoal(trip, in: app); XCTAssertTrue(trip.waitForExistence(timeout: 10)); trip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelope-detail"].waitForExistence(timeout: 10))
        let increase = app.buttons["money-envelope-saving-add"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5)); increase.tap()
        let input = app.textFields["money-saving-change-amount"], save = app.buttons["money-saving-change-save"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "An empty saving change cannot be saved")
        let savingValue = app.descendants(matching: .any)["money-envelope-saving-value"]
        XCTAssertTrue(savingValue.exists, app.debugDescription)
        let before = savingValue.label
        input.tap(); input.typeText("50")
        XCTAssertTrue(save.isEnabled, "A positive change enables saving")
        save.tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(savingValue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(savingValue.label, before, "A successful edit should update the amount shown in the envelope detail.")
        shot(app, "AU95-money-saving-after-L")
        app.terminate()
    }
    func testHiddenReserveDoesNotLeakDailiesOrCoverage() throws {
        continueAfterFailure = false; let app = make("hidden"); open(app)
        XCTAssertEqual(app.staticTexts["money-envelope-reserve"].label, "•••")
        XCTAssertFalse(app.staticTexts["money-reserve-dailies"].exists)
        XCTAssertFalse(app.staticTexts["money-reserve-coverage"].exists)
        shot(app, "M5-V03-hidden-L")
        app.buttons["money-envelopes-reveal"].tap()
        XCTAssertTrue(app.staticTexts["money-reserve-dailies"].label.contains("٢٥٠"))
    }
    func testGoalForecastShowsFundedAndShortDatesAndPersistsThroughRelaunch() throws {
        continueAfterFailure = false; let app = make("funding"); open(app)
        let gift = app.buttons["money-envelope-هدية"], emergency = app.buttons["money-envelope-الطوارئ"]
        reachGoal(gift, in: app)
        XCTAssertTrue(gift.waitForExistence(timeout: 10))
        XCTAssertTrue(gift.label.contains("بحسب خطتك، يكتمل بحلول الموعد"), gift.label)
        XCTAssertTrue(plainLabel(emergency).contains("بحسب خطتك، ينقصه ١٠٠ عند الموعد"), emergency.label)
        shot(app, "OR-22-goal-due-rails-L")
        app.terminate(); app.launch(); open(app)
        reachGoal(gift, in: app)
        XCTAssertTrue(gift.label.contains("بحسب خطتك، يكتمل بحلول الموعد"), gift.label)
        XCTAssertTrue(plainLabel(emergency).contains("ينقصه ١٠٠ عند الموعد"), emergency.label)
        shot(app, "OR-22-goal-due-reopened-L")
        for _ in 0..<3 where !emergency.isHittable { app.swipeDown(velocity: .slow) }
        emergency.tap()
        let detail = app.descendants(matching: .any)["money-detail-shortfall"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue(plainLabel(detail).contains("ينقصه ١٠٠"), detail.label)
        shot(app, "OR-22-shared-detail-forecast-L")
    }
    func testHiddenGoalsDoNotExposeConditionalAmountsUntilReveal() throws {
        continueAfterFailure = false; let app = make("hidden"); open(app)
        let gift = app.buttons["money-envelope-هدية"]
        XCTAssertFalse(gift.label.contains("بحسب خطتك"), gift.label)
        XCTAssertFalse(app.staticTexts["تقدير دون صرف جديد"].exists)
        app.buttons["money-envelopes-reveal"].tap()
        reachGoal(gift, in: app)
        XCTAssertTrue(plainLabel(gift).contains("بحسب خطتك، ينقصه ١٤٠ عند الموعد"), gift.label)
        shot(app, "OR-22-goals-revealed-L")
        app.terminate(); app.launch(); open(app)
        XCTAssertFalse(gift.label.contains("بحسب خطتك"), gift.label)
        XCTAssertFalse(app.staticTexts["تقدير دون صرف جديد"].exists)
    }
    func testHiddenSavedReserveGoalNeedsRevealInSheet() throws {
        continueAfterFailure = false; let app = make("hidden"); open(app)
        app.buttons["money-envelopes-reveal"].tap()
        app.buttons["money-reserve-mode-goal"].tap()
        let input = app.textFields["money-reserve-target-input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("200000")
        app.buttons["money-reserve-target-save"].tap(); XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        app.terminate(); app.launch(); open(app)
        XCTAssertEqual(app.staticTexts["money-envelope-reserve"].label, "•••")
        app.buttons["money-reserve-mode-goal"].tap()
        let reveal = app.buttons["money-reserve-target-reveal"]; XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(input.exists); XCTAssertFalse(app.buttons["money-reserve-target-save"].exists)
        shot(app, "M5-V03-target-hidden-L")
        reveal.tap(); XCTAssertTrue(input.waitForExistence(timeout: 5))
        let value = input.value as? String ?? ""
        XCTAssertTrue(value.contains("٢٠٠") || value.contains("200"), value)
    }

}
