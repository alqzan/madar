import XCTest

/// M5-V10: categories and limits open from the money home's limits block; a raised limit is saved and shown.
@MainActor final class MoneyCategoriesUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testShelvesAndLimitEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        // The limits block sits low on the home; a half-visible button lies under the bottom dimming.
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()
        let shelf = app.buttons["money-shelf-مطاعم"]; XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "M5-V10-cat-L")
        let value = app.staticTexts["money-limit-value"], save = app.buttons["money-limit-save"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }
        let before = value.label
        app.buttons["money-limit-plus"].tap()
        XCTAssertNotEqual(value.label, before)
        shot(app, "M5-V10-cat-s1-L")
        app.buttons["money-limit-save"].tap()
        app.swipeDown(velocity: .slow); app.swipeDown(velocity: .slow)
        let saved = app.buttons["money-shelf-مطاعم"]
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "٣٬١٠٠").evaluate(with: saved) || saved.label.contains("3,100") || saved.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("٣٬١٠٠") }, saved.debugDescription)
    }

    func testAmountLimitUsesItsLocalizedHomeCurrencyName() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_MONEY_CURRENCY": "USD", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()
        let amountMode = app.buttons["money-limit-mode-amount"]
        for _ in 0..<8 where !amountMode.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(amountMode.waitForExistence(timeout: 10), app.debugDescription)
        let expected = try XCTUnwrap(Locale(identifier: "ar").localizedString(forCurrencyCode: "USD"))
        XCTAssertTrue(amountMode.label.contains(expected), amountMode.label)
        XCTAssertFalse(amountMode.label.contains("ريال"), amountMode.label)
        shot(app, "AU-81-categories-usd-L")
        app.terminate()
    }

    func testPercentLimitDisplaysHundredths() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()
        let shelf = app.buttons["money-shelf-بقالة"]; XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
        shelf.tap()
        XCTAssertTrue(app.staticTexts["حدّ بقالة"].waitForExistence(timeout: 5), app.debugDescription)
        let value = app.staticTexts["money-limit-value"]
        XCTAssertTrue(value.label.contains("٤٬٠٠٠"), value.debugDescription)
        let percentMode = app.buttons["money-limit-mode-percent"]
        for _ in 0..<8 where !percentMode.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(percentMode.waitForExistence(timeout: 10), app.debugDescription); percentMode.tap()
        XCTAssertTrue(value.waitForExistence(timeout: 10), app.debugDescription)
        let normalizedValue = value.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(normalizedValue, "٢٦٫٦٦٪")
        shot(app, "AU-83-categories-percent-L")
        app.terminate()
    }

    func testInvalidLimitIsBlockedAndLargeLimitCanSwitchToPercent() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()

        let grocery = app.buttons["money-shelf-بقالة"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 10), app.debugDescription)
        grocery.tap()

        let field = app.textFields["money-limit-field"]
        for _ in 0..<8 where !field.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(field.isHittable, app.debugDescription)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, app.debugDescription)
        let assertVisibleGeometry: (XCUIElement, String) -> Void = { element, name in
            let frame = element.frame
            let bounds = window.frame
            XCTAssertTrue([frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height].allSatisfy { $0.isFinite }, "Non-finite \(name) geometry: \(frame)")
            XCTAssertGreaterThan(frame.width, 0, "The \(name) needs visible width")
            XCTAssertGreaterThan(frame.height, 0, "The \(name) needs visible height")
            XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX - 1, "The \(name) must stay inside the app window")
            XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY - 1, "The \(name) must stay inside the app window")
            XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX + 1, "The \(name) must stay inside the app window")
            XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY + 1, "The \(name) must stay inside the app window")
        }
        assertVisibleGeometry(field, "money input")
        field.tap()
        assertVisibleGeometry(field, "focused money input")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32) + "1.234")
        let invalid = app.staticTexts["money-limit-invalid-input"]
        XCTAssertTrue(invalid.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(invalid.isHittable, "The warning must remain visible above the amount keypad: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["money-limit-save"].isEnabled)
        XCTAssertEqual(app.staticTexts["money-limit-value"].label, "—", "An invalid input must not leave the previous limit looking active.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "money-limit-percent-summary").firstMatch.exists, "The percentage summary must not reuse the previous amount.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "money-limit-left").firstMatch.exists, "The remaining amount must not reuse the previous limit.")
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "OWNER-money-limit-invalid-L")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32) + "90071992547410")
        XCTAssertEqual(invalid.label, "هذا المبلغ أكبر من الحد الذي يمكن حفظه بدقة.")
        XCTAssertEqual(app.staticTexts["money-limit-value"].label, "—", "An over-limit input must not leave the previous limit looking active.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "money-limit-percent-summary").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "money-limit-left").firstMatch.exists)
        XCTAssertFalse(app.buttons["money-limit-save"].isEnabled)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32) + "90071992547409")
        XCTAssertFalse(invalid.exists, app.debugDescription)
        let done = app.buttons["money-limit-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        done.tap()
        let percent = app.buttons["money-limit-mode-percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !percent.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(percent.isHittable, app.debugDescription)
        XCTAssertTrue(percent.isEnabled, app.debugDescription)
        assertVisibleGeometry(percent, "percentage mode button before switching")
        percent.tap()
        let value = app.staticTexts["money-limit-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5), app.debugDescription)
        assertVisibleGeometry(percent, "percentage mode button after switching")
        assertVisibleGeometry(value, "percentage limit value")
        XCTAssertEqual(value.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: ""), "١٠٠٪")
        app.terminate()
    }

    func testLargeFixedLimitSurvivesSavingAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()

        let grocery = app.buttons["money-shelf-بقالة"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 10), app.debugDescription); grocery.tap()
        let field = app.textFields["money-limit-field"]
        for _ in 0..<8 where !field.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(field.isHittable, app.debugDescription)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32) + "90071992547409")
        XCTAssertFalse(app.staticTexts["money-limit-invalid-input"].exists, app.debugDescription)
        let done = app.buttons["money-limit-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription); done.tap()

        let save = app.buttons["money-limit-save"]
        for _ in 0..<8 where !save.isHittable { app.swipeUp(velocity: .slow) }
        let updatedRow = app.buttons["money-shelf-بقالة"]
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 5), app.debugDescription)
        let initialRowLabel = updatedRow.label
        XCTAssertTrue(save.isHittable && save.isEnabled, app.debugDescription); save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", initialRowLabel), object: updatedRow)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed, app.debugDescription)
        let close = app.buttons["money-categories-close"]
        close.tap()

        let reopen = app.buttons["money-categories-open"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10), app.debugDescription); reopen.tap()
        let reopenedGrocery = app.buttons["money-shelf-بقالة"]
        XCTAssertTrue(reopenedGrocery.waitForExistence(timeout: 10), app.debugDescription); reopenedGrocery.tap()
        let reloadedField = app.textFields["money-limit-field"]
        XCTAssertTrue(reloadedField.waitForExistence(timeout: 10), app.debugDescription)
        let reloadedDigits = ((reloadedField.value as? String) ?? "").compactMap(\.wholeNumberValue).map { String($0) }.joined()
        XCTAssertTrue(reloadedDigits.hasPrefix("90071992547409"), "The saved limit must reload in full: \(reloadedField.value ?? "nil")")
        app.terminate()
    }

    func testLimit80AlertIsDeliveredWithPrivacySafeCopy() throws {
        continueAfterFailure = false
        let storeID = UUID().uuidString
        var environment = ["MADAR_UI_STORE_ID": storeID, "MADAR_UI_MONEY_FIXTURE": "showcase",
                           "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_NOTIFICATION_TEST_FLOW": "1"]
        let app = XCUIApplication(); app.launchEnvironment = environment; app.launch()

        let authorize = app.buttons["notification-test-authorize"]
        if authorize.waitForExistence(timeout: 3) {
            authorize.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), springboard.debugDescription)
            let allow = alert.buttons.allElementsBoundByIndex.first { button in
                let label = button.label, normalized = label.replacingOccurrences(of: "’", with: "'")
                let positive = normalized.localizedCaseInsensitiveContains("allow") || label.contains("السماح")
                let negative = normalized.localizedCaseInsensitiveContains("don't") || normalized.localizedCaseInsensitiveContains("deny")
                    || label.contains("لا تسمح") || label.contains("عدم")
                return positive && !negative
            }
            XCTAssertNotNil(allow, "Notification prompt buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
            try XCTUnwrap(allow).tap()
        }
        XCTAssertFalse(app.buttons["notification-test-settings"].exists, "Enable simulator notifications before this system-delivery trial")
        app.terminate()
        environment.removeValue(forKey: "MADAR_NOTIFICATION_TEST_FLOW")
        app.launchEnvironment = environment; app.launch()

        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        // Prayer asks are gone (owner, 17 Nov 2026), so nothing else competes with the limit alert.
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32)); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let categories = app.buttons["money-categories-open"]; XCTAssertTrue(categories.waitForExistence(timeout: 10))
        for _ in 0..<6 where !categories.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where categories.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        categories.tap()
        let shelf = app.buttons["money-shelf-مطاعم"]; XCTAssertTrue(shelf.waitForExistence(timeout: 10)); shelf.tap()
        let minus = app.buttons["money-limit-minus"], value = app.staticTexts["money-limit-value"]
        let save = app.buttons["money-limit-save"]
        XCTAssertTrue(value.waitForExistence(timeout: 10)); XCTAssertTrue(minus.waitForExistence(timeout: 10))
        for _ in 0..<6 where !minus.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<25 { minus.tap() }
        for _ in 0..<6 where !save.isHittable { app.swipeUp(velocity: .slow) }
        save.tap()
        let saved = app.buttons["money-shelf-مطاعم"]
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "٥٠٠").evaluate(with: saved) || saved.label.contains("500"), saved.debugDescription)
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.001))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.72)))
        let body = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "بلغت ٨٠٪ من حد «مطاعم» لهذه الدورة")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 180), springboard.debugDescription)
        XCTAssertNil(body.label.replacingOccurrences(of: "٨٠٪", with: "").rangeOfCharacter(from: .decimalDigits), body.label)
        XCTAssertTrue(body.label.contains("مطاعم"), body.label)
        shot(springboard, "M5-V10-a80-real-privacy-safe-L")
    }

    // Owner, 22 Nov 2026: add, rename and remove a category.
    private func openCategories() -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let open = app.buttons["money-categories-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<4 where open.frame.maxY > app.frame.maxY - 140 { app.swipeUp(velocity: .slow) }
        open.tap()
        XCTAssertTrue(app.buttons["money-shelf-مطاعم"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }
    private func removeButton(_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'money-category-remove-' AND NOT identifier ENDSWITH 'failure'")).firstMatch }
    func testNewCategoryCanBeAddedAndThenRemoved() throws {
        continueAfterFailure = false
        let app = openCategories()
        app.buttons["money-category-add"].tap()
        let name = app.textFields["money-edit-name"]; XCTAssertTrue(name.waitForExistence(timeout: 8), app.debugDescription)
        name.tap(); name.typeText("هدايا")
        app.buttons["money-edit-save"].tap()
        let shelf = app.buttons["money-shelf-هدايا"]; XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<6 where !shelf.isHittable { app.swipeUp(velocity: .slow) }
        shelf.tap()
        let remove = removeButton(app)
        for _ in 0..<8 where !remove.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription); remove.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "احذف التصنيف")).allElementsBoundByIndex.last
        XCTAssertTrue(try XCTUnwrap(confirm).waitForExistence(timeout: 5), app.debugDescription); confirm?.tap()
        XCTAssertTrue(app.buttons["money-shelf-هدايا"].waitForNonExistence(timeout: 10), app.debugDescription)
    }
    func testCategoryWithRecordedMovementsExplainsWhyItStays() throws {
        continueAfterFailure = false
        let app = openCategories()
        let remove = removeButton(app)
        for _ in 0..<8 where !remove.exists || !remove.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription); remove.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "احذف التصنيف")).allElementsBoundByIndex.last
        XCTAssertTrue(try XCTUnwrap(confirm).waitForExistence(timeout: 5), app.debugDescription); confirm?.tap()
        let why = app.staticTexts["money-category-remove-failure"]
        for _ in 0..<6 where !why.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(why.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(why.label.contains("عليها حركات مسجّلة"), why.label)
    }
}
