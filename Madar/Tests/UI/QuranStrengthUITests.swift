import XCTest
@MainActor final class QuranStrengthUITests:XCTestCase {
    func testStrengthRaiseRecoveryAndDetails() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 {if app.buttons["quran-tool-strength"].isHittable {break};app.swipeUp()};app.buttons["quran-tool-strength"].tap()
        XCTAssertTrue(app.staticTexts["quran-strength-mean"].waitForExistence(timeout:10));capture(app,"M2-V16-strength-L")
        for _ in 0..<3 {if app.buttons["quran-strength-raise"].isHittable {break};app.swipeUp()};app.buttons["quran-strength-raise"].tap()
        XCTAssertTrue(app.staticTexts["quran-strength-raised"].waitForExistence(timeout:8));capture(app,"M2-V16-raised-L")
        for _ in 0..<4 {if app.buttons["quran-strength-recovery"].isHittable {break};app.swipeDown()};app.buttons["quran-strength-recovery"].tap()
        XCTAssertTrue(app.buttons["quran-recovery-days-7"].waitForExistence(timeout:5));capture(app,"M2-V16-recovery-L");app.buttons["quran-recovery-days-7"].tap();app.buttons["quran-recovery-create"].tap()
        XCTAssertTrue(app.buttons["quran-strength-recovery"].waitForExistence(timeout:8));app.buttons["quran-strength-recovery"].tap();XCTAssertTrue(app.buttons["quran-recovery-cancel"].waitForExistence(timeout:5));app.buttons["quran-recovery-cancel"].tap()
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
