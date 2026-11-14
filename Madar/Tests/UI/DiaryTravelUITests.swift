import XCTest
@MainActor final class DiaryTravelUITests:XCTestCase {
    // M3-V15 · notes-app/21: a shared trip from yesterday shows the air-mail day two, stamp, route and «اكتب من إسطنبول».
    func testTravelTodayPageAndStamps() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"travel","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-09-30T16:40:00+03:00"];app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        let title=app.staticTexts["diary-travel-title"];XCTAssertTrue(title.waitForExistence(timeout:10));XCTAssertEqual(title.label,"اليوم الثاني")
        XCTAssertTrue(app.staticTexts["diary-travel-distance"].label.contains("كم عن الرياض"))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-travel-stamp").firstMatch.exists)
        XCTAssertTrue(app.textFields["diary-inline-field"].exists || app.buttons["diary-day-write"].exists)
        capture(app,"M3-V15-travel-L")
        app.buttons["diary-stamps-open"].tap();XCTAssertTrue(app.buttons["diary-stamps-done"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-passport-stamp").firstMatch.exists);capture(app,"M3-V15-stamps-L")
        app.buttons["diary-stamps-done"].tap();app.buttons["diary-day-write"].tap();XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout:10))
    }
    func testTripDayLineUsesItsSavedLocalClock() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "travelClock",
                                "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-03-20T00:30:00Z"]
        app.launch()
        let today = app.buttons["diary-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 25)); today.tap()
        let localTime = app.staticTexts["diary-day-line-time"]
        XCTAssertTrue(localTime.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(localTime.label, "١٢:٣٠ ص", "London's midnight entry must not fall back to Riyadh time")
        capture(app, "M3-V15-trip-clock-L")
    }
    // §7.3 «تقويم السفر · الإطار البريدي» and the return moment: the Cairo trip (10–14 September) is framed, and its return day folds into an envelope.
    func testTravelCalendarFramesAndReturnEnvelope() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"travel","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-09-30T16:40:00+03:00"];app.launch()
        let days=app.buttons.matching(identifier:"diary-days").firstMatch;XCTAssertTrue(days.waitForExistence(timeout:25));days.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-calendar-travel-legend").firstMatch.waitForExistence(timeout:10));capture(app,"M3-V15-year-travel-L")
        app.buttons["diary-calendar-scale"].tap()
        let travelled=app.buttons["diary-calendar-day-2026-09-12"];XCTAssertTrue(travelled.waitForExistence(timeout:10));XCTAssertTrue(travelled.label.hasSuffix("يوم سفر"))
        let back=app.buttons["diary-calendar-day-2026-09-15"];XCTAssertFalse(back.label.hasSuffix("يوم سفر"))
        capture(app,"M3-V15-month-travel-L")
        back.tap()
        let envelope=app.buttons["diary-travel-return"];XCTAssertTrue(envelope.waitForExistence(timeout:10))
        XCTAssertTrue(envelope.label.contains("عدت من القاهرة"),envelope.label);XCTAssertTrue(envelope.label.contains("٥ أيام"),envelope.label)
        capture(app,"M3-V15-return-envelope-L")
        envelope.tap();XCTAssertTrue(app.buttons["diary-stamps-done"].waitForExistence(timeout:10))
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
