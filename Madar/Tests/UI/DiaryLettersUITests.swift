import XCTest
@MainActor final class DiaryLettersUITests:XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDiaryArchiveRetriesAfterItsFirstReadFails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "letters", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_DIARY_HUB_READ_FAILURE_ONCE": "1"]
        app.launch()
        let days = app.buttons["diary-days"]
        XCTAssertTrue(days.waitForExistence(timeout: 25), app.debugDescription); days.tap()
        let error = app.staticTexts["diary-hub-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(error.label, "تعذّر فتح سجل اليوميات.")
        shot(app, "AU-74-hub-read-error-L")
        app.buttons["diary-hub-retry"].tap()
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "AU-74-hub-retried-L")
    }
    func testDayPageKeepsItsContentAndRetriesWhenLetterReadFails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "letters", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_DIARY_DAY_READ_FAILURE_ONCE": "letters"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25), app.debugDescription); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["diary-day-line"].waitForExistence(timeout: 10), app.debugDescription)
        let error = app.staticTexts["diary-day-read-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["diary-day-read-retry"].tap()
        XCTAssertTrue(app.buttons["diary-letter-waiting"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5), app.debugDescription)
    }
    // N04: a due letter waits on today's page and opens once; a sealed one shows only as a blurred line;
    // the mailbox lives in «أيامك». (Projects were removed from the app on 11 Nov 2026; their UI tests went with them.)
    func testLettersAndMailbox() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"letters","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"];app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.buttons["diary-letter-waiting"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-sealed-letter-line").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","لا تُقرأ قبل وقتها")).firstMatch.exists)
        capture(app,"F01-today-letters-L")
        app.buttons["diary-letter-waiting"].tap();XCTAssertTrue(app.buttons["diary-letter-open"].waitForExistence(timeout:10));capture(app,"F01-letter-sealed-L")
        app.buttons["diary-letter-open"].tap();let text=app.staticTexts["diary-letter-text"];XCTAssertTrue(text.waitForExistence(timeout:10))
        XCTAssertTrue(text.label.hasPrefix("أرجو أن تكون"));capture(app,"F01-letter-open-L")
        app.buttons["diary-letter-done"].tap()
        XCTAssertTrue(app.buttons["diary-letter-waiting"].waitForNonExistence(timeout:10))
        app.buttons.matching(identifier:"أيامك").firstMatch.tap();XCTAssertTrue(app.buttons["diary-hub-letters"].waitForExistence(timeout:10));app.buttons["diary-hub-letters"].tap()
        XCTAssertTrue(app.buttons["diary-letter-opened"].waitForExistence(timeout:10));XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-letter-sealed").firstMatch.exists)
        capture(app,"F01-mailbox-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
