import XCTest

/// Phase 3 (owner, 11 Nov 2026): «يتكرر», instalment and statement dues, the refund's purchase chooser and the fee lines of a movement.
@MainActor final class MoneyPhase3UITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "phase3",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    private func openMoney(_ app: XCUIApplication) {
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
    }
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<12 where !element.exists || !element.isHittable { app.swipeUp(velocity: .slow) }
    }

    func testHomeShowsRecurringAndInstalmentAndStatementDues() throws {
        continueAfterFailure = false
        let app = launch(); openMoney(app)
        let recurring = app.descendants(matching: .any)["money-recurring"].firstMatch
        for _ in 0..<12 where !recurring.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(recurring.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["money-recurring-salary-جهة العمل"].firstMatch.exists, "the salary line is listed")
        XCTAssertTrue(app.descendants(matching: .any)["money-recurring-line-منصة شاهد"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["money-recurring-price-change"].firstMatch.exists, "the price rise is noted")
        XCTAssertTrue(app.staticTexts["money-recurring-late"].firstMatch.exists, "the overdue charge is noted")
        let dues = app.descendants(matching: .any)["money-dues"].firstMatch
        for _ in 0..<6 where !dues.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(dues.waitForExistence(timeout: 10), app.debugDescription)
        // The Tamara instalment names its number, count and what is left; the statement shows its card and minimum.
        let instalment = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'money-instalment-'")).firstMatch
        for _ in 0..<6 where !instalment.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(instalment.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(instalment.label.contains("القسط ٢ من ٤"), instalment.label)
        XCTAssertTrue(instalment.label.contains("المتبقي"), instalment.label)
        let minimum = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'money-due-minimum-'")).firstMatch
        XCTAssertTrue(minimum.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(minimum.label.contains("الحد الأدنى"), minimum.label)
        XCTAssertTrue(minimum.label.contains("٢١٣"), minimum.label)
        let statement = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'money-due-' AND label CONTAINS '٨٨٤٤'")).firstMatch
        XCTAssertTrue(statement.exists, "the statement row names its card tail")
    }

    func testRefundDraftNamesItsPurchaseAndOffersAChoice() throws {
        continueAfterFailure = false
        let app = launch(); openMoney(app)
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let chooser = app.buttons["money-refund-chooser"].firstMatch
        for _ in 0..<8 where !chooser.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(chooser.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["money-refund-origin"].exists, "two equal purchases: none is named before a choice")
        scrollTo(app, chooser); chooser.tap()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'money-refund-choice-'")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        let origin = app.staticTexts["money-refund-origin"].firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 5)); XCTAssertTrue(origin.label.contains("مرتجع من"), origin.label)
    }

    func testMovementDetailShowsForeignFiguresAndFees() throws {
        continueAfterFailure = false
        let app = launch(); openMoney(app)
        let log = app.buttons["money-log-open"]; XCTAssertTrue(log.waitForExistence(timeout: 10)); scrollTo(app, log); log.tap()
        XCTAssertTrue(app.otherElements["money-log-arcade"].waitForExistence(timeout: 10))
        let row = app.buttons["money-log-row-متجر خارجي"]; XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription); row.tap()
        let charges = app.descendants(matching: .any)["money-charges"].firstMatch
        XCTAssertTrue(charges.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["money-charges-original"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-charges-rate"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-charges-fee"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-charges-vat"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-charges-foreign-fee"].firstMatch.exists)
    }
}
