import XCTest

@MainActor final class RoomGlyphUITests: XCTestCase {
    func testWalkBuiltRoomsWithNativeRoomGlyphs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 20))
        capture(app, "UX-13-diary-L")
        for (tabID,id,name) in [("tab-foundation","bahw-block-salah","lobby"),("tab-prayer","prayer-today-header","prayer"),("tab-quran","quran-coverage-title","quran"),("tab-money","money-home","money"),("tab-mihbara","mihbara-add-paper","mihbara")] {
            app.buttons[tabID].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 10), tabID)
            capture(app, "UX-13-" + name + "-L")
        }
        app.buttons["tab-foundation"].tap()
        let year = app.descendants(matching: .any).matching(identifier: "bahw-block-year").firstMatch
        if !year.isHittable { app.swipeUp(velocity: .slow) }
        year.tap(); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-hero").firstMatch.waitForExistence(timeout: 10)); capture(app, "UX-13-year-L")
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
