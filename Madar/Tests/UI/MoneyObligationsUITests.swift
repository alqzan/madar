import XCTest

/// M5-V09: the obligations room opens from the money home, and repeat charges create reviewable drafts.
@MainActor final class MoneyObligationsUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testObligationsThreadLadderShelvesAndAdd() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-obligations-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()
        let total = app.staticTexts["money-obligations-total"]; XCTAssertTrue(total.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["money-obligation-detail"].exists)
        shot(app, "M5-V09-obl-L")
        app.swipeUp(velocity: .slow); shot(app, "M5-V09-obl-s1-L")
        XCTAssertTrue(app.descendants(matching: .any)["money-ladder"].exists)
        let add = app.buttons["money-obligations-add"]; for _ in 0..<3 where !add.isHittable { app.swipeUp(velocity: .slow) }
        add.tap()
        let name = app.textFields["money-obligation-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("الماء")
        let amount = app.textFields["money-obligation-amount"]; amount.tap(); amount.typeText("85")
        XCTAssertTrue(app.descendants(matching: .any)["money-obligation-preview"].waitForExistence(timeout: 5))
        shot(app, "M5-V09-add-L")
        app.buttons["money-obligation-save"].tap()
        let row = app.buttons["money-obligation-row-الماء"]; XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !row.isHittable { app.swipeUp(velocity: .slow) }
        shot(app, "M5-V09-obl-s2-L")
    }

    /// M5-X00 (owner 16 Oct): rent every 6 months, first due 18 Feb 2027 (4 months and 2 days after 16 Oct 2026),
    /// lands on its own «الاشتراكات» shelf with the next three due days previewed in both calendars.
    func testSubscriptionEverySixMonthsWithAFreeFirstDate() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-obligations-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()
        let add = app.buttons["money-obligations-add"]; XCTAssertTrue(add.waitForExistence(timeout: 10))
        for _ in 0..<4 where !add.isHittable { app.swipeUp(velocity: .slow) }
        add.tap()
        let kind = app.segmentedControls["money-obligation-kind"]; XCTAssertTrue(kind.waitForExistence(timeout: 5)); kind.buttons["اشتراك"].tap()
        let name = app.textFields["money-obligation-name"]; name.tap(); name.typeText("الإيجار")
        let amount = app.textFields["money-obligation-amount"]; amount.tap(); amount.typeText("15000")
        let done = app.buttons["money-obligation-keyboard-done"]; XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let more = app.buttons["money-obligation-every-Increment"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        for _ in 0..<5 { more.tap() }
        XCTAssertEqual(app.staticTexts["money-obligation-rhythm"].label, "كل ٦ أشهر")
        // The first due day: open the calendar, move four months on, pick the 18th.
        let picker = app.datePickers["money-obligation-first"]; XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        let next = app.buttons["DatePicker.NextMonth"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<4 { next.tap() }
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "١٨ فبراير", "18 February")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription); day.tap()
        // Close the calendar by tapping the sheet title above it, and keep the keyboard away for the shots.
        // The calendar popover can leave the title reported as not hittable; a tap at its position still lands outside it.
        app.staticTexts["التزام جديد"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["DatePicker.NextMonth"].waitForNonExistence(timeout: 5))
        // Focus can return to the amount field once the popover closes; wait for it, then close the keyboard.
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.textFields["money-obligation-amount"].value as? String, "15000")
        let relative = app.staticTexts["money-obligation-first-relative"]
        XCTAssertTrue(relative.waitForExistence(timeout: 5))
        XCTAssertEqual(relative.label, "بعد ٤ أشهر ويومين", app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["money-obligation-upcoming"].exists)
        shot(app, "M5-X00-add-rent-L")
        app.swipeUp(velocity: .slow)
        if app.keyboards.count > 0 { done.tap() }
        shot(app, "M5-X00-add-rent-s1-L")
        app.buttons["money-obligation-save"].tap()
        let row = app.buttons["money-obligation-row-الإيجار"]; XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<6 where !row.isHittable { app.swipeUp(velocity: .slow) }
        row.tap()
        XCTAssertTrue(app.staticTexts["money-obligation-schedule"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["money-obligation-schedule"].label, "اشتراك يتكرر كل ٦ أشهر")
        shot(app, "M5-X00-subscriptions-shelf-L")
    }

    /// M5-V09: three confirmed, equal monthly bank charges offer a reviewable draft only.
    func testRepeatChargeSuggestionPrefillsDraftWithoutSaving() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "subscriptions",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-obligations-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()

        let suggestion = app.buttons["money-subscription-suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<8 where !suggestion.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(suggestion.isHittable, app.debugDescription)
        XCTAssertTrue(suggestion.label.contains("منصة شاهد"))
        XCTAssertTrue(suggestion.label.contains("٣٩٩"))
        shot(app, "M5-V09-subscription-suggestion-L")
        suggestion.tap()

        let name = app.textFields["money-obligation-name"]
        let amount = app.textFields["money-obligation-amount"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "منصة شاهد")
        XCTAssertEqual(amount.value as? String, "399")
        XCTAssertTrue(app.segmentedControls["money-obligation-kind"].buttons["اشتراك"].isSelected)
        app.buttons["إلغاء"].tap()
        XCTAssertFalse(app.buttons["money-obligation-row-منصة شاهد"].exists, app.debugDescription)
    }

    /// M5-V25: a repeated confirmed bank charge becomes an obligation only after the owner confirms the review draft.
    func testConfirmingRepeatChargeCreatesSubscriptionOnShelf() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "subscriptions",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-obligations-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        open.tap()

        let suggestion = app.buttons["money-subscription-suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<8 where !suggestion.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(suggestion.isHittable, app.debugDescription)
        shot(app, "M5-V25-subscription-suggestion-L")
        suggestion.tap()

        let name = app.textFields["money-obligation-name"]
        let amount = app.textFields["money-obligation-amount"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "منصة شاهد")
        XCTAssertEqual(amount.value as? String, "399")
        XCTAssertTrue(app.segmentedControls["money-obligation-kind"].buttons["اشتراك"].isSelected)
        app.buttons["money-obligation-save"].tap()

        let row = app.buttons["money-obligation-row-منصة شاهد"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<10 where !row.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["money-subscription-suggestion"].exists, app.debugDescription)
        shot(app, "M5-V25-confirmed-subscription-shelf-L")
    }
}
