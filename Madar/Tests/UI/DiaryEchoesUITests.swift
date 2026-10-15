import XCTest

@MainActor final class DiaryEchoesUITests: XCTestCase {
    func testEchoesReadOriginalAndJumpToOlderDistance() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "echoes", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-echo-1w"].waitForExistence(timeout: 30), app.debugDescription)
        capture(app, "M3-V02-echoes-L")
        app.buttons["diary-echo-1w"].tap()
        XCTAssertTrue(app.staticTexts["جلست بعد الفجر حتى الشروق."].waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap()
        app.buttons["diary-echo-jump-1m"].tap()
        XCTAssertTrue(app.buttons["diary-echo-1m"].waitForExistence(timeout: 10))
        app.buttons["diary-echo-1m"].tap()
        XCTAssertTrue(app.staticTexts["قهوة وحديث طويل مع أخي."].waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap()
        XCTAssertTrue(app.buttons["diary-write"].isHittable)
        capture(app, "M3-V02-echoes-scrolled-L")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
