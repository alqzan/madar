import XCTest
@MainActor final class QuranIndexUITests:XCTestCase {
    func testAllFiveUnitsAndVerifiedBoundaryOpenMushaf() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 {if app.buttons["quran-tool-index"].isHittable {break};app.swipeUp()};app.buttons["quran-tool-index"].tap()
        XCTAssertTrue(app.buttons["quran-index-unit-surah"].waitForExistence(timeout:10));capture(app,"M2-V15-index-L")
        for unit in ["ayah","juz","hizb","page"] {app.buttons["quran-index-unit-"+unit].tap();XCTAssertTrue(app.buttons["quran-index-item-1"].waitForExistence(timeout:10))}
        capture(app,"M2-V15-pages-L");app.buttons["quran-index-item-1"].tap();XCTAssertTrue(app.buttons["افتح في المصحف"].waitForExistence(timeout:5));app.buttons["افتح في المصحف"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["quran-mushaf-page"].waitForExistence(timeout:15))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
