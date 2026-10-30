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

    func testPrayerCustomizeExposesSupportedSettingsAndPersistsTravelChoice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00", "MADAR_UI_PRAYER_FIXTURE": "homeShowcase"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        if app.buttons["first-run-continue"].waitForExistence(timeout: 2) { app.buttons["first-run-continue"].tap() }
        app.tabBars.buttons["الصلاة"].tap()
        let customize = app.buttons["prayer-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10)); customize.tap()

        let riwaq = app.buttons["prayer-customize-card-riwaq"]
        reveal(riwaq, in: app); riwaq.tap()
        XCTAssertTrue(app.switches["setting-salah.pool"].exists, app.debugDescription)
        XCTAssertTrue(app.switches["setting-salah.fridayTallArch"].exists, app.debugDescription)

        let log = app.buttons["prayer-customize-card-log"]
        reveal(log, in: app); log.tap()
        XCTAssertTrue(app.steppers["setting-salah.pendingDays"].exists, app.debugDescription)

        let times = app.buttons["prayer-customize-card-times"]
        reveal(times, in: app); times.tap()
        XCTAssertTrue(app.buttons["option-salah.tripMethod-ummAlQura"].exists, app.debugDescription)
        let travel = app.switches["setting-salah.travelShortenCombine"]
        XCTAssertTrue(travel.exists, app.debugDescription)
        XCTAssertEqual(travel.value as? String, "1")
        reveal(travel, in: app)
        travel.tap()
        waitValue(travel, "0")

        let remind = app.buttons["prayer-customize-card-remind"]
        reveal(remind, in: app); remind.tap()
        XCTAssertTrue(app.buttons["option-salah.qadaReminder-afterIsha"].exists, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["setting-salah.balanceView"].exists, "RA8 keeps the v2 balance view out of v1.")

        app.terminate(); app.launch()
        app.tabBars.buttons["الصلاة"].tap()
        let reopened = app.buttons["prayer-customize"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10)); reopened.tap()
        let timesAgain = app.buttons["prayer-customize-card-times"]
        reveal(timesAgain, in: app); timesAgain.tap()
        let persisted = app.switches["setting-salah.travelShortenCombine"]
        reveal(persisted, in: app)
        waitValue(persisted, "0")
        capture(app, "AU-95-prayer-settings-complete-L")
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
