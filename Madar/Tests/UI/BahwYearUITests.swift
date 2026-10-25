import XCTest

/// M4-V03 · bahw/04-W3-Sana: the year screen opens from the lobby, shows the strips and what matters, and a user day saves and undoes.
@MainActor final class BahwYearUITests: XCTestCase {
    func testYearScreenAndUserDay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00",
                                 "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(element("bahw-block-year").waitForExistence(timeout: 15), app.debugDescription)
        element("bahw-block-year").tap()
        XCTAssertTrue(element("bahw-year-hero").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("bahw-year-hero").label.contains("رمضان بعد ١٢٢"), element("bahw-year-hero").label)
        for id in ["bahw-year-strip", "bahw-strip-month", "bahw-strip-week", "bahw-strip-day"] { XCTAssertTrue(element(id).exists, id) }
        XCTAssertFalse(element("bahw-strip-day").label.contains("·"))
        // v1 ships the strip only: no view switcher.
        XCTAssertFalse(app.buttons["العِقد"].exists)
        capture(app, "M4-V03-year-L")
        app.swipeUp(); XCTAssertTrue(element("bahw-matter-رمضان").waitForExistence(timeout: 5)); capture(app, "M4-V03-year-s1-L")
        app.swipeUp(); capture(app, "M4-V03-year-s2-L"); app.swipeDown()

        element("bahw-add-day").tap()
        let title = element("bahw-day-title"); XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("هدية أمي")
        app.buttons["bahw-day-save"].tap()
        XCTAssertTrue(element("bahw-matter-هدية أمي").waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["أيامي"].tap()
        XCTAssertTrue(element("bahw-matter-هدية أمي").waitForExistence(timeout: 5)); XCTAssertFalse(element("bahw-matter-رمضان").exists)
        capture(app, "M4-V03-mine-L")
        element("bahw-matter-هدية أمي").tap()
        let delete = app.buttons["bahw-day-delete"]; XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(element("bahw-matter-هدية أمي").waitForNonExistence(timeout: 8))
        element("bahw-year-back").tap()
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 5))
    }
    func testOneTimeDayBeyondTwoYearsHasPreviewSavesAndRelaunches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_HABIT_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-25T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_UNDO_SECONDS": "6"]
        func open() {
            let block = app.descendants(matching: .any)["bahw-block-year"]
            XCTAssertTrue(block.waitForExistence(timeout: 25))
            for _ in 0..<6 where !block.isHittable { app.swipeUp(velocity: .slow) }
            block.tap(); XCTAssertTrue(app.descendants(matching: .any)["bahw-year-hero"].waitForExistence(timeout: 10))
        }
        app.launch(); open()
        app.buttons["bahw-add-day"].tap()
        let title = app.textFields["bahw-day-title"]; XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText("موعد بعيد\n")
        app.segmentedControls["bahw-day-repeats"].buttons["مرة واحدة"].tap()
        let increment = app.buttons["bahw-day-year-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<4 { increment.tap() }
        let preview = app.staticTexts.matching(identifier: "bahw-day-date-preview")
        XCTAssertTrue(preview.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.allElementsBoundByIndex.contains { $0.label.contains("٢٠٣٠") })
        capture(app, "M4-V03-far-future-preview-L")
        app.buttons["bahw-day-save"].tap(); app.buttons["أيامي"].tap()
        let saved = app.descendants(matching: .any).matching(identifier: "bahw-matter-موعد بعيد").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        _ = app.buttons["تراجع"].waitForNonExistence(timeout: 8)
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(saved.isHittable)
        capture(app, "M4-V03-far-future-saved-L")
        app.terminate(); app.launch(); open(); app.buttons["أيامي"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-matter-موعد بعيد").firstMatch.waitForExistence(timeout: 10))
    }
    /// Owner, 25 Oct: a passed one-time day with «واصل العدّ بعد الموعد» stays and shows the days since it.
    func testPassedOneTimeDayKeepsCountingWhenAsked() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_HABIT_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-25T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_UNDO_SECONDS": "6"]
        app.launch()
        let block = app.descendants(matching: .any)["bahw-block-year"]
        XCTAssertTrue(block.waitForExistence(timeout: 25))
        for _ in 0..<6 where !block.isHittable { app.swipeUp(velocity: .slow) }
        block.tap(); XCTAssertTrue(app.descendants(matching: .any)["bahw-year-hero"].waitForExistence(timeout: 10))
        app.buttons["bahw-add-day"].tap()
        let title = app.textFields["bahw-day-title"]; XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText("أول يوم\n")
        app.segmentedControls["bahw-day-repeats"].buttons["مرة واحدة"].tap()
        let decrement = app.buttons["bahw-day-year-Decrement"]; XCTAssertTrue(decrement.waitForExistence(timeout: 5)); decrement.tap()
        let toggle = app.switches["bahw-day-count-up"]; XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // Without the option a passed one-time day has no occurrence to preview; with it, the day itself shows.
        XCTAssertFalse(app.staticTexts.matching(identifier: "bahw-day-date-preview").firstMatch.exists)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts.matching(identifier: "bahw-day-date-preview").firstMatch.waitForExistence(timeout: 5))
        capture(app, "M4-V03-count-up-editor-L")
        app.buttons["bahw-day-save"].tap(); app.buttons["أيامي"].tap()
        let saved = app.descendants(matching: .any).matching(identifier: "bahw-matter-أول يوم").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        // 25 Oct 2025 to 25 Oct 2026 is 365 whole days.
        XCTAssertTrue(saved.label.contains("٣٦٥") && saved.label.contains("مضت"), saved.label)
        _ = app.buttons["تراجع"].waitForNonExistence(timeout: 8)
        capture(app, "M4-V03-count-up-saved-L")
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
