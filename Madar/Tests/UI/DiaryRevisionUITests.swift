import XCTest
@MainActor final class DiaryRevisionUITests:XCTestCase {
    // RD1 [DEFAULT]: a line from a closed day a year ago is edited; the page marks it «عُدّل» and the original is readable.
    func testEditFrozenLineKeepsTheOriginal() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"today","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"];app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout:25));app.buttons["diary-today"].tap()
        XCTAssertTrue(app.buttons["diary-day-year"].waitForExistence(timeout:10));app.buttons["diary-day-year"].tap()
        let line=app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH %@","عشاء عند أهلي")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout:10));line.press(forDuration:1.0)
        XCTAssertTrue(app.buttons["عدّل السطر"].waitForExistence(timeout:5));app.buttons["عدّل السطر"].tap()
        let field=app.textViews["diary-line-edit-text"];XCTAssertTrue(field.waitForExistence(timeout:10))
        field.typeText(" وبقينا حتى العشاء.")
        app.buttons["diary-line-edit-save"].tap()
        let mark=app.buttons["diary-line-edited"];XCTAssertTrue(mark.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","وبقينا حتى العشاء")).firstMatch.exists)
        capture(app,"F01-edited-L")
        mark.tap();let original=app.staticTexts["diary-line-original"];XCTAssertTrue(original.waitForExistence(timeout:10))
        XCTAssertFalse(original.label.contains("وبقينا"));capture(app,"F01-original-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
