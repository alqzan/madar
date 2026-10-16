import XCTest

@MainActor final class CustomizeSearchUITests: XCTestCase {
    func testClearRestoresSettingsInOneTap() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); let tab = app.tabBars.buttons["خصّص"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المظهر")
        let clear = app.buttons["settings-clear-search"]; XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Improve-search-after-L"; attachment.lifetime = .keepAlways; add(attachment)
        clear.tap(); XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(search.value as? String, "المظهر")
        XCTAssertTrue(app.buttons["room-widgets-gallery"].exists)
    }
}
