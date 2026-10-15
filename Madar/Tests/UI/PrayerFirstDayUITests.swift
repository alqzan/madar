import XCTest

@MainActor final class PrayerFirstDayUITests: XCTestCase {
    func testUnrecordedTodayAndActualPastGapUseDistinctCopy() throws {
        continueAfterFailure = false
        for past in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": past ? "light" : "dark", "MADAR_UI_NOW": "2026-10-15T22:00:00+03:00"]
            if past { app.launchEnvironment["MADAR_UI_TRACKING_START"] = "2026-10-01" }
            app.launch()
            if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
            let start = app.buttons["first-run-continue"]
            if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
            app.tabBars.buttons["الصلاة"].tap()
            let summary = app.staticTexts["prayer-today-summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.contains("لم تُسجَّل"), summary.label)
            XCTAssertFalse(summary.label.contains("بقيت"), summary.label)
            let old = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "من فترة سابقة")).firstMatch
            XCTAssertEqual(old.exists, past, app.debugDescription)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = past ? "UX-08-real-history-L" : "UX-08-first-night-L"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
}
