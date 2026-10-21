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
        search.tap(); search.typeText("salah.askReminder\n")
        let prayerAsk = app.switches["setting-salah.askReminder"]
        XCTAssertTrue(prayerAsk.waitForExistence(timeout: 10), app.debugDescription)
        if (prayerAsk.value as? String) != "0" { prayerAsk.tap() }

        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32)); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let categories = app.buttons["money-categories-open"]; XCTAssertTrue(categories.waitForExistence(timeout: 10))
        for _ in 0..<6 where !categories.isHittable { app.swipeUp(velocity: .slow) }
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
        app.terminate()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard"); springboard.activate()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)))
        let body = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "اقترب أحد تصنيفاتك من حدّه لهذه الدورة")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 2_400), springboard.debugDescription)
        XCTAssertNil(body.label.rangeOfCharacter(from: .decimalDigits), body.label)
        XCTAssertFalse(body.label.contains("مطاعم"), body.label)
        shot(springboard, "M5-V10-a80-real-privacy-safe-L")
    }
}
