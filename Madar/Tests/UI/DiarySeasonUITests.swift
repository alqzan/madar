import XCTest
@MainActor final class DiarySeasonUITests:XCTestCase {
    private func launch(_ variant:String,_ now:String,_ theme:String="light",styles:String?=nil)->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":variant,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":theme,"MADAR_UI_NOW":now];if let styles{app.launchEnvironment["MADAR_UI_STYLE_SETTINGS"]=styles};app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap();XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout:10));return app
    }
    func testFridayFrameAndActualWeekRoute() throws {
        continueAfterFailure=false
        let app=launch("today","2026-10-16T16:00:00+03:00");XCTAssertEqual(app.staticTexts["diary-day-title"].label,"جمعة مباركة");capture(app,"M3-V14-friday-L");app.buttons["diary-week-open"].tap();XCTAssertTrue(app.buttons["diary-week-write"].waitForExistence(timeout:10));capture(app,"M3-V14-week-L")
    }
    /// OR-16: the three Friday and three Ramadan looks chosen from the diary settings.
    func testFridayAndRamadanLooksFromSettings() throws {
        continueAfterFailure=false
        for (friday,ramadan) in [("mihrab","night"),("ribbon","lantern"),("medallion","paper")] {
            let f=launch("today","2026-10-16T16:00:00+03:00",styles:"notes.fridayStyle="+friday);XCTAssertEqual(f.staticTexts["diary-day-title"].label,"جمعة مباركة")
            if friday != "ribbon" {XCTAssertTrue(f.descendants(matching:.any)["diary-friday-"+friday].exists,friday)}
            XCTAssertTrue(f.buttons["diary-week-open"].exists);capture(f,"M3-V14-friday-"+friday+"-L");f.terminate()
            let r=launch("today","2024-03-11T15:00:00+03:00",styles:"notes.ramadanStyle="+ramadan);let banner=r.descendants(matching:.any).matching(identifier:"diary-ramadan").firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout:10));XCTAssertTrue(banner.label.contains("من رمضان"),banner.label);capture(r,"M3-V14-ramadan-"+ramadan+"-L");r.terminate()
        }
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
