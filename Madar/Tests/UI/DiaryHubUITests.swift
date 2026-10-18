import XCTest
@MainActor final class DiaryHubUITests: XCTestCase {
    func testYearMonthDayTimelinePhotosAndCalendarPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        let yearScale = app.buttons["diary-calendar-scale-year"]
        let monthScale = app.buttons["diary-calendar-scale"]
        XCTAssertTrue(yearScale.waitForExistence(timeout: 10)); XCTAssertTrue(yearScale.isSelected); XCTAssertFalse(monthScale.isSelected)
        XCTAssertTrue(app.buttons["diary-month-10"].waitForExistence(timeout: 10)); capture(app,"M3-V07-hub-L")
        monthScale.tap(); XCTAssertTrue(monthScale.isSelected); XCTAssertFalse(yearScale.isSelected)
        yearScale.tap(); XCTAssertTrue(yearScale.isSelected); XCTAssertFalse(monthScale.isSelected)
        app.buttons["diary-month-10"].tap(); let day = app.buttons["diary-calendar-day-2026-10-15"]; XCTAssertTrue(day.waitForExistence(timeout: 5)); capture(app,"M3-V07-month-L"); day.tap()
        XCTAssertTrue(app.buttons["diary-day-write"].waitForExistence(timeout: 10)); app.buttons["diary-day-close"].tap()
        app.buttons["diary-hub-timeline"].tap(); XCTAssertTrue(app.buttons["diary-hub-day-2026-10-15"].waitForExistence(timeout: 10)); capture(app,"M3-V07-timeline-L")
        app.buttons["diary-hub-photos"].tap(); XCTAssertTrue(app.images.count > 0); capture(app,"M3-V07-photos-L")
        app.buttons["diary-hub-calendar"].tap(); yearScale.tap()
        let hijri = app.buttons["diary-calendar-hijri"]; for _ in 0..<4 where !hijri.isHittable { app.swipeUp() }; hijri.tap()
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["diary-hub-year"].label,"١٤٤٨")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["diary-hub-year"].label,"١٤٤٨")
    }
    private func capture(_ app: XCUIApplication,_ name:String) { let shot = XCTAttachment(screenshot:app.screenshot()); shot.name=name; shot.lifetime = .keepAlways; add(shot) }
}
