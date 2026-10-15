import XCTest

@MainActor final class PrayerCountdownUITests: XCTestCase {
    func testActivitySettingDefaultsOffPersistsAndUndoesAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00", "MADAR_UI_PRAYER_FIXTURE": "homeShowcase"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        if app.buttons["first-run-continue"].waitForExistence(timeout: 2) { app.buttons["first-run-continue"].tap() }
        openReminders(app)
        let toggle = app.switches["setting-salah.liveActivity"]
        XCTAssertEqual(toggle.value as? String, "0")
        capture(app, "M1-F04-activity-default-off-L")
        toggle.tap()
        waitValue(toggle, "1")
        app.terminate(); app.launch()
        openReminders(app)
        waitValue(toggle, "1")
        toggle.tap(); waitValue(toggle, "0")
        let undo = app.buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap(); waitValue(toggle, "1")
        capture(app, "M1-F04-activity-enabled-L")
    }
    private func openReminders(_ app: XCUIApplication) {
        app.tabBars.buttons["الصلاة"].tap()
        let settings = app.buttons["prayer-customize"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let card = app.buttons["prayer-customize-card-remind"]
        for _ in 0..<12 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        let toggle = app.switches["setting-salah.liveActivity"]
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable, app.debugDescription)
    }
    private func waitValue(_ element: XCUIElement, _ value: String) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 8), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
