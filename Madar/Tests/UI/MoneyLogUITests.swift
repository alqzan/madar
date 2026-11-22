import XCTest

@MainActor final class MoneyLogUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testArcadeMonthSelectionSearchAndSource() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "cards", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let log = app.buttons["money-log-open"]; XCTAssertTrue(log.waitForExistence(timeout: 10)); for _ in 0..<8 where !log.isHittable { app.swipeUp(velocity: .slow) }; log.tap()
        XCTAssertTrue(app.otherElements["money-log-arcade"].waitForExistence(timeout: 10)); shot(app, "M5-V13-log-4-L")
        let movement = app.buttons["money-log-row-متجر الأجهزة"]; XCTAssertTrue(movement.waitForExistence(timeout: 5))
        for _ in 0..<4 where !movement.isHittable { app.swipeUp(velocity: .slow) }; movement.tap()
        XCTAssertTrue(app.staticTexts["خارج الميزانية"].waitForExistence(timeout: 5) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "خارج الميزانية")).firstMatch.exists); shot(app, "M5-V13-log-source-L"); app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let mode = app.buttons["money-log-mode"]; XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.tap()
        XCTAssertTrue(app.otherElements["money-log-month-grid"].waitForExistence(timeout: 5)); shot(app, "M5-V13-log-4x-L")
        let previous = app.buttons["money-log-day-2026-10-15"]; XCTAssertTrue(previous.exists); previous.tap()
        XCTAssertTrue(app.otherElements["money-log-detail"].exists)
        app.swipeDown(velocity: .fast)
        app.buttons["money-log-search-open"].tap()
        let field = app.textFields["money-log-search"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("غيرموجود\n")
        XCTAssertTrue(app.staticTexts["money-log-search-empty"].waitForExistence(timeout: 5))
        app.buttons["مسح البحث"].tap(); XCTAssertTrue(app.otherElements["money-log-month-grid"].exists)
        app.buttons["money-log-filter-transfers"].tap()
        XCTAssertTrue(app.staticTexts["money-log-empty"].waitForExistence(timeout: 5))
        app.buttons["money-log-search-open"].tap()
        let filteredSearch = app.textFields["money-log-search"]
        XCTAssertTrue(filteredSearch.waitForExistence(timeout: 5)); filteredSearch.tap(); filteredSearch.typeText("متجر الأدوات\n")
        XCTAssertTrue(app.staticTexts["money-log-search-empty"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["مسح البحث"].tap()
        app.buttons["money-log-filter-all"].tap()
        let restored = app.buttons["money-log-row-مصروف"]
        for _ in 0..<6 where !restored.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        let months = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'money-log-month-'"))
        XCTAssertGreaterThanOrEqual(months.count, 2)
        for _ in 0..<5 where !months.element(boundBy: 0).isHittable { app.swipeDown(velocity: .fast) }
        let currentID = months.element(boundBy: 0).identifier
        months.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["money-log-day-2026-10-16"].waitForNonExistence(timeout: 5))
        app.buttons[currentID].tap()
        XCTAssertTrue(app.buttons["money-log-day-2026-10-16"].waitForExistence(timeout: 5))
    }

    func testSearchHidesAmountsUntilTheUserRevealsThem() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "cardsHidden", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let settingsSearch = app.textFields["settings-search"]; XCTAssertTrue(settingsSearch.waitForExistence(timeout: 10)); settingsSearch.tap(); settingsSearch.typeText("المال")
        app.buttons["money-open"].tap()
        let log = app.buttons["money-log-open"]; XCTAssertTrue(log.waitForExistence(timeout: 10)); for _ in 0..<8 where !log.isHittable { app.swipeUp(velocity: .slow) }; log.tap()
        XCTAssertTrue(app.otherElements["money-log-arcade"].waitForExistence(timeout: 10))
        app.buttons["money-log-search-open"].tap()
        let field = app.textFields["money-log-search"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("2300\n")
        XCTAssertTrue(app.staticTexts["money-log-search-empty"].waitForExistence(timeout: 5))
        app.buttons["money-log-reveal"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-log-search-result-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    }

    // Owner, 22 Nov 2026: correct or delete a confirmed movement from the log.
    private func openExpenseLog() -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let log = app.buttons["money-log-open"]; XCTAssertTrue(log.waitForExistence(timeout: 10)); for _ in 0..<8 where !log.isHittable { app.swipeUp(velocity: .slow) }; log.tap()
        XCTAssertTrue(app.otherElements["money-log-arcade"].waitForExistence(timeout: 10))
        let yesterday = app.buttons["money-log-day-2026-10-16"]; XCTAssertTrue(yesterday.waitForExistence(timeout: 5)); yesterday.tap()
        return app
    }
    private func tapRow(_ app: XCUIApplication, _ name: String) {
        let row = app.buttons["money-log-row-" + name]
        for _ in 0..<6 where !row.exists || !row.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription); row.tap()
    }
    func testEditingAConfirmedMovementChangesItsLabelAndAmount() throws {
        continueAfterFailure = false
        let app = openExpenseLog(); tapRow(app, "مقهى الزاوية")
        let label = app.textFields["money-edit-label"]; XCTAssertTrue(label.waitForExistence(timeout: 8), app.debugDescription)
        let save = app.buttons["money-edit-save"]; XCTAssertFalse(save.isEnabled, "Nothing changed yet.")
        XCTAssertTrue(app.textFields["money-edit-amount"].exists, "A plain purchase in an open cycle can change its amount.")
        label.tap(); label.typeText(" الجديد")
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(label.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["money-log-row-مقهى الزاوية الجديد"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testDeletingAConfirmedMovementAsksFirst() throws {
        continueAfterFailure = false
        let app = openExpenseLog(); tapRow(app, "متجر الحي")
        let delete = app.buttons["money-edit-delete"]; XCTAssertTrue(delete.waitForExistence(timeout: 8), app.debugDescription)
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "احذف الحركة")).allElementsBoundByIndex.last
        XCTAssertTrue(try XCTUnwrap(confirm).waitForExistence(timeout: 5), app.debugDescription); confirm?.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["money-log-row-متجر الحي"].waitForNonExistence(timeout: 10), app.debugDescription)
    }
}
