import XCTest

@MainActor final class MoneyAnalysisUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func openAnalysis(fixture: String, analysisHoldMS: String? = nil, analysisFailPeriod: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        if let analysisHoldMS { app.launchEnvironment["MADAR_UI_MONEY_ANALYSIS_READ_HOLD_MS"] = analysisHoldMS }
        if let analysisFailPeriod { app.launchEnvironment["MADAR_UI_MONEY_ANALYSIS_READ_FAIL_PERIOD"] = analysisFailPeriod }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let open = app.buttons["money-analysis-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); for _ in 0..<8 where !open.isHittable { app.swipeUp(velocity: .slow) }; open.tap()
        return app
    }

    /// FB-39 (owner, 6 Nov): the calendar month (October 2026 on the 16th) and the year as twelve months.
    func testMonthAndYearPeriods() throws {
        continueAfterFailure = false
        let app = openAnalysis(fixture: "analysis")
        let month = app.buttons["money-analysis-period-month"]; XCTAssertTrue(month.waitForExistence(timeout: 10), app.debugDescription); month.tap()
        let range = app.descendants(matching: .any)["money-analysis-range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5)); XCTAssertTrue(range.label.contains("أكتوبر") && range.label.contains("٢٠٢٦"), range.label)
        shot(app, "FB39-analysis-month-L")
        app.buttons["money-analysis-period-year"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-year"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(range.label.contains("سنة ٢٠٢٦"), range.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-month-10"].exists)
        shot(app, "FB39-analysis-year-L")
    }
    func testPeriodRefreshKeepsTheCurrentReadingVisible() throws {
        continueAfterFailure = false
        let app = openAnalysis(fixture: "analysis", analysisHoldMS: "2500")
        let range = app.descendants(matching: .any)["money-analysis-range"]
        XCTAssertTrue(range.waitForExistence(timeout: 15), app.debugDescription)
        let cycleRange = range.label
        let refreshing = app.descendants(matching: .any)["money-analysis-refreshing"]
        let initialSettled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: refreshing)
        XCTAssertEqual(XCTWaiter.wait(for: [initialSettled], timeout: 10), .completed)

        app.buttons["money-analysis-period-month"].tap()
        XCTAssertTrue(refreshing.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(range.label, cycleRange, "Keep the settled cycle reading visible while the month is loading")
        let updatedRange = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", cycleRange), object: range)
        XCTAssertEqual(XCTWaiter.wait(for: [updatedRange], timeout: 10), .completed)
        let refreshSettled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: refreshing)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshSettled], timeout: 5), .completed)
        XCTAssertTrue(range.label.contains("أكتوبر"))
        shot(app, "FB25-analysis-month-refreshed-L")
    }
    func testFailedPeriodRefreshDoesNotShowNumbersFromThePreviousPeriod() throws {
        continueAfterFailure = false
        let app = openAnalysis(fixture: "analysis", analysisFailPeriod: "month")
        let spent = app.descendants(matching: .any)["money-analysis-spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["money-analysis-period-month"].tap()
        let failed = app.descendants(matching: .any)["money-analysis-refresh-failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["money-analysis-period-month"].isSelected)
        XCTAssertFalse(spent.exists, "A cycle reading must not remain under the month selection after the month read fails")
        XCTAssertFalse(app.descendants(matching: .any)["money-analysis-range"].exists)
        shot(app, "FB25-analysis-month-read-failed-L")
    }
    func testCycleWeekDaySelectionAndHistory() throws {
        continueAfterFailure = false
        let app = openAnalysis(fixture: "analysis")
        // Opens on mal.analysisDefault = cycle.
        XCTAssertTrue(app.otherElements["money-analysis-chart"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["money-analysis-period-cycle"].isSelected)
        XCTAssertTrue(app.otherElements["money-analysis-compare"].exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "عن الأيام نفسها")).firstMatch.exists)
        // FB-39 (owner, 6 Nov): month and year joined v1; testMonthAndYearPeriods covers them.
        shot(app, "M5-V14-ana-1-L")
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-category-مطاعم"].exists)
        // Choosing a day writes nothing and names it with both calendars.
        let day = app.buttons["money-analysis-day-2026-10-08"]; XCTAssertTrue(day.exists); day.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-selected"].label.contains("أكتوبر"))
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-merchant-بقالة الحي"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-projection"].exists)
        app.swipeUp(velocity: .slow); shot(app, "M5-V14-ana-1-s1-L")
        app.swipeDown(velocity: .fast)
        // The earlier cycle, then back.
        app.buttons["money-analysis-previous"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-analysis-range"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["money-analysis-projection"].exists, "A finished cycle has no projection")
        app.buttons["money-analysis-next"].tap()
        // The week.
        app.buttons["money-analysis-period-week"].tap()
        XCTAssertTrue(app.buttons["money-analysis-period-week"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["money-analysis-period-week"].isSelected)
        XCTAssertTrue(app.buttons["money-analysis-day-2026-10-10"].exists && app.buttons["money-analysis-day-2026-10-16"].exists, "Saturday-first week (core.weekStart)")
        app.buttons["money-analysis-day-2026-10-14"].tap()
        shot(app, "M5-V14-ana-1x-L")
        app.swipeUp(velocity: .slow); shot(app, "M5-V14-ana-1x-s1-L")
    }

    func testHiddenAmountsAndEmptyStore() throws {
        continueAfterFailure = false
        let app = openAnalysis(fixture: "analysisHidden")
        let spent = app.descendants(matching: .any)["money-analysis-spent"].firstMatch
        XCTAssertTrue(spent.waitForExistence(timeout: 10)); XCTAssertTrue(spent.label.contains("•••"))
        XCTAssertFalse(app.descendants(matching: .any)["money-analysis-line"].exists, "No daily line while amounts are hidden")
        shot(app, "M5-V14-hidden-L")
        app.buttons["money-analysis-reveal"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["money-analysis-spent"].firstMatch.label.contains("•••"))
        app.terminate()

        let empty = openAnalysis(fixture: "empty")
        XCTAssertTrue(empty.descendants(matching: .any)["money-analysis-empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(empty.otherElements["money-analysis-chart"].exists)
        shot(empty, "M5-V14-empty-L")
    }
}
