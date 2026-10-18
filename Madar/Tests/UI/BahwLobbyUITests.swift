import XCTest

/// M4-V01 · bahw/02-W1-Bahw: the lobby shows built rooms only, arranges through settings, and opens a room directly.
@MainActor final class BahwLobbyUITests: XCTestCase {
    func testLobbyBuiltBlocksArrangeAndOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00",
                                 "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_PRAYER_FIXTURE": "homeShowcaseFriday",
                                 "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_HABIT_FIXTURE": "showcase",
                                 "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        app.tabBars.buttons["البهو"].tap()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(element("bahw-greeting").label, "مساء الخير")
        XCTAssertFalse(element("bahw-date").label.contains("·"))
        for block in ["habits", "salah", "quran", "mal", "year", "upcoming"] { XCTAssertTrue(element("bahw-block-" + block).exists, block) }
        // Mihbara waits for M6; money is now built in M5.
        for block in ["mihbara"] { XCTAssertFalse(element("bahw-block-" + block).exists, block) }
        XCTAssertTrue(element("bahw-salah-next").label.contains("المغرب"), element("bahw-salah-next").label)
        capture(app, "M4-V01-lobby-L")
        app.swipeUp(); XCTAssertTrue(element("bahw-block-notes").waitForExistence(timeout: 5)); capture(app, "M4-V01-lobby-s1-L")
        app.swipeDown()

        element("bahw-block-salah").press(forDuration: 0.7)
        let hide = app.buttons["bahw-hide-year"]; XCTAssertTrue(hide.waitForExistence(timeout: 5)); hide.tap()
        XCTAssertTrue(element("bahw-block-year").waitForNonExistence(timeout: 5))
        app.swipeUp(); app.buttons["bahw-drawer"].tap()
        let show = app.buttons["bahw-show-year"]; XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        XCTAssertTrue(element("bahw-block-year").waitForExistence(timeout: 5))
        app.swipeDown(); app.buttons["bahw-arrange"].tap()

        element("bahw-block-salah").tap()
        XCTAssertTrue(element("prayer-today-header").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["bahw-open-prayer"].exists)
        capture(app, "UX-02-direct-prayer-L")
    }
    func testHabitWideAndSmallBlocksShowAtRisk() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "atRisk", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let habits = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        XCTAssertTrue(habits.waitForExistence(timeout: 15))
        habits.press(forDuration: 0.7)
        let size = app.buttons["bahw-size-habits"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.tap()
        let wide = app.buttons["عريضة"]
        XCTAssertTrue(wide.waitForExistence(timeout: 5))
        wide.tap()
        app.buttons["bahw-arrange"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        let next = app.buttons["bahw-habits-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(next.label.contains("التالي: الماء"), next.label)
        XCTAssertTrue(next.label.contains("فاتتك فترة في الماء"), next.label)
        capture(app, "M4-V01-habit-wide-after-L")

        habits.press(forDuration: 0.7)
        size.tap()
        let small = app.buttons["صغيرة"]
        XCTAssertTrue(small.waitForExistence(timeout: 5))
        small.tap()
        app.buttons["bahw-arrange"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        let risk = app.staticTexts["bahw-habits-at-risk"]
        XCTAssertTrue(risk.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(risk.label, "فاتتك فترة")
        capture(app, "M4-V01-habit-small-after-L")
    }
    func testNextFajrAfterIsha() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T22:00:00+03:00"]
        app.launch(); finishOnboarding(app)
        let next = app.descendants(matching: .any).matching(identifier: "bahw-salah-next").firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(next.label.contains("الفجر"), next.label)
        XCTAssertTrue(next.label.contains("بعد"), next.label)
        capture(app, "UX-03-next-fajr-L")
    }
    func testYearSummaryAvoidsDuplicateSeasonsAndDate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let year = app.descendants(matching: .any).matching(identifier: "bahw-block-year").firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 15))
        let text = year.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        for duplicate in ["رمضان", "العيد", "عرفة", "أكتوبر", "ربيع"] { XCTAssertFalse(text.contains(duplicate), text) }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-hijri").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-gregorian").firstMatch.exists)
        capture(app, "UX-04-year-strips-L")
    }
    func testGreetingScrollsAndEditingControlsStayContextual() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let greeting = app.staticTexts["bahw-greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["bahw-arrange"].exists)
        XCTAssertFalse(app.buttons["settings-button"].exists)
        capture(app, "UX-14-lobby-L")
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
        XCTAssertFalse(greeting.isHittable)
        capture(app, "UX-14-lobby-s1-L")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        let prayer = app.descendants(matching: .any).matching(identifier: "bahw-block-salah").firstMatch
        prayer.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForExistence(timeout: 5))
        app.buttons["bahw-arrange"].tap()
        XCTAssertFalse(app.buttons["bahw-arrange"].exists)
        app.tabBars.buttons["خصّص"].tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10))
    }
    func testUpcomingShowsGregorianDatesAndComparableRings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); finishOnboarding(app)
        let upcoming = app.descendants(matching: .any).matching(identifier: "bahw-block-upcoming").firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 15))
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(upcoming.isHittable)
        let dates = upcoming.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(dates.contains("فبراير"), dates)
        // Both dates always (owner, 15 Oct): the Hijri date sits beside the Gregorian one.
        capture(app, "UX-06-upcoming-L")
    }
    func testEmptyDiaryOpensWriterAndKeepsDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let notes = app.descendants(matching: .any).matching(identifier: "bahw-block-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["bahw-notes-count"].label.contains("اكتب سطر اليوم"))
        capture(app, "UX-07-invitation-L")
        notes.tap()
        let writer = app.textViews["diary-editor-text"]
        XCTAssertTrue(writer.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        writer.typeText("بداية هادئة من البهو")
        capture(app, "UX-07-writer-L")
        app.buttons["diary-editor-cancel"].tap()
        app.buttons["diary-write"].tap()
        XCTAssertTrue(writer.waitForExistence(timeout: 5))
        XCTAssertEqual(writer.value as? String, "بداية هادئة من البهو")
    }
    func testNativeMinimizedBarAndVisibleTabsSwitchOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 20))
        app.tabBars.buttons["البهو"].tap()
        XCTAssertTrue(app.staticTexts["bahw-greeting"].waitForExistence(timeout: 10))
        app.swipeUp(velocity: .slow)
        capture(app, "UX-10-native-scrolled-L")
        let quran = app.tabBars.buttons["القرآن"]
        print("UX-10 collapsed Quran: exists=\(quran.exists), hittable=\(quran.isHittable)")
        if !quran.isHittable { app.tabBars.buttons["البهو"].tap() }
        XCTAssertTrue(quran.waitForExistence(timeout: 5)); quran.tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "UX-10-single-tap-quran-L")
        for (tab, id, shortcutID) in [
            ("الصلاة", "prayer-today-header", ""),
            ("خصّص", "settings-search", ""),
            ("المذكرات", "diary-home-title", "notes"),
            ("المال", "money-home", "money"),
            ("المحبرة", "mihbara-add-paper", "mihbara"),
            ("البهو", "bahw-block-salah", "")
        ] {
            if shortcutID.isEmpty { app.tabBars.buttons[tab].tap() }
            else { app.buttons["tab-\(shortcutID)"].tap() }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 10), tab + app.debugDescription)
        }
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
