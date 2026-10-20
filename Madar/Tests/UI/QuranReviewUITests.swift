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
        // The fixture's pages are mastered and recent, so each starts with one whole-page check.
        XCTAssertEqual(advance.label, "سمّعته كاملًا")
        XCTAssertTrue(app.staticTexts["quran-session-stage"].label.contains("وجه متقن"), app.staticTexts["quran-session-stage"].label)
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
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, advance.debugDescription)
        // Uncovering one ayah by hand keeps this page ayah by ayah.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "اكشف ")).firstMatch.tap()
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "كشفت ١"), object: app.staticTexts["quran-session-stage"])
        XCTAssertEqual(XCTWaiter.wait(for: [one], timeout: 8), .completed, app.staticTexts["quran-session-stage"].label)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-resume"].waitForExistence(timeout: 20)); app.buttons["quran-resume"].tap()
        XCTAssertTrue(advance.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["quran-session-stage"].label.contains("كشفت ١"), app.staticTexts["quran-session-stage"].label)
        attach(app, "M2-V03-revealed-L")
        // Revealing the last ayah opens grading by itself (owner 20 Oct: fewer taps per page).
        let grade = app.buttons["quran-coach-grade-needs"]
        for _ in 0..<40 {
            if grade.exists { break }
            if advance.label == "كشفت التالية" && advance.isEnabled { advance.tap() }
            _ = grade.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(grade.waitForExistence(timeout: 10), app.debugDescription); grade.tap()
        attach(app, "M2-V03-grade-L")
        // A grade moves on to the next page by itself.
        let nextPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "سمّعته كاملًا"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPage], timeout: 12), .completed)
        app.buttons["quran-session-close"].tap()
        XCTAssertTrue(app.buttons["quran-session-save-partial"].waitForExistence(timeout: 5))
        app.buttons["quran-session-save-partial"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["quran-resume"].waitForNonExistence(timeout: 6), app.buttons["quran-resume"].label)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-resume"].exists, "No draft survives a partial save")
        app.terminate()
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    /// Owner 20 Oct: review adapts to the page. A mastered, recent page is checked whole: one tap uncovers it and opens grading.
    func testMasteredPageIsCheckedWholeInOneTap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription); app.buttons["quran-begin"].tap()
        let advance = app.buttons["quran-session-advance"]
        let whole = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND label == %@", "سمّعته كاملًا"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [whole], timeout: 15), .completed, app.debugDescription)
        attach(app, "M2-V03-whole-check-L")
        advance.tap()
        XCTAssertTrue(app.buttons["quran-coach-grade-mastered"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "اكشف ")).count, 0, "the whole page is uncovered")
        attach(app, "M2-V03-whole-graded-L")
        app.terminate()
    }
    /// Owner 20 Oct: a finger dragged down the covered page uncovers every ayah it crosses, no button needed.
    func testDraggingAcrossTheCoveredPageRevealsAyahs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription); app.buttons["quran-begin"].tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        let covered = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "اكشف "))
        let before = covered.count
        XCTAssertGreaterThan(before, 2, app.debugDescription)
        attach(app, "M2-V03-drag-before-L")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)), end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 260, thenHoldForDuration: 0.3)
        let fewer = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _, _ in covered.count <= before - 2 }), object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fewer], timeout: 10), .completed, "before \(before), after \(covered.count)")
        XCTAssertTrue(app.staticTexts["quran-session-stage"].label.contains("كشفت"), app.staticTexts["quran-session-stage"].label)
        attach(app, "M2-V03-drag-after-L")
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
