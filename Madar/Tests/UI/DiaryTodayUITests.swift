import XCTest

@MainActor final class DiaryTodayUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]; app.launch(); return app
    }
    func testFirstOpenShowsTodayDirectlyAndKeyboardOpensWithoutWelcome() throws {
        continueAfterFailure = false
        let app = launch("welcome")
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-welcome-next"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); XCTAssertFalse(app.buttons["diary-welcome-next"].exists)
        app.buttons["diary-write"].tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
    }
    func testRestoredDiaryOpensWithoutWelcomeAndNamesItsMissingPhoto() throws {
        continueAfterFailure = false
        let app = launch("restored")
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["diary-welcome-next"].exists)
        let excerpt = app.staticTexts.matching(NSPredicate(format: "label == %@", "ذكرى مستوردة بقيت بتاريخها")).firstMatch
        XCTAssertTrue(excerpt.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "صورة هذا اليوم لم تُنقل")).firstMatch.exists)
        let write = app.buttons["diary-write"]
        let accessory = app.otherElements["fixed-tab-bar"]   // FB-31: the glass tab bar replaced the prayer accessory
        XCTAssertLessThanOrEqual(write.frame.maxY, accessory.frame.minY, "Writing stays above the native accessory")
        XCTAssertLessThanOrEqual(accessory.frame.minY - write.frame.maxY, 24, "No duplicate bottom spacer")
        capture(app, "M3-restored-diary-L")
        app.swipeUp(velocity: .slow)
        XCTAssertLessThanOrEqual(excerpt.frame.maxY, write.frame.minY, "The complete memory excerpt can scroll clear of the writing bar")
        capture(app, "M3-restored-diary-s1-L")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["diary-welcome-next"].exists)
        app.buttons["diary-days"].tap()
        let month = app.buttons["diary-month-10"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        XCTAssertTrue(month.label.contains("أكتوبر"))
        XCTAssertTrue(month.label.contains("ربيع"), "Month accessibility includes the other calendar")
        capture(app, "M3-restored-hub-L")
    }
    func testTodayPaperSourcesYesterdayYearAndLateWriting() throws {
        continueAfterFailure = false
        let app = launch("today")
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "صلّيت الفجر جماعة")).firstMatch.waitForExistence(timeout: 10)); capture(app, "M3-V05-today-L")
        app.swipeUp(); capture(app, "M3-V05-today-scrolled-L")
        app.buttons["diary-day-year"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "عشاء عند أهلي")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["diary-day-yesterday"].tap()
        XCTAssertTrue(app.staticTexts["دوام طويل. وصلت البيت قبل العشاء بدقائق."].waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap(); app.buttons["diary-write"].tap()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["diary-editor-yesterday"].tap(); editor.tap(); editor.typeText("سطر متأخر محفوظ في أمس"); app.buttons["diary-editor-save"].tap()
        app.buttons["diary-today"].tap(); app.buttons["diary-day-yesterday"].tap()
        let late = app.staticTexts["سطر متأخر محفوظ في أمس"]; for _ in 0..<4 where !late.isHittable { app.swipeUp() }
        XCTAssertTrue(late.exists); XCTAssertTrue(app.staticTexts["كُتبت لاحقًا"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
