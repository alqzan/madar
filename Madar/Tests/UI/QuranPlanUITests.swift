import XCTest
@MainActor final class QuranPlanUITests:XCTestCase {
    func testDeepHabitualExampleShowsItsActualFractionalWird() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout: 25)); app.buttons["quran-streak"].tap()
        let level = app.buttons["quran-plan-quran.hifzLevel"]
        XCTAssertTrue(level.waitForExistence(timeout: 10)); level.tap()
        app.buttons["quran-plan-option-quran.hifzLevel-deep"].tap()
        let amount = app.staticTexts["quran-plan-example-amount"]
        for _ in 0..<8 where !amount.isHittable { app.swipeUp() }
        XCTAssertTrue(amount.isHittable)
        XCTAssertTrue(amount.label.contains("وجه ونصف"), amount.label)
        XCTAssertFalse(amount.label.contains("المقدار") || amount.label.contains("وحدة"))
        capture(app, "OR-21-fractional-wird-L")
    }
    func testForecastTrackComparesLevelsWithoutChangingTheHabitualSetting() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout: 25)); app.buttons["quran-streak"].tap()
        let forecast = app.staticTexts["quran-plan-forecast"]
        XCTAssertTrue(forecast.waitForExistence(timeout: 10)); let before = forecast.label
        let maximum = app.buttons["quran-plan-preview-max"]
        for _ in 0..<5 where !maximum.isHittable { app.swipeUp() }
        XCTAssertTrue(maximum.isHittable); maximum.tap()
        XCTAssertTrue(maximum.isSelected)
        XCTAssertNotEqual(forecast.label, before)
        XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].label.contains("متوسط"))
        capture(app, "OR-21-forecast-preview-max-L")
        let simple = app.buttons["quran-plan-preview-simple"]
        // Drag the existing four-stop track from its last stop to its first stop.
        maximum.press(forDuration: 0.1, thenDragTo: simple)
        XCTAssertTrue(simple.isSelected)
        capture(app, "OR-21-forecast-preview-simple-L")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout: 25)); app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.buttons["quran-plan-preview-medium"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quran-plan-preview-medium"].isSelected)
        XCTAssertEqual(forecast.label, before)
    }
    func testHabitualSettingsForecastRelaunchAndUndo() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.staticTexts["quran-plan-forecast"].waitForExistence(timeout:10));capture(app,"M2-V12-plan-L")
        XCTAssertTrue(app.staticTexts["quran-plan-forecast-secondary"].exists); XCTAssertTrue(app.staticTexts["quran-plan-forecast-secondary"].label.contains(" م"))
        let before=app.staticTexts["quran-plan-forecast"].label
        let level=app.buttons["quran-plan-quran.hifzLevel"];XCTAssertTrue(level.waitForExistence(timeout:10))
        let enabled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isEnabled == true"),object:level)
        XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:30),.completed,app.debugDescription)
        level.tap();let deep=app.buttons["quran-plan-option-quran.hifzLevel-deep"];XCTAssertTrue(deep.waitForExistence(timeout:10),app.debugDescription);deep.tap()
        XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].label.contains("عميق"));XCTAssertNotEqual(app.staticTexts["quran-plan-forecast"].label,before)
        app.terminate();app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].label.contains("عميق"))
        for _ in 0..<5 { if app.buttons["quran-plan-miss-spread"].isHittable { break };app.swipeUp() }
        capture(app,"M2-V12-policy-L");app.buttons["quran-plan-miss-spread"].tap()
        app.otherElements["quran-plan-undo"].buttons["undo-button"].tap()
        XCTAssertTrue(app.buttons["quran-plan-miss-ask"].waitForExistence(timeout:5))
    }
    func testMissedDayChartReflectsPolicyAndRestDaysAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        func openPlan() {
            XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout: 25)); app.buttons["quran-streak"].tap()
            XCTAssertTrue(app.staticTexts["quran-plan-forecast"].waitForExistence(timeout: 10))
        }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 where !element.isHittable { app.swipeUp() }
            if !element.isHittable { capture(app, "OR-21-chart-locator-diagnostic") }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        func bar(_ day: String) -> XCUIElement { app.descendants(matching: .any)["quran-plan-miss-preview-" + day] }
        app.launch(); openPlan()
        let forecast = app.staticTexts["quran-plan-forecast"].label
        let spread = app.buttons["quran-plan-miss-spread"]; reveal(spread); spread.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: spread)], timeout: 10) == .completed)
        reveal(bar("2026-10-19"))
        for day in ["2026-10-15", "2026-10-17", "2026-10-18"] {
            XCTAssertTrue(bar(day).label.contains("وردك وثلثه"), bar(day).label)
            XCTAssertTrue(bar(day).label.contains("أكتوبر") && bar(day).label.contains("جمادى"), bar(day).label)
        }
        XCTAssertFalse(bar("2026-10-16").exists)
        XCTAssertTrue(bar("2026-10-19").label.contains("وردك")); XCTAssertFalse(bar("2026-10-19").label.contains("ثلثه"))
        XCTAssertEqual(app.staticTexts["quran-plan-forecast"].label, forecast)
        app.swipeUp(velocity: .slow)
        capture(app, "OR-21-missed-spread-preview-L")
        let double = app.buttons["quran-plan-miss-double"]
        for _ in 0..<5 where !double.isHittable { app.swipeDown() }
        double.tap()
        reveal(bar("2026-10-19")); XCTAssertTrue(bar("2026-10-15").label.contains("وردان"))
        app.swipeUp(velocity: .slow)
        capture(app, "OR-21-missed-double-preview-L")
        app.terminate(); app.launch(); openPlan()
        reveal(app.buttons["quran-plan-miss-double"]); XCTAssertTrue(app.buttons["quran-plan-miss-double"].isSelected)
        reveal(bar("2026-10-19")); XCTAssertTrue(bar("2026-10-15").label.contains("وردان"))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
