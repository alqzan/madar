import XCTest
@MainActor final class QuranPlanSetupUITests:XCTestCase {
    func testFourStepsSummarySaveNewVersionAndRetainHistory() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        XCTAssertTrue(app.buttons["quran-plan-edit"].waitForExistence(timeout:10));app.buttons["quran-plan-edit"].tap()
        XCTAssertTrue(app.buttons["quran-setup-continue"].waitForExistence(timeout:10));capture(app,"M2-V13-start-L")
        app.buttons["quran-setup-custom"].tap()
        XCTAssertTrue(app.steppers["quran-setup-page"].waitForExistence(timeout:5));app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-unit-quarter"].tap();capture(app,"M2-V13-amount-L");app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-rhythm-light"].tap();app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-rest-none"].tap();app.buttons["quran-setup-next"].tap();capture(app,"M2-V13-summary-L")
        app.buttons["quran-setup-next"].tap();XCTAssertTrue(app.buttons["quran-plan-edit"].waitForExistence(timeout:10))
        for _ in 0..<5 { if app.staticTexts["quran-plan-version"].isHittable { break };app.swipeUp() }
        XCTAssertTrue(app.staticTexts["quran-plan-version"].label.contains("٢"))
        for _ in 0..<6 { if app.buttons["quran-screen-close"].isHittable { break };app.swipeDown() }
        app.buttons["quran-screen-close"].tap();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["quran-coverage-title"].label.contains("١٤"))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
