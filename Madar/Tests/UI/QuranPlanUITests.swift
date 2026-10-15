import XCTest
@MainActor final class QuranPlanUITests:XCTestCase {
    func testHabitualSettingsForecastRelaunchAndUndo() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.staticTexts["quran-plan-forecast"].waitForExistence(timeout:10));capture(app,"M2-V12-plan-L")
        XCTAssertTrue(app.staticTexts["quran-plan-forecast-secondary"].exists); XCTAssertTrue(app.staticTexts["quran-plan-forecast-secondary"].label.contains(" م"))
        let before=app.staticTexts["quran-plan-forecast"].label
        app.buttons["quran-plan-quran.hifzLevel"].tap();app.buttons["quran-plan-option-quran.hifzLevel-deep"].tap()
        XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].label.contains("عميق"));XCTAssertNotEqual(app.staticTexts["quran-plan-forecast"].label,before)
        app.terminate();app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["quran-plan-quran.hifzLevel"].label.contains("عميق"))
        for _ in 0..<5 { if app.buttons["quran-plan-miss-spread"].isHittable { break };app.swipeUp() }
        capture(app,"M2-V12-policy-L");app.buttons["quran-plan-miss-spread"].tap()
        app.otherElements["quran-plan-undo"].buttons["undo-button"].tap()
        XCTAssertTrue(app.buttons["quran-plan-miss-ask"].waitForExistence(timeout:5))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
