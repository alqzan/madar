import XCTest

@MainActor final class RoomGlyphUITests: XCTestCase {
    func testWalkBuiltRoomsWithNativeRoomGlyphs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        XCTAssertTrue(app.buttons["tab-foundation"].waitForExistence(timeout: 20)) // habits is the first tab now
        for (tabID,id,name) in [("tab-foundation","bahw-block-year","lobby"),("tab-habits","habits-title","habits"),("tab-quran","quran-coverage-title","quran"),("tab-money","money-home","money"),("tab-mihbara","mihbara-add-paper","mihbara")] {
            app.buttons[tabID].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 10), tabID)
            capture(app, "UX-13-" + name + "-L")
        }
        app.buttons["tab-foundation"].tap()
        let year = app.descendants(matching: .any).matching(identifier: "bahw-block-year").firstMatch
        if !year.isHittable { app.swipeUp(velocity: .slow) }
        year.tap(); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-hero").firstMatch.waitForExistence(timeout: 10)); capture(app, "UX-13-year-L")
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        let city = app.buttons["first-run-city"]
        guard city.waitForExistence(timeout: 2) else { return }
        city.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription); field.tap(); field.typeText("الرياض")
        let hit = app.buttons["city-hit-الرياض"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription); hit.tap()
        XCTAssertTrue(city.waitForNonExistence(timeout: 8), app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
