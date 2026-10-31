import XCTest

@MainActor final class MoneyCardsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ app: XCUIApplication, fixture: String, rootRouteHarness: Bool = false, saveHoldMS: Int? = nil) {
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        if rootRouteHarness { app.launchEnvironment["MADAR_UI_MONEY_ROOT_ROUTE_HARNESS"] = "1" }
        if let saveHoldMS { app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"] = String(saveHoldMS) }
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10)); money.tap()
        let cards = app.buttons["money-cards-open"]; XCTAssertTrue(cards.waitForExistence(timeout: 10))
        for _ in 0..<8 where !cards.isHittable { app.swipeUp(velocity: .slow) }; cards.tap()
        XCTAssertTrue(app.buttons["money-cards-close"].waitForExistence(timeout: 10))
    }
    func testFourTabsSourcesAndDebit() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app, fixture: "cards")
        let statement = app.buttons["money-card-statement-source"]; XCTAssertTrue(statement.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["money-card-billed"].label.contains("٦٬٨٠٠"))
        shot(app, "M5-V12-cards-1-L")
        statement.tap(); XCTAssertTrue(app.staticTexts["الرسالة المصدر"].waitForExistence(timeout: 5)); shot(app, "M5-V12-card-source-L"); app.swipeDown(velocity: .fast)
        app.buttons["money-cards-tab-متى يخرج النقد"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-card-cashflow"].waitForExistence(timeout: 5))
        let timeline = app.descendants(matching: .any)["money-card-cashflow-timeline"].firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(timeline.label.contains("نوفمبر"), timeline.label)
        XCTAssertTrue(timeline.label.contains("جمادى"), timeline.label)
        shot(app, "M5-V12-cards-2-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V12-cards-2-s1-L"); app.swipeDown(velocity: .fast)
        app.buttons["money-cards-tab-تقويم السداد"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-card-calendar-grid"].waitForExistence(timeout: 5)); shot(app, "M5-V12-cards-3-L")
        app.swipeUp(velocity: .slow); shot(app, "M5-V12-cards-3-s1-L"); app.swipeDown(velocity: .fast)
        app.buttons["money-cards-tab-المطابقة"].tap()
        let payment = app.buttons["money-card-payment-source"]; XCTAssertTrue(payment.waitForExistence(timeout: 5)); shot(app, "M5-V12-cards-4-L")
        payment.tap(); XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ينقص النقد والدين معًا")).firstMatch.waitForExistence(timeout: 5)); app.swipeDown(velocity: .fast)
        let debit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-card-بطاقة مدى-")).firstMatch
        let strip = app.scrollViews["money-card-strip"]
        // AX includes the card's outer shadow; the tappable centre must be inside the strip.
        XCTAssertTrue(debit.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(strip.exists, app.debugDescription)
        for _ in 0..<6 where debit.frame.midX < strip.frame.minX + 20 || debit.frame.midX > strip.frame.maxX - 20 {
            if debit.frame.midX < strip.frame.minX + 20 { strip.swipeRight() } else { strip.swipeLeft() }
        }
        XCTAssertGreaterThanOrEqual(debit.frame.midX, strip.frame.minX + 20)
        XCTAssertLessThanOrEqual(debit.frame.midX, strip.frame.maxX - 20)
        XCTAssertTrue(debit.isHittable); debit.tap(); app.buttons["money-cards-tab-نظرة"].tap()
        XCTAssertTrue(app.staticTexts["تُخصم مشتريات مدى من الحساب مباشرة"].waitForExistence(timeout: 5))
    }
    /// 21 Oct 2026: a card can be added from the cards page (before, `money.saveCard` had no screen).
    func testAddCardFromCardsPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app, fixture: "zero")
        app.buttons["money-cards-add"].tap()
        let name = app.textFields["money-card-name"]; XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap(); name.typeText("بطاقة البقالة")
        let bank = app.textFields["money-card-bank"]; bank.tap(); bank.typeText("بنك التجربة")
        let last4 = app.textFields["money-card-last4"]; last4.tap(); last4.typeText("4512")
        app.buttons["money-card-keyboard-done"].firstMatch.tap()
        let account = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-card-account-")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
        if !account.isSelected { account.tap() }
        shot(app, "money-card-add-L")
        let save = app.buttons["money-card-save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp(velocity: .slow) }
        save.tap()
        let added = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "بطاقة البقالة")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "money-card-added-L")
    }

    func testHiddenAmountsAndEmptyCards() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app, fixture: "cardsHidden")
        XCTAssertEqual(app.staticTexts["money-card-billed"].label, "•••")
        let reveal = app.buttons["money-cards-reveal"]; XCTAssertTrue(reveal.exists); reveal.tap()
        XCTAssertTrue(app.staticTexts["money-card-billed"].label.contains("٦٬٨٠٠"))
        app.terminate(); open(app, fixture: "empty")
        XCTAssertTrue(app.staticTexts["لا بطاقات بعد"].waitForExistence(timeout: 5))
    }

    func testMoneyRootWaitsForNewCardDraftThenReturnsAfterSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app, fixture: "zero", rootRouteHarness: true)
        app.buttons["money-cards-add"].tap()
        let name = app.textFields["money-card-name"]; XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap(); name.typeText("بطاقة الرابط")
        let bank = app.textFields["money-card-bank"]; bank.tap(); bank.typeText("مصرف الاختبار")
        let last4 = app.textFields["money-card-last4"]; last4.tap(); last4.typeText("4826")
        app.buttons["money-card-keyboard-done"].firstMatch.tap()
        let route = app.buttons["money-root-test-route"]
        for _ in 0..<5 where !route.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(route.isHittable, app.debugDescription); route.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "بطاقة الرابط")
        let save = app.buttons["money-card-save"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(save.isEnabled, app.debugDescription); save.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 15), app.debugDescription)
    }
    func testMoneyCardFieldsStayDisabledAndRootWaitsDuringSave() {
        continueAfterFailure = false
        let app = XCUIApplication(); open(app, fixture: "zero", rootRouteHarness: true, saveHoldMS: 3500)
        app.buttons["money-cards-add"].tap()
        let name = app.textFields["money-card-name"]; XCTAssertTrue(name.waitForExistence(timeout: 8), app.debugDescription)
        name.tap(); name.typeText("بطاقة تنتظر الحفظ")
        let bank = app.textFields["money-card-bank"]; bank.tap(); bank.typeText("مصرف الاختبار")
        let last4 = app.textFields["money-card-last4"]; last4.tap(); last4.typeText("6734")
        app.buttons["money-card-keyboard-done"].firstMatch.tap()
        let save = app.buttons["money-card-save"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(save.isEnabled, app.debugDescription); save.tap()
        XCTAssertFalse(name.isEnabled, "Card fields cannot change after the save payload has been captured.")
        XCTAssertFalse(bank.isEnabled, app.debugDescription)
        XCTAssertFalse(last4.isEnabled, app.debugDescription)
        let route = app.buttons["money-root-test-route"]
        for _ in 0..<8 where !route.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(route.isHittable, app.debugDescription); route.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3), "The money root must wait while the card is saving.")
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()
    }
}
