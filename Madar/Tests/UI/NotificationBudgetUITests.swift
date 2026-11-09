import XCTest

@MainActor final class NotificationBudgetUITests: XCTestCase {
    func testUnreadableDeviceBudgetIsRecoveredWithoutRepeatingLaunchAlert() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_NOTIFICATION_BUDGET_RECOVERY": "1",
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light"
        ]

        for _ in 0..<2 {
            app.launch()
            XCTAssertFalse(app.alerts["لم تكتمل العملية"].waitForExistence(timeout: 4), app.debugDescription)
            finishOnboarding(app)
            XCTAssertTrue(app.buttons["tab-foundation"].waitForExistence(timeout: 15), app.debugDescription)
            app.terminate()
        }
    }

    func testDailyNotificationBudgetDefaultAndGlobalReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription)
        customize.tap()

        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        search.tap(); search.typeText("notif.dailyBudget\n")
        let budget = app.steppers["setting-notif.dailyBudget"]
        XCTAssertTrue(budget.waitForExistence(timeout: 10), app.debugDescription)
        let note = app.staticTexts["setting-notif.dailyBudget-note"]
        XCTAssertTrue(note.exists, app.debugDescription)
        let noteLabel = note.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(noteLabel, "الحد على هذا الجهاز من ١ إلى ١٠. لا يشمل سؤال الصلاة ولا متابعة القلب ولا النشاط الحي؛ ويُحسب الملخّص و«افتح مدار» تذكيرًا واحدًا لكل منهما.")
        XCTAssertEqual(value(budget), 4, "The agreed default is four daily reminders.")
        capture(app, "AU96-notif-daily-budget-L")

        let buttons = budget.buttons.allElementsBoundByIndex
        XCTAssertEqual(buttons.count, 2, app.debugDescription)
        buttons[0].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] object, _ in
            guard let self, let stepper = object as? XCUIElement, let current = self.value(stepper) else { return false }
            return current == 3 || current == 5
        }, object: budget)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed, budget.debugDescription)
        let firstValue = try XCTUnwrap(value(budget))
        let increment = buttons[firstValue == 5 ? 0 : 1]
        if firstValue == 3 { increment.tap(); waitValue(budget, 4); increment.tap() }
        waitValue(budget, 5)

        app.buttons["settings-clear-search"].tap()
        let reset = app.buttons["settings-door-أعِد الإعدادات المتفق عليها"]
        scrollTo(reset, in: app)
        reset.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "أعِد الافتراضي", "reset-settings")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), app.debugDescription)
        confirm.tap()
        XCTAssertFalse(app.buttons["undo-button"].exists, "An ordinary settings reset is corrected in place and does not raise the global removal undo toast.")
        search.tap(); search.typeText("notif.dailyBudget\n")
        waitValue(budget, 4)
        app.terminate()
    }

    private func value(_ element: XCUIElement) -> Int? {
        if let number = element.value as? NSNumber { return number.intValue }
        guard let raw = element.value as? String else { return nil }
        let western = String(raw.map { character in
            switch character {
            case "٠": "0"; case "١": "1"; case "٢": "2"; case "٣": "3"; case "٤": "4"
            case "٥": "5"; case "٦": "6"; case "٧": "7"; case "٨": "8"; case "٩": "9"
            default: character
            }
        })
        guard let digits = western.split(whereSeparator: { !$0.isNumber }).last else { return nil }
        return Int(digits)
    }

    private func waitValue(_ element: XCUIElement, _ expected: Int) {
        let predicate = NSPredicate { [weak self] object, _ in
            guard let self, let stepper = object as? XCUIElement else { return false }
            return self.value(stepper) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, element.debugDescription)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) {
            start.tap()
            if start.exists && start.isHittable { start.tap() }
        }
        let city = app.buttons["first-run-city"]
        guard city.waitForExistence(timeout: 2) else { return }
        city.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription); field.tap(); field.typeText("الرياض")
        let hit = app.buttons["city-hit-الرياض"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription); hit.tap()
        if field.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        let later = app.buttons["first-run-continue"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription); later.tap()
        XCTAssertTrue(later.waitForNonExistence(timeout: 5), app.debugDescription)
    }
}
