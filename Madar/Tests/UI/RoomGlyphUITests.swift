import XCTest

@MainActor final class RoomGlyphUITests: XCTestCase {
    func testWalkBuiltRoomsWithNativeRoomGlyphs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 20))
        capture(app, "UX-13-diary-L")
        for (tab,id,name) in [("البهو","bahw-block-salah","lobby"),("الصلاة","prayer-today-header","prayer"),("القرآن","quran-coverage-title","quran"),("المال","money-home","money"),("المحبرة","mihbara-add-paper","mihbara")] {
            app.otherElements["fixed-tab-bar"].buttons[tab].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 10), tab)
            capture(app, "UX-13-" + name + "-L")
        }
        app.buttons["tab-foundation"].tap()
        let year = app.descendants(matching: .any).matching(identifier: "bahw-block-year").firstMatch
        if !year.isHittable { app.swipeUp(velocity: .slow) }
        year.tap(); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-hero").firstMatch.waitForExistence(timeout: 10)); capture(app, "UX-13-year-L")
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
