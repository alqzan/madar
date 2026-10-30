import XCTest

@MainActor final class PrayerFirstDayUITests: XCTestCase {
    func testPrayerRootLinkClosesHistorySheetAndReturnsToToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_PRAYER_FIXTURE": "homeShowcase",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00",
            "MADAR_UI_TRACKING_START": "2026-10-01"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        app.tabBars.buttons["الصلاة"].tap()

        let streaks = app.buttons["prayer-streaks"]
        reveal(streaks, in: app); streaks.tap()
        let history = app.buttons["prayer-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(history.isHittable, app.debugDescription)
        history.tap()
        let month = app.staticTexts["prayer-history-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "AU-95-prayer-root-before-L")

        app.open(URL(string: "madar://prayer")!)

        XCTAssertTrue(month.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["prayer-today-summary"].waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "AU-95-prayer-root-after-L")
        app.terminate()
    }

    func testPolarDayLetsMeRecordAPrayerManually() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_PRAYER_FIXTURE": "polarNoTimes",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-06-21T12:00:00+02:00",
            "MADAR_UI_TRACKING_START": "2026-06-20"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        app.tabBars.buttons["الصلاة"].tap()

        let noTimes = app.staticTexts["prayer-no-times"]
        XCTAssertTrue(noTimes.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(noTimes.label.contains("اضغط قوس الصلاة"), noTimes.label)
        let fajr = app.descendants(matching: .any).matching(identifier: "prayer-arch-fajr").firstMatch
        XCTAssertTrue(fajr.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(fajr.isEnabled, app.debugDescription)
        XCTAssertTrue(fajr.label.contains("سجّلها يدويًا"), fajr.label)
        attachScreenshot(app, named: "M1-polar-no-times-before-L")

        fajr.tap()
        let alone = app.buttons["prayer-status-alone"]
        XCTAssertTrue(alone.waitForExistence(timeout: 10), app.debugDescription)
        alone.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        // The default heart question keeps the log sheet open after the prayer is saved.
        // Finish that real flow before checking or scrolling the home behind it.
        let skipHeart = app.buttons["prayer-heart-skip"]
        XCTAssertTrue(skipHeart.waitForExistence(timeout: 10), app.debugDescription)
        skipHeart.tap()
        XCTAssertTrue(alone.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(fajr.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(fajr.label.contains("وحدي"), fajr.label)
        XCTAssertTrue(fajr.label.contains("—"), fajr.label)
        XCTAssertFalse(app.buttons["prayer-pending-review"].exists, "No-time prayers do not become derived pending records.")
        XCTAssertTrue(noTimes.exists, app.debugDescription)
        XCTAssertFalse(app.alerts["لم تكتمل العملية"].exists, "A missing prayer boundary must not surface as a reminder refresh failure.")
        attachScreenshot(app, named: "M1-polar-no-times-logged-L")

        let streaks = app.buttons["prayer-streaks"]
        reveal(streaks, in: app)
        streaks.tap()
        let history = app.buttons["prayer-history"]
        reveal(history, in: app)
        history.tap()
        let yesterday = app.buttons["prayer-history-day-2026-06-20"]
        reveal(yesterday, in: app)
        yesterday.tap()
        let historicalManualLog = app.buttons["prayer-day-fajr-alone"]
        XCTAssertTrue(historicalManualLog.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(historicalManualLog.isEnabled, app.debugDescription)
        attachScreenshot(app, named: "M1-polar-history-edit-L")
        historicalManualLog.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.alerts["لم تكتمل العملية"].exists, app.debugDescription)
    }

    func testUnrecordedTodayAndActualPastGapUseDistinctCopy() throws {
        continueAfterFailure = false
        for past in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": past ? "light" : "dark", "MADAR_UI_NOW": "2026-10-15T22:00:00+03:00"]
            if past { app.launchEnvironment["MADAR_UI_TRACKING_START"] = "2026-10-01" }
            app.launch()
            if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
            let start = app.buttons["first-run-continue"]
            if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
            app.tabBars.buttons["الصلاة"].tap()
            let summary = app.staticTexts["prayer-today-summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.contains("لم تُسجَّل"), summary.label)
            XCTAssertFalse(summary.label.contains("بقيت"), summary.label)
            let old = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "من فترة سابقة")).firstMatch
            XCTAssertEqual(old.exists, past, app.debugDescription)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = past ? "UX-08-real-history-L" : "UX-08-first-night-L"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription)
        // A partly visible tall card can report hittable while its tap point is
        // beneath the floating accessory. Bring its centre into the clear area.
        for _ in 0..<12 {
            if element.isHittable && element.frame.midY < app.frame.maxY * 0.8 { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
        XCTAssertLessThan(element.frame.midY, app.frame.maxY * 0.8, app.debugDescription)
    }
}
