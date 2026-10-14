import XCTest

@MainActor final class QuranReviewUITests: XCTestCase {
    func testCoveredReviewRevealFlagResumeGradeAndPartialExitAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["quran-begin"].tap()
        let advance = app.buttons["quran-session-advance"]
        XCTAssertTrue(advance.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(advance.label, "كشفت التالية")
        let closeFrame = app.buttons["quran-session-close"].frame
        XCTAssertGreaterThanOrEqual(closeFrame.minX, app.frame.minX, "Close button: \(closeFrame), window: \(app.frame)")
        XCTAssertLessThanOrEqual(closeFrame.maxX, app.frame.maxX, "Close button: \(closeFrame), window: \(app.frame)")
        attach(app, "M2-V03-review-L")
        app.buttons["quran-session-full-page"].tap()
        XCTAssertTrue(app.buttons["quran-session-show-tools"].waitForExistence(timeout: 5))
        XCTAssertFalse(advance.exists)
        attach(app, "M2-V03-full-page-L")
        app.buttons["quran-session-show-tools"].tap()
        XCTAssertTrue(advance.waitForExistence(timeout: 5))
        let flag = app.buttons["quran-session-hint"]
        XCTAssertEqual(flag.label, "تعثّرت"); flag.tap()
        advance.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-resume"].waitForExistence(timeout: 20)); app.buttons["quran-resume"].tap()
        XCTAssertTrue(advance.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["quran-session-stage"].label.contains("كشفت ١"))
        attach(app, "M2-V03-revealed-L")
        for _ in 0..<40 {
            if advance.label == "قيّم هذا الوجه" { break }
            advance.tap()
            XCTAssertTrue(advance.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(advance.label, "قيّم هذا الوجه"); advance.tap()
        let grade = app.buttons["quran-coach-grade-needs"]
        XCTAssertTrue(grade.waitForExistence(timeout: 10)); grade.tap()
        attach(app, "M2-V03-grade-L")
        XCTAssertEqual(advance.label, "تابع")
        advance.tap()
        let nextPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "كشفت التالية"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPage], timeout: 12), .completed)
        app.buttons["quran-session-close"].tap()
        XCTAssertTrue(app.buttons["quran-session-save-partial"].waitForExistence(timeout: 5))
        app.buttons["quran-session-save-partial"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quran-resume"].exists)
        app.terminate()
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testQuietFullPageInDarkAtDefaultSize() {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "dark", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20)); app.buttons["quran-begin"].tap()
        XCTAssertTrue(app.buttons["quran-session-full-page"].waitForExistence(timeout: 15)); app.buttons["quran-session-full-page"].tap()
        XCTAssertTrue(app.buttons["quran-session-show-tools"].waitForExistence(timeout: 5))
        attach(app, "M2-V03-full-page-dark-L")
        app.terminate()
    }
}
