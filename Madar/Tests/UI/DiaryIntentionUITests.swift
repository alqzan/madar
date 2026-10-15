import XCTest
@MainActor final class DiaryIntentionUITests:XCTestCase {
    func testMorningIntentionEveningExplicitResultAndUndo() throws {
        continueAfterFailure=false
        let app=XCUIApplication();let store=UUID().uuidString
        app.launchEnvironment=["MADAR_UI_STORE_ID":store,"MADAR_UI_DIARY_FIXTURE":"empty","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap();app.buttons["diary-niyya-open"].tap()
        let text=app.textFields["diary-niyya-text"];XCTAssertTrue(text.waitForExistence(timeout:10));text.tap();text.typeText("أُنهي ما بدأت");app.buttons["diary-niyya-save"].tap()
        XCTAssertTrue(app.buttons["diary-niyya-undo"].waitForExistence(timeout:10));app.buttons["diary-niyya-close"].tap();capture(app,"M3-V13-morning-L")
        app.terminate();app.launchEnvironment["MADAR_UI_NOW"]="2026-10-15T22:00:00+03:00";app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.buttons["diary-niyya-evening"].waitForExistence(timeout:10));capture(app,"M3-V13-evening-L");app.buttons["diary-niyya-evening"].tap()
        let partial=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'diary-niyya-result-partial-'")).firstMatch;XCTAssertTrue(partial.waitForExistence(timeout:10));XCTAssertFalse(partial.isSelected);partial.tap();XCTAssertTrue(partial.isSelected);capture(app,"M3-V13-outcome-L")
        let undo=app.buttons["diary-niyya-undo"];for _ in 0..<4 where !undo.isHittable{app.swipeUp()};undo.tap();XCTAssertFalse(partial.isSelected)
    }
    func testSentenceBecomesIntentionFromItsContextMenu() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T07:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        let line=app.staticTexts["صورة احتفظت بها اليوم."];XCTAssertTrue(line.waitForExistence(timeout:10));line.press(forDuration:1.2)
        let convert=app.buttons["اجعلها نيّة اليوم"];XCTAssertTrue(convert.waitForExistence(timeout:5));convert.tap()
        XCTAssertTrue(app.buttons["diary-day-niyya-undo"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["diary-niyya-open"].label.contains("صورة احتفظت بها اليوم"));capture(app,"M3-V13-sentence-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
