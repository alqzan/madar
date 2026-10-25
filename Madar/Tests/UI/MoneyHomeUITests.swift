import XCTest

@MainActor final class MoneyHomeUITests: XCTestCase {
    func app(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    func open(_ app: XCUIApplication) {
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        XCTAssertTrue(app.staticTexts["money-title"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// Owner-data walk 25 Oct: after the drawer pages, the basis sheet stopped opening. Open each page, come back,
    /// and require the basis sheet after every one, from the money tab as the walk does.
    func testBasisSheetStillOpensAfterEveryDrawerPage() throws {
        continueAfterFailure = true
        let app = app("showcase")
        let tab = app.tabBars.buttons["المال"].firstMatch
        if tab.waitForExistence(timeout: 15) { tab.tap() }
        if !app.buttons["money-expense-open"].waitForExistence(timeout: 8) { open(app) }
        func top() { for _ in 0..<6 { app.swipeDown(velocity: .fast) } }
        func basis(after page: String) {
            top()
            let open = app.buttons.matching(identifier: "money-basis-open").firstMatch
            XCTAssertTrue(open.waitForExistence(timeout: 10), page); open.tap()
            let close = app.buttons["money-page-close"]
            guard close.waitForExistence(timeout: 8) else { XCTFail("Basis sheet did not open after " + page); shot(app, "basis-blocked-after-" + page); return }
            close.tap(); _ = close.waitForNonExistence(timeout: 5)
        }
        basis(after: "launch")
        for page in ["accounts", "categories", "envelopes", "obligations", "cards", "analysis", "reconcile", "cashback", "goal", "zakat", "settings"] {
            top()
            let door = app.buttons["money-\(page)-open"]
            for _ in 0..<8 where !door.isHittable || door.frame.maxY > app.windows.firstMatch.frame.maxY * 0.7 { app.swipeUp(velocity: .slow) }
            guard door.exists, door.isHittable else { XCTFail("Unreachable " + page); continue }
            door.tap(); Thread.sleep(forTimeInterval: 1.5)
            let close = app.buttons["money-\(page)-close"], back = app.buttons["money-\(page)-back"]
            for _ in 0..<8 where !close.isHittable && !back.isHittable { app.swipeDown(velocity: .fast) }
            if close.exists && close.isHittable { close.tap() } else if back.exists && back.isHittable { back.tap() } else { XCTFail("No close on " + page); continue }
            Thread.sleep(forTimeInterval: 1)
            basis(after: page)
        }
    }
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func assertChartDates(_ chart: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let dateRange = chart.label.components(separatedBy: "؛").first ?? chart.label
        let dates = dateRange.components(separatedBy: " إلى ")
        XCTAssertEqual(dates.count, 2, chart.label, file: file, line: line)
        for date in dates {
            XCTAssertTrue(date.contains("،"), "A chart endpoint must include both calendars: \(chart.label)", file: file, line: line)
        }
    }
    func testHomeReadsActualCycleAndHasNoUnbuiltDoors() throws {
        continueAfterFailure = false; let app = app("showcase"); open(app)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("١٤٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-today"].label.contains("٤٠٠"), app.staticTexts["money-today"].label)
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"), app.staticTexts["money-available"].label)
        let chart = app.descendants(matching: .any)["money-scroll-chart"]
        XCTAssertTrue(chart.exists)
        assertChartDates(chart)
        XCTAssertTrue(app.descendants(matching: .any)["money-pending"].exists)
        // V14 analysis and V17 manual expense are both built; each must have a live door.
        XCTAssertTrue(app.buttons["سجّل مصروفًا"].exists); XCTAssertTrue(app.buttons["money-analysis-open"].exists)
        shot(app, "M5-V01-home-L"); app.swipeUp(velocity: .slow); shot(app, "M5-V01-home-s1-L")
        XCTAssertTrue(app.staticTexts["الالتزامات"].exists)
        app.buttons["money-back"].tap(); XCTAssertTrue(app.buttons["money-open"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app); XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
    }
    func testEmptyAndHiddenAmountsAreHonest() throws {
        continueAfterFailure = false; var app = app("empty"); open(app)
        XCTAssertTrue(app.descendants(matching: .any)["money-empty"].exists); XCTAssertFalse(app.staticTexts["money-available"].exists)
        shot(app, "M5-V01-empty-L")
        let create = app.buttons["money-envelope-empty-create"]
        XCTAssertTrue(create.exists)
        for _ in 0..<8 {
            if create.frame.minY > 80 && create.frame.maxY < app.frame.maxY - 220 { break }
            if create.frame.minY <= 80 { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertLessThan(create.frame.maxY, app.frame.maxY - 220, "Capture the actual card above the floating bar")
        XCTAssertEqual(app.staticTexts["money-reserve"].label, "لم يبدأ بعد")
        XCTAssertEqual(app.staticTexts["money-surplus"].label, "يتجمع مع دوراتك")
        shot(app, "M5-18-empty-envelope-L"); create.tap()
        XCTAssertTrue(app.buttons["money-goal-edit"].waitForExistence(timeout: 10))
        app.terminate()
        app = self.app("hidden"); open(app)
        XCTAssertEqual(app.staticTexts["money-available"].label, "•••")
        let chart = app.descendants(matching: .any)["money-scroll-chart"]
        XCTAssertEqual(chart.label, "منحنى الدورة مخفي")
        shot(app, "M5-V01-hidden-L"); app.buttons["money-reveal"].tap()
        XCTAssertTrue(app.staticTexts["money-available"].label.contains("١٬٣٦٠"))
        assertChartDates(chart)
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

    func testUnknownBalancesStayUnknownInBasisCashAndTheirSources() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_ALL_BALANCES_UNKNOWN": "1", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); open(app)
        XCTAssertEqual(app.staticTexts["money-net"].label, "—")
        app.buttons["money-basis-open"].tap()
        let cash = app.buttons["money-cash-open"]; XCTAssertTrue(cash.waitForExistence(timeout: 10))
        shot(app, "M5-V02-unknown-basis-L")
        XCTAssertTrue(cash.label.contains("—"), cash.label)
        XCTAssertEqual(app.staticTexts["money-basis-unallocated"].label, "—")
        XCTAssertEqual(app.staticTexts["money-basis-remainder"].label, "—")
        cash.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-cash"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["money-cash-total"].label, "—")
        XCTAssertEqual(app.staticTexts["money-cash-net"].label, "—")
        shot(app, "M5-V02-unknown-cash-L")
        let account = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-source-account:")).firstMatch
        for _ in 0..<5 where !account.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(account.exists); XCTAssertTrue(account.label.contains("لم يُعرف رصيدها بعد"), account.label)
        shot(app, "M5-V02-unknown-cash-s1-L")
        account.tap()
        XCTAssertTrue(app.staticTexts["لم يُعرف رصيدها بعد"].waitForExistence(timeout: 10))
        shot(app, "M5-V02-unknown-source-L")
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
