import XCTest
@MainActor final class QuranFreeUITests:XCTestCase {
    func testSelectFreeRangeEnterOriginalPageAndDiscard() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 { if app.buttons["quran-tool-free"].isHittable { break };app.swipeUp() };app.buttons["quran-tool-free"].tap()
        XCTAssertTrue(app.buttons["quran-free-start"].waitForExistence(timeout:10));capture(app,"M2-V14-free-L")
        app.buttons["quran-free-start"].tap();XCTAssertTrue(app.buttons["quran-session-method"].waitForExistence(timeout:15));capture(app,"M2-V14-session-L")
        app.buttons["quran-session-close"].tap();app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(app.buttons["quran-free-start"].waitForExistence(timeout:10))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
