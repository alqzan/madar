import XCTest

@MainActor final class MoneyCashbackUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openJar(fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch(); let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
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
        // The months: Jumada I 1448 is still gathering; choosing Muharram names it in both calendars.
        XCTAssertTrue(app.descendants(matching: .any)["money-cashback-selected"].firstMatch.label.contains("يتجمّع"))
        app.swipeUp(velocity: .slow)
        let muharram = app.buttons["money-cashback-month-0"]; XCTAssertTrue(muharram.waitForExistence(timeout: 5)); muharram.tap()
        let selected = app.descendants(matching: .any)["money-cashback-selected"].firstMatch
        XCTAssertTrue(selected.label.contains("محرم") && (selected.label.contains("يونيو") || selected.label.contains("يوليو")))
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
