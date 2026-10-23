import XCTest

@MainActor final class MoneyCashbackUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openJar(fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let open = app.buttons["money-cashback-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); for _ in 0..<8 where !open.isHittable { app.swipeUp(velocity: .slow) }; open.tap()
        return app
    }

    func testJarMonthsSwitchAndRate() throws {
        continueAfterFailure = false
        let app = openJar(fixture: "cashback")
        let headline = app.descendants(matching: .any)["money-cashback-headline"].firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 10)); XCTAssertFalse(headline.label.contains("•••"))
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-landed"].firstMatch.label.contains("نزل"))
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-yearend"].exists, "Four complete months: the year end is drawn")
        XCTAssertTrue(app.buttons["money-cashback-card-بطاقة مدى"].label.contains("غير معروفة"))
        XCTAssertFalse(app.buttons["اعتمد النقل"].exists, "No entry point that stores nothing")
        sleep(2); shot(app, "M5-V16-cb-1-L")
        // Owner default: Gregorian first. October is gathering; January names both calendars.
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-selected"].firstMatch.label.contains("يتجمّع"))
        app.swipeUp(velocity: .slow)
        let january = app.buttons["money-cashback-month-0"]; XCTAssertTrue(january.waitForExistence(timeout: 5)); january.tap()
        let selected = app.descendants(matching: .any)["money-cashback-selected"].firstMatch
        XCTAssertTrue(selected.label.contains("يناير") && selected.label.contains("رجب"), selected.label)
        let chip = app.buttons["money-cashback-chip-بقالة"]; XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-chip-detail"].firstMatch.label.contains("بطاقة السفر"))
        shot(app, "M5-V16-cb-1-s1-L")
        // Enter the debit card's unknown rate, then undo it.
        app.swipeDown(velocity: .fast)
        app.buttons["money-cashback-card-بطاقة مدى"].tap()
        let value = app.descendants(matching: .any)["money-cashback-rate-value"].firstMatch; XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["money-cashback-rate-save"].isEnabled, "An unknown rate is not pre-filled")
        app.buttons["money-cashback-rate-chip-100"].tap(); app.buttons["money-cashback-rate-minus"].tap(); app.buttons["money-cashback-rate-minus"].tap()
        XCTAssertTrue(value.label.contains("٠٫٥") && !value.label.contains("٠٫٥٠"), value.label)
        shot(app, "M5-V16-rate-L")
        app.buttons["money-cashback-rate-save"].tap()
        let debit = app.buttons["money-cashback-card-بطاقة مدى"]
        XCTAssertTrue(debit.waitForExistence(timeout: 5))
        let entered = NSPredicate(format: "label CONTAINS %@", "٠٫٥")
        expectation(for: entered, evaluatedWith: debit); waitForExpectations(timeout: 5)
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "غير معروفة"), evaluatedWith: debit); waitForExpectations(timeout: 5)

        // A chosen destination is a persistent setting with one glass undo toast.
        let destinations = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-cashback-destination-"))
        for _ in 0..<12 where destinations.count < 2 || !destinations.element(boundBy: 1).isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(destinations.count, 7, "Surplus appears once alongside the reserve and five goal envelopes")
        XCTAssertTrue(destinations.element(boundBy: 6).isHittable, "The compact grid keeps every destination clear of the bottom navigation")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "الاحتياطي")).count, 1)
        let surplus = destinations.element(boundBy: 0), envelope = destinations.element(boundBy: 1)
        XCTAssertTrue(surplus.isEnabled); XCTAssertTrue(envelope.isEnabled)
        XCTAssertTrue(surplus.label.contains("الوجهة المختارة")); XCTAssertFalse(envelope.label.contains("الوجهة المختارة"))
        envelope.tap()
        let destinationUndo = app.buttons["تراجع"]; XCTAssertTrue(destinationUndo.waitForExistence(timeout: 5)); destinationUndo.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "الوجهة المختارة"), evaluatedWith: surplus)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(envelope.label.contains("الوجهة المختارة"))
        envelope.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "الوجهة المختارة"), evaluatedWith: envelope)
        waitForExpectations(timeout: 5)
        surplus.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "الوجهة المختارة"), evaluatedWith: surplus)
        waitForExpectations(timeout: 5)
        envelope.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "الوجهة المختارة"), evaluatedWith: envelope)
        waitForExpectations(timeout: 5)
        sleep(1); shot(app, "M5-V16-cashback-destination-glass-L")
    }

    func testPreferredCardIsSavedAndOfferedForExplicitExpenseSelection() throws {
        continueAfterFailure = false
        let app = openJar(fixture: "cashback")
        let groceries = app.buttons["money-cashback-chip-بقالة"]
        for _ in 0..<10 where !groceries.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(groceries.waitForExistence(timeout: 8)); groceries.tap()
        let preference = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-cashback-preferred-card-")).firstMatch
        XCTAssertTrue(preference.waitForExistence(timeout: 8))
        XCTAssertTrue(preference.label.contains("بطاقة السفر"))
        preference.tap()
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(preference.waitForExistence(timeout: 5))
        XCTAssertTrue(preference.label.contains("اجعل"), preference.label)
        preference.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout: 5))
        XCTAssertTrue(preference.label.contains("أزل"), preference.label)

        app.buttons["money-cashback-close"].tap()
        let expense = app.buttons["money-expense-open"]
        for _ in 0..<10 where !expense.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expense.waitForExistence(timeout: 8)); expense.tap()
        let category = app.buttons["money-expense-category"]; XCTAssertTrue(category.waitForExistence(timeout: 8)); category.tap()
        let groceriesOption = app.buttons["بقالة"]; XCTAssertTrue(groceriesOption.waitForExistence(timeout: 5)); groceriesOption.tap()
        let preferredName = app.staticTexts["money-expense-preferred-card-name"]
        XCTAssertTrue(preferredName.waitForExistence(timeout: 8)); XCTAssertTrue(preferredName.label.contains("بطاقة السفر"))
        let useCard = app.buttons["money-expense-preferred-card-use"]
        XCTAssertTrue(useCard.exists); XCTAssertTrue(useCard.label.contains("استخدمها"))
        useCard.tap()
        XCTAssertTrue(useCard.label.contains("مختارة للدفع"))
        shot(app, "M5-V16-preferred-card-expense-L")
    }

    func testHiddenAmountsCardsDoorAndEmptyStore() throws {
        continueAfterFailure = false
        let app = openJar(fixture: "cashbackHidden")
        let headline = app.descendants(matching: .any)["money-cashback-headline"].firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 10)); XCTAssertTrue(headline.label.contains("•••"))
        XCTAssertFalse(app.descendants(matching: .any)["money-cashback-yearend"].exists, "No year-end line while amounts are hidden")
        shot(app, "M5-V16-hidden-L")
        app.buttons["money-cashback-reveal"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["money-cashback-headline"].firstMatch.label.contains("•••"))
        // Nothing landed yet: the page says it is an estimate, not money that came back.
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-landed"].firstMatch.label.contains("لم ينزل"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "كسبته بطاقاتك")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-approx"].exists)
        sleep(2); shot(app, "M5-V16-estimate-L")
        // The same jar from «البطاقات».
        app.buttons["money-cashback-close"].tap()
        let cards = app.buttons["money-cards-open"]; for _ in 0..<8 where !cards.isHittable { app.swipeUp(velocity: .slow) }; cards.tap()
        let door = app.buttons["money-cards-cashback-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-headline"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()

        let empty = openJar(fixture: "empty")
        XCTAssertTrue(empty.descendants(matching: .any)["money-cashback-empty"].waitForExistence(timeout: 10))
        shot(empty, "M5-V16-empty-L")
    }
}
