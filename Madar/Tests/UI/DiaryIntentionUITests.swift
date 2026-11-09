import XCTest
@MainActor final class DiaryIntentionUITests:XCTestCase {
    func testMorningIntentionEveningExplicitResultAndUndo() throws {
        continueAfterFailure=false
        let app=XCUIApplication();let store=UUID().uuidString
        app.launchEnvironment=["MADAR_UI_STORE_ID":store,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.scrollViews["diary-audio-transcript-text"].waitForExistence(timeout:10));app.buttons["diary-audio-transcript-open"].tap()
        XCTAssertTrue(app.textViews["diary-audio-transcript-edit"].waitForExistence(timeout:5));app.buttons["diary-audio-transcript-cancel"].tap();app.buttons["diary-niyya-open"].tap()
        let text=app.textFields["diary-niyya-text"];XCTAssertTrue(text.waitForExistence(timeout:10));capture(app,"OWNER-notes-intention-inline-L");text.tap();text.typeText("أُنهي ما بدأت");app.buttons["diary-niyya-save"].tap()
        XCTAssertTrue(app.buttons["diary-niyya-undo"].waitForExistence(timeout:10));app.buttons["diary-niyya-close-inline"].tap();XCTAssertTrue(app.staticTexts["أسألك عنها بعد العشاء"].waitForExistence(timeout:10));capture(app,"M3-V13-morning-L")
        let back=app.navigationBars.buttons.firstMatch;XCTAssertTrue(back.waitForExistence(timeout:5));back.tap();XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout:10),"Popping the day must reveal the same diary home without a covering page")
        app.terminate();app.launchEnvironment["MADAR_UI_NOW"]="2026-10-15T22:00:00+03:00";app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["diary-day-arc"].waitForExistence(timeout:10))
        let partial=app.buttons["diary-niyya-inline-partial"];XCTAssertTrue(partial.waitForExistence(timeout:10));capture(app,"M3-V13-evening-L");XCTAssertFalse(partial.isSelected)
        partial.tap();XCTAssertTrue(app.buttons["diary-niyya-inline-partial"].waitForExistence(timeout:5));let selected=NSPredicate(format:"isSelected == true");expectation(for:selected,evaluatedWith:app.buttons["diary-niyya-inline-partial"]);waitForExpectations(timeout:10);capture(app,"M3-V13-outcome-L")
        let undo=app.buttons["diary-day-niyya-undo"];XCTAssertTrue(undo.waitForExistence(timeout:10));undo.tap()
        expectation(for:NSPredicate(format:"isSelected == false"),evaluatedWith:app.buttons["diary-niyya-inline-partial"]);waitForExpectations(timeout:10)
    }
    func testSentenceBecomesIntentionFromItsContextMenu() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        let line=app.staticTexts["صورة احتفظت بها اليوم."];XCTAssertTrue(line.waitForExistence(timeout:10));line.press(forDuration:1.2)
        let convert=app.buttons["اجعلها نيّة اليوم"];XCTAssertTrue(convert.waitForExistence(timeout:5));convert.tap()
        XCTAssertTrue(app.buttons["diary-day-niyya-undo"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["diary-niyya-open"].label.contains("صورة احتفظت بها اليوم"));capture(app,"M3-V13-sentence-L")
    }
    func testWeeklyThenMonthlyReviewStayOnDiaryHome() throws {
        continueAfterFailure=false
        let app=XCUIApplication(),store=UUID().uuidString
        app.launchEnvironment=["MADAR_UI_STORE_ID":store,"MADAR_UI_DIARY_FIXTURE":"intentionReview","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch()
        let weekly=app.textFields["diary-intention-review-text"]
        XCTAssertTrue(weekly.waitForExistence(timeout:25));XCTAssertTrue(app.staticTexts["مضى أسبوع على نيّتك"].exists)
        capture(app,"OWNER-notes-week-review-L");weekly.tap();weekly.typeText("بدأت بالمشي بعد المغرب.");app.buttons["diary-intention-review-save"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:weekly);waitForExpectations(timeout:10)
        app.terminate();app.launchEnvironment["MADAR_UI_NOW"]="2026-11-14T07:00:00+03:00";app.launch()
        let monthly=app.textFields["diary-intention-review-text"]
        XCTAssertTrue(monthly.waitForExistence(timeout:25));XCTAssertTrue(app.staticTexts["مضى شهر على نيّتك"].exists)
        monthly.tap();monthly.typeText("أصبحت أخرج أربعة أيام في الأسبوع.");app.buttons["diary-intention-review-save"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:monthly);waitForExpectations(timeout:10)
    }
    func testUnsavedIntentionIsKeptWhenCloseIsCancelled() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap();app.buttons["diary-niyya-open"].tap()
        let text=app.textFields["diary-niyya-text"];XCTAssertTrue(text.waitForExistence(timeout:10));text.tap();text.typeText("أتمّ ما بدأت به")
        app.buttons["diary-niyya-close-inline"].tap();let keep=app.buttons.matching(identifier:"diary-niyya-continue").firstMatch;XCTAssertTrue(keep.waitForExistence(timeout:5));capture(app,"AU-95-diary-intention-discard-confirm-L");keep.tap()
        XCTAssertEqual(text.value as? String,"أتمّ ما بدأت به");app.buttons["diary-niyya-save"].tap();XCTAssertTrue(app.buttons["diary-niyya-undo"].waitForExistence(timeout:10))
    }
    private func capture(_ app:XCUIApplication,_ name:String){
        let image=app.screenshot(),attachment=XCTAttachment(screenshot:image);attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        if let dir=ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? image.pngRepresentation.write(to:URL(fileURLWithPath:dir).appendingPathComponent(name+".png")) }
    }
}
