import XCTest

@MainActor final class QuranOutsideUITests: XCTestCase {
    func testLiveWidgetTemplatesReminderSaveRelaunchResetAndUndoAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); open(app)
        attach(app, "M2-V07-widgets-L")
        let choice = app.buttons["quran-reminder-choice"]
        for _ in 0..<3 { if choice.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(choice.isHittable); choice.tap(); app.buttons["quran-reminder-afterIsha"].tap()
        wait(choice, "بعد العشاء")
        attach(app, "M2-V07-reminders-L")
        app.terminate(); app.launch(); open(app)
        for _ in 0..<3 { if choice.isHittable { break }; app.swipeUp() }
        wait(choice, "بعد العشاء")
        app.buttons["quran-reminder-reset"].tap(); wait(choice, "بعد الفجر")
        app.descendants(matching: .any)["quran-reminder-undo"].buttons["تراجع"].tap(); wait(choice, "بعد العشاء")
        app.terminate()
    }
    func testReviewControlRouteStartsDurableTimerAndCanDiscard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/session/review"]
        app.launch()
        let method = app.buttons["quran-session-method"]
        XCTAssertTrue(method.waitForExistence(timeout: 25), app.debugDescription); method.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-review-timer"].waitForExistence(timeout: 5))
        attach(app, "M2-V07-review-timer-L")
        app.buttons["quran-method-done"].tap()
        app.buttons["quran-session-close"].tap()
        app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        app.terminate()
    }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-outside"]
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-widget-preview-coverage"].waitForExistence(timeout: 10))
    }
    private func wait(_ item: XCUIElement, _ label: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", label), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
