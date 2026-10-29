import XCTest
@MainActor final class DiaryLettersUITests:XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWelcomeRetriesAfterItsFirstReadFails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "welcome", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_DIARY_WELCOME_READ_FAILURE_ONCE": "1"]
        app.launch()
        let retry = app.buttons["diary-welcome-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12), app.debugDescription)
        let error = app.staticTexts["diary-welcome-error"]
        XCTAssertEqual(error.label, "تعذّر فتح صفحة اليوميات. أعد المحاولة.")
        shot(app, "AU-70-welcome-read-error-L")
        retry.tap()
        XCTAssertTrue(app.buttons["diary-welcome-next"].waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "AU-70-welcome-retried-L")
    }
    func testSwipeCannotDiscardAnUnsavedProjectDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "letters", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        XCTAssertTrue(app.buttons["diary-hub-projects"].waitForExistence(timeout: 10)); app.buttons["diary-hub-projects"].tap()
        app.buttons["diary-project-new"].tap()
        let name = app.textFields["diary-project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("مسودة محفوظة من السحب")
        shot(app, "AU-70-project-draft-before-L")
        app.swipeDown()
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "مسودة محفوظة من السحب")
        app.buttons["إلغاء"].tap()
        let discard = app.buttons["diary-project-discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "AU-70-project-discard-confirm-L")
        app.buttons["أكمل الكتابة"].tap()
        XCTAssertTrue(name.exists, app.debugDescription)
        XCTAssertEqual(name.value as? String, "مسودة محفوظة من السحب")
        shot(app, "AU-70-project-draft-kept-L")
        app.buttons["إلغاء"].tap()
        XCTAssertTrue(discard.firstMatch.waitForExistence(timeout: 5)); discard.firstMatch.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 8))
    }
    func testProjectRapidSaveCreatesOneRowAndHijriComposerKeepsBothDates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "letters", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        XCTAssertTrue(app.buttons["diary-hub-projects"].waitForExistence(timeout: 10)); app.buttons["diary-hub-projects"].tap()
        app.buttons["diary-project-new"].tap()
        let name = app.textFields["diary-project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("مشروع بلا تكرار")
        capture(app, "Final-project-before-save-L")
        app.buttons["diary-project-save"].doubleTap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10))
        let rows = app.buttons.matching(identifier: "diary-project-row").matching(NSPredicate(format: "label CONTAINS %@", "مشروع بلا تكرار"))
        XCTAssertEqual(rows.count, 1)
        capture(app, "Final-project-single-L")
        app.buttons["diary-hub-letters"].tap(); app.buttons["diary-letter-compose"].tap()
        XCTAssertTrue(app.buttons["diary-letter-trigger-hijri"].waitForExistence(timeout: 5))
        app.buttons["diary-letter-trigger-hijri"].tap()
        XCTAssertTrue(app.datePickers["diary-letter-date"].waitForExistence(timeout: 5))
        capture(app, "Final-letter-hijri-L")
    }
    // N04: a due letter waits on today's page and opens once; a sealed one shows only as a blurred line;
    // a project keyword is a suggestion that links by one tap; the mailbox and projects live in «أيامك».
    func testLettersProjectsAndMailbox() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"letters","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"];app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.buttons["diary-letter-waiting"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-sealed-letter-line").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","لا تُقرأ قبل وقتها")).firstMatch.exists)
        capture(app,"F01-today-letters-L")
        app.buttons["diary-line-project-suggest"].tap();XCTAssertTrue(app.staticTexts["diary-line-project"].waitForExistence(timeout:10))
        app.buttons["diary-letter-waiting"].tap();XCTAssertTrue(app.buttons["diary-letter-open"].waitForExistence(timeout:10));capture(app,"F01-letter-sealed-L")
        app.buttons["diary-letter-open"].tap();let text=app.staticTexts["diary-letter-text"];XCTAssertTrue(text.waitForExistence(timeout:10))
        XCTAssertTrue(text.label.hasPrefix("أرجو أن تكون"));capture(app,"F01-letter-open-L")
        app.buttons["diary-letter-done"].tap()
        XCTAssertTrue(app.buttons["diary-letter-waiting"].waitForNonExistence(timeout:10))
        app.buttons.matching(identifier:"أيامك").firstMatch.tap();XCTAssertTrue(app.buttons["diary-hub-letters"].waitForExistence(timeout:10));app.buttons["diary-hub-letters"].tap()
        XCTAssertTrue(app.buttons["diary-letter-opened"].waitForExistence(timeout:10));XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-letter-sealed").firstMatch.exists)
        capture(app,"F01-mailbox-L")
        app.buttons["diary-hub-projects"].tap();XCTAssertTrue(app.buttons["diary-project-row"].waitForExistence(timeout:10));capture(app,"F01-projects-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
