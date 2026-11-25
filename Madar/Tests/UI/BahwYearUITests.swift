import XCTest

/// M4-V03 · bahw/04-W3-Sana: the year screen opens from the lobby, shows the strips and what matters, and a user day saves and undoes.
@MainActor final class BahwYearUITests: XCTestCase {
    func testYearScreenAndUserDay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00", "MADAR_UI_THEME": "light"]
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

        let mattersCount = app.staticTexts.containing(NSPredicate(format: "label ENDSWITH %@", "الأقرب أولًا")).firstMatch
        app.buttons["أيامي"].tap()
        XCTAssertTrue(app.staticTexts["لم تضف يومًا بعد. أضف يومًا يهمّك ليظهر هنا."].waitForExistence(timeout: 5))
        XCTAssertFalse(mattersCount.exists)
        app.buttons["المواسم"].tap()
        XCTAssertTrue(mattersCount.waitForExistence(timeout: 5))
        element("bahw-add-day").tap()
        let title = element("bahw-day-title"); XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("هدية أمي")
        app.buttons["bahw-day-save"].tap()
        XCTAssertTrue(element("bahw-matter-هدية أمي").waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["أيامي"].isSelected)
        XCTAssertFalse(element("bahw-matter-رمضان").exists)
        capture(app, "M4-V03-mine-L")
        element("bahw-matter-هدية أمي").tap()
        let delete = app.buttons["bahw-day-delete"]; XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        app.slideToConfirm(fraction: 0.4)
        let cancel = app.buttons["madar-swipe-cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.madarSwipeConfirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        app.slideToConfirm()
        XCTAssertTrue(element("bahw-matter-هدية أمي").waitForNonExistence(timeout: 8))
        element("bahw-year-back").tap()
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 5))
    }
    func testSelectedYearStillShowsItsOtherCalendar() throws {
        continueAfterFailure = false
        for (mode, attachment) in [("hijri", "M4-V03-year-hijri-paired-L"), ("gregorian", "M4-V03-year-gregorian-paired-L")] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00", "MADAR_UI_THEME": "light", "MADAR_UI_UNDO_SECONDS": "2"]
            app.launch(); finishOnboarding(app)
            // The lobby's own «خصّص مدار» door: the path a person takes.
            let customize = app.buttons["bahw-customize"]
            XCTAssertTrue(customize.waitForExistence(timeout: 10), app.debugDescription)
            customize.tap()
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
            search.tap(); search.typeText("أي سنة")
            let option = app.buttons["option-bahw.yearWhich-\(mode)"]
            XCTAssertTrue(option.waitForExistence(timeout: 8), app.debugDescription)
            option.tap()
            // Choosing the room tab dismisses the keyboard. Its Search key may still
            // appear in accessibility after it has moved below the screen.
            let lobby = app.buttons["tab-foundation"]
            XCTAssertTrue(lobby.waitForExistence(timeout: 8), app.debugDescription)
            lobby.tap()
            let yearBlock = app.descendants(matching: .any)["bahw-block-year"]
            XCTAssertTrue(yearBlock.waitForExistence(timeout: 10), app.debugDescription)
            for _ in 0..<5 where !yearBlock.isHittable { app.swipeUp(velocity: .slow) }
            yearBlock.tap()
            let hero = app.descendants(matching: .any)["bahw-year-hero"]
            XCTAssertTrue(hero.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(hero.label.contains("هـ") && hero.label.contains("م"), hero.label)
            let strip = app.descendants(matching: .any)["bahw-year-strip"]
            XCTAssertTrue(strip.label.contains("هـ") && strip.label.contains("م"), strip.label)
            XCTAssertTrue(app.buttons["undo-button"].waitForNonExistence(timeout: 12), "Wait for the settings receipt before capturing the year screen.")
            capture(app, attachment)
            app.terminate()
        }
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
        let repeats = app.segmentedControls["bahw-day-repeats"]
        repeats.buttons["كل سنة"].tap()
        repeats.buttons["مرة واحدة"].tap()
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
    func testConvertingYearlyDayToOneTimeKeepsItsNextOccurrence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_HABIT_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-25T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let year = app.descendants(matching: .any)["bahw-block-year"].firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 25))
        for _ in 0..<6 where !year.isHittable { app.swipeUp(velocity: .slow) }
        year.tap()
        let add = app.buttons["bahw-add-day"]
        for _ in 0..<6 where !add.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(add.isHittable, app.debugDescription)
        add.tap()

        let title = app.textFields["bahw-day-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText("موعد دوري\n")
        let month = app.buttons["bahw-day-month"].firstMatch
        for _ in 0..<5 where !month.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(month.isHittable, app.debugDescription)
        month.tap()
        let may = app.buttons["مايو"].firstMatch
        XCTAssertTrue(may.waitForExistence(timeout: 5), app.debugDescription)
        may.tap()

        let save = app.buttons["bahw-day-save"]
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        app.buttons["أيامي"].tap()
        let saved = app.descendants(matching: .any).matching(identifier: "bahw-matter-موعد دوري").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !saved.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saved.isHittable, app.debugDescription)
        saved.tap()

        let once = app.segmentedControls["bahw-day-repeats"].buttons["مرة واحدة"]
        XCTAssertTrue(once.waitForExistence(timeout: 5))
        once.tap()
        let date = NSPredicate(format: "label CONTAINS %@", "٢٥ مايو ٢٠٢٧")
        let preview = app.staticTexts.matching(identifier: "bahw-day-date-preview").matching(date).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(save.isHittable, app.debugDescription)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(date.evaluate(with: saved), saved.label)
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
        XCTAssertTrue(saved.label.contains("٣٦٥") && saved.label.contains("مضى"), saved.label)
        _ = app.buttons["تراجع"].waitForNonExistence(timeout: 8)
        capture(app, "M4-V03-count-up-saved-L")
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        // This store reaches the location step: without a city the first-run cover stays over the lobby and every tap below is lost.
        let city = app.buttons["first-run-city"]
        guard city.waitForExistence(timeout: 2) else { return }
        city.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription); field.tap(); field.typeText("الرياض")
        let hit = app.buttons["city-hit-الرياض"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription); hit.tap()
        if field.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        let later = app.buttons["first-run-continue"]
        // B2-12: first run now ends after the city, so the second «متابعة» may not exist.
        if later.waitForExistence(timeout: 3) { later.tap(); XCTAssertTrue(later.waitForNonExistence(timeout: 5), app.debugDescription) }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { guard ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] != nil else { return }; let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}

extension XCUIApplication {
    /// The swipe-to-confirm sheet (owner, 23 Nov): drag its knob across the track.
    var madarSwipeConfirm: XCUIElement { descendants(matching: .any)["madar-swipe-confirm"].firstMatch }
    func slideToConfirm(fraction: CGFloat = 1, file: StaticString = #filePath, line: UInt = #line) {
        let track = madarSwipeConfirm
        XCTAssertTrue(track.waitForExistence(timeout: 5), debugDescription, file: file, line: line)
        let center = track.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -29, dy: 0))
        let destination = center.withOffset(CGVector(dx: -fraction * (track.frame.width - 40), dy: 0))
        center.press(forDuration: 0.1, thenDragTo: destination)
    }
}
