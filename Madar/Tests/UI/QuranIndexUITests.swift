import XCTest
@MainActor final class QuranIndexUITests:XCTestCase {
    func testAllFiveUnitsAndVerifiedBoundaryOpenMushaf() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 {if app.buttons["quran-tool-index"].isHittable {break};app.swipeUp()};app.buttons["quran-tool-index"].tap()
        XCTAssertTrue(app.buttons["quran-index-unit-surah"].waitForExistence(timeout:10));capture(app,"M2-V15-index-L")
        app.buttons["quran-index-unit-ayah"].tap()
        let search=app.textFields["quran-index-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("الحمد")
        XCTAssertTrue(app.buttons["quran-index-item-2"].waitForExistence(timeout:5));app.buttons["quran-index-unit-juz"].tap()
        for unit in ["juz","hizb","page"] {app.buttons["quran-index-unit-"+unit].tap();XCTAssertTrue(app.buttons["quran-index-item-1"].waitForExistence(timeout:10))}
        capture(app,"M2-V15-pages-L");app.buttons["quran-index-item-1"].tap();XCTAssertTrue(app.buttons["افتح في المصحف"].waitForExistence(timeout:5));app.buttons["افتح في المصحف"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["quran-mushaf-page"].waitForExistence(timeout:15))
    }
    func testFailedUnitChangeRemovesOldRowsAndRetryLoadsAyahs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_INDEX_FAIL_UNIT_ONCE": "ayah"]
        app.launch()
        let index = app.buttons["quran-tool-index"]
        XCTAssertTrue(index.waitForExistence(timeout: 25))
        for _ in 0..<7 where !index.isHittable { app.swipeUp() }
        index.tap()
        app.buttons["quran-index-unit-juz"].tap()
        XCTAssertTrue(app.buttons["quran-index-item-1"].waitForExistence(timeout: 10))
        app.buttons["quran-index-unit-ayah"].tap()
        XCTAssertTrue(app.staticTexts["quran-index-read-error"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-index-item-1"].exists, "An ayah failure cannot leave old juz rows selectable.")
        capture(app, "OWNER-quran-index-unit-failure-L")
        app.buttons["quran-index-retry"].tap()
        let search = app.textFields["quran-index-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("الحمد")
        XCTAssertTrue(app.buttons["quran-index-item-2"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "OWNER-quran-index-unit-recovered-L")
        app.terminate()
    }

    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
