import XCTest

@MainActor final class MoneyHomeUITests: XCTestCase {
    func app(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    func open(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testHomeReadsActualCycleAndHasNoUnbuiltDoors() throws {
        continueAfterFailure = false; let app = app("showcase"); open(app)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("١٤٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("٤٠٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"), app.staticTexts["money-available"].label)
        XCTAssertTrue(app.descendants(matching: .any)["money-scroll-chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["money-pending"].exists)
        // «التحليل» is built (M5-V14), so its door is now expected; manual add still is not.
        XCTAssertFalse(app.buttons["سجّل مصروفًا"].exists); XCTAssertTrue(app.buttons["money-analysis-open"].exists)
        shot(app, "M5-V01-home-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V01-home-s1-L")
        XCTAssertTrue(app.staticTexts["الالتزامات"].exists)
        app.buttons["money-back"].tap(); XCTAssertTrue(app.buttons["money-open"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app); XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
    }
    func testEmptyAndHiddenAmountsAreHonest() throws {
        continueAfterFailure = false; var app = app("empty"); open(app)
        XCTAssertTrue(app.descendants(matching: .any)["money-empty"].exists); XCTAssertFalse(app.staticTexts["money-available"].exists)
        shot(app, "M5-V01-empty-L"); app.terminate()
        app = self.app("hidden"); open(app)
        XCTAssertEqual(app.staticTexts["money-available"].label, "•••")
        shot(app, "M5-V01-hidden-L"); app.buttons["money-reveal"].tap()
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
        app.buttons["money-back"].tap(); app.buttons["money-open"].tap()
        XCTAssertEqual(app.staticTexts["money-available"].label, "•••")
    }
    func testBasisCashAndSourcesExplainTheSameMoney() throws {
        continueAfterFailure = false; let app = app("showcase"); open(app)
        app.buttons["money-basis-open"].tap()
        let cashOpen = app.buttons["money-cash-open"]
        XCTAssertTrue(cashOpen.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(cashOpen.label.contains("١١٨٬٧٠٠"), cashOpen.label)
        XCTAssertTrue(app.staticTexts["money-basis-unallocated"].label.contains("١٢٬٤٠٢"), app.staticTexts["money-basis-unallocated"].label)
        shot(app, "M5-V02-basis-L")
        let envelopes = app.buttons["money-basis-source-envelopes"]; envelopes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-source"].waitForExistence(timeout: 5))
        shot(app, "M5-V02-source-L"); app.buttons["money-page-close"].firstMatch.tap()
        cashOpen.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-cash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["money-cash-total"].label.contains("١٢٨٬٥٠٠"))
        XCTAssertTrue(app.staticTexts["money-cash-net"].label.contains("١١٨٬٧٠٠"))
        shot(app, "M5-V02-cash-L")
        let debt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-cash-debt-statement:")).firstMatch
        XCTAssertTrue(debt.exists); debt.tap(); XCTAssertTrue(app.descendants(matching: .any)["money-source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["تقريبًا، تاريخ القفل مقدّر"].exists)
        shot(app, "M5-V02-card-source-L")
    }

    func testNegativeNetUsesExplicitAmountsWithoutAPositiveColumn() throws {
        continueAfterFailure = false; let app = app("shortfall"); open(app)
        app.buttons["money-basis-open"].tap()
        let cash = app.buttons["money-cash-open"]; XCTAssertTrue(cash.waitForExistence(timeout: 10))
        XCTAssertTrue(cash.label.contains("−٩٬٣٠٠"), cash.label)
        shot(app, "M5-V02-shortfall-L"); cash.tap()
        XCTAssertTrue(app.staticTexts["ما عليك أكثر من النقد المسجّل."].waitForExistence(timeout: 5))
        shot(app, "M5-V02-shortfall-cash-L")
    }

}
