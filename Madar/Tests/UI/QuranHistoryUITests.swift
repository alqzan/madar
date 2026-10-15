import XCTest
@MainActor final class QuranHistoryUITests: XCTestCase {
    func testEditGradeDeleteAndUndoKeepSession() throws {
        continueAfterFailure = false
        let app=XCUIApplication(); app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch(); XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<4 { if app.buttons["quran-week-open"].isHittable { break };app.swipeUp() }
        app.buttons["quran-week-open"].tap();app.buttons["quran-log-sessions"].tap()
        XCTAssertTrue(app.staticTexts["quran-history-coverage"].waitForExistence(timeout:10))
        app.buttons["quran-history-filter-hifz"].tap()
        let row=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","quran-history-record-")).firstMatch
        let id=row.identifier;row.tap();capture(app,"M2-V11-history-L")
        app.buttons["quran-history-grade-needs"].tap()
        XCTAssertTrue(app.staticTexts["quran-history-warning"].waitForExistence(timeout:5));capture(app,"M2-V11-grade-L")
        app.buttons["quran-history-delete"].tap();app.alerts.buttons["احذف"].tap()
        XCTAssertTrue(app.buttons[id].waitForNonExistence(timeout:8))
        app.otherElements["quran-history-undo"].buttons["undo-button"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout:8));capture(app,"M2-V11-restored-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
}
