import XCTest
@MainActor final class QuranJourneyUITests: XCTestCase {
    func testJourneyTotalsForecastAndPageHistory() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        for _ in 0..<4 { if app.buttons["quran-week-open"].isHittable { break }; app.swipeUp() }
        app.buttons["quran-week-open"].tap(); app.buttons["quran-log-all"].tap()
        XCTAssertTrue(app.staticTexts["quran-journey-forecast"].waitForExistence(timeout: 15)); capture(app,"M2-V10-journey-L")
        XCTAssertTrue(app.staticTexts["quran-journey-hifz"].label.contains("٢٨٤"))
        for id in ["work", "recited", "streak", "pace"] {
            let stat = app.staticTexts["quran-journey-" + id]
            var found = stat.waitForExistence(timeout: 2)
            for _ in 0..<4 where !found {
                app.swipeUp()
                found = stat.waitForExistence(timeout: 2)
            }
            XCTAssertTrue(found, "Missing journey statistic: \(id)")
        }
        let map = app.descendants(matching: .any)["quran-journey-map"]
        for _ in 0..<5 { if map.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(map.isHittable)
        capture(app,"M2-V10-map-L"); map.tap()
        XCTAssertTrue(app.buttons["افتح في المصحف"].waitForExistence(timeout: 5)); capture(app,"M2-V10-page-L")
        app.buttons["تمّ"].tap()
    }
    private func capture(_ app: XCUIApplication,_ name: String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
}
