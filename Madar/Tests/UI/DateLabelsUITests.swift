import XCTest

@MainActor final class DateLabelsUITests: XCTestCase {
    func testPairedHeadersUpcomingAndGregorianPreference() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 20)); capture(app, "UX-11-diary-L")
        app.buttons["tab-foundation"].tap()
        let date = app.descendants(matching: .any).matching(identifier: "bahw-date").firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 10)); XCTAssertTrue(date.label.contains("١٤٤٨")); XCTAssertTrue(date.label.contains("٢٠٢٦"))
        capture(app, "UX-11-lobby-L")
        app.swipeUp(velocity: .slow); capture(app, "UX-11-upcoming-L"); app.swipeDown(velocity: .fast)
        app.buttons["tab-prayer"].tap(); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-today-header").firstMatch.waitForExistence(timeout: 10)); capture(app, "UX-11-prayer-L")
        app.buttons["tab-customize"].tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("core.firstCalendar\n")
        let gregorian = app.buttons["option-core.firstCalendar-gregorian"]; XCTAssertTrue(gregorian.waitForExistence(timeout: 5)); gregorian.tap()
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 10)); XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "الخميس ١٥ أكتوبر"), object: date)], timeout: 8), .completed)
        capture(app, "UX-11-gregorian-first-L")
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
