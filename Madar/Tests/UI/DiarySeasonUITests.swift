import XCTest
@MainActor final class DiarySeasonUITests:XCTestCase {
    private func launch(_ variant:String,_ now:String,_ theme:String="light")->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":variant,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":theme,"MADAR_UI_NOW":now];app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap();XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout:10));return app
    }
    func testFridayFrameAndActualWeekRoute() throws {
        continueAfterFailure=false
        let app=launch("today","2026-10-16T16:00:00+03:00");XCTAssertEqual(app.staticTexts["diary-day-title"].label,"جمعة مباركة");capture(app,"M3-V14-friday-L");app.buttons["diary-week-open"].tap();XCTAssertTrue(app.buttons["diary-week-write"].waitForExistence(timeout:10));capture(app,"M3-V14-week-L")
    }
    func testRamadanNightAndReturnRoutes() throws {
        continueAfterFailure=false
        let app=launch("today","2024-03-11T15:00:00+03:00");XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-ramadan").firstMatch.waitForExistence(timeout:10));capture(app,"M3-V14-ramadan-L");app.terminate()
        let night=launch("today","2026-10-15T22:00:00+03:00","dark")
        XCTAssertTrue(night.staticTexts["diary-day-title"].label.contains("١٥ أكتوبر ٢٠٢٦"))
        XCTAssertTrue(night.staticTexts["diary-day-secondary-date"].label.contains("ليلة ٥ جمادى الأولى ١٤٤٨"), night.staticTexts["diary-day-secondary-date"].label)
        capture(night,"M3-V14-dark-L");night.terminate()
        let back=launch("return","2026-10-15T15:00:00+03:00");XCTAssertTrue(back.buttons["diary-return-days"].waitForExistence(timeout:10));capture(back,"M3-V14-return-L");back.buttons["diary-return-days"].tap();XCTAssertTrue(back.buttons["diary-month-10"].waitForExistence(timeout:10))
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
