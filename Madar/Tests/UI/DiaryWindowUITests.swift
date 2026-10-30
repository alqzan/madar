import XCTest

@MainActor final class DiaryWindowUITests: XCTestCase {
    private func launch(_ variant: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": variant,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        return app
    }
    func testWindowYearsMarginTodayAndRelaunch() throws {
        continueAfterFailure = false
        let app = launch("home")
        let currentMonth = app.descendants(matching: .any)["diary-current-month"]
        XCTAssertTrue(currentMonth.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(currentMonth.label.contains("أكتوبر"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("ربيع"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("جمادى"), currentMonth.label)
        XCTAssertTrue(app.buttons["diary-year-2025-10-15"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "M3-V01-window-L")
        // OR-10: one card per past year, newest first; a card opens that day, whose «اكتب في هامشها» writes the margin.
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].exists, app.debugDescription)
        XCTAssertLessThan(app.buttons["diary-year-2025-10-15"].frame.minY, app.buttons["diary-year-2024-10-15"].frame.minY)
        XCTAssertFalse(app.buttons["diary-year-previous"].exists)
        app.swipeUp()
        capture(app, "M3-V01-window-scrolled-L")
        app.swipeDown()
        app.buttons["diary-year-2024-10-15"].tap()
        XCTAssertTrue(app.staticTexts["مشينا بعد المغرب، والجو صار يحتمل."].waitForExistence(timeout: 8))
        let margin = app.buttons["diary-day-write"]
        XCTAssertTrue(margin.waitForExistence(timeout: 8)); XCTAssertTrue(margin.label.contains("هامش"), margin.label); margin.tap()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("هامش من يومي")
        capture(app, "M3-V01-margin-editor-L")
        app.buttons["diary-editor-save"].tap()
        if app.buttons["diary-day-close"].waitForExistence(timeout: 5) { app.buttons["diary-day-close"].tap() }
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "هامش من يومي")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["diary-day-close"].tap()
        app.buttons["diary-write"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("سطر محفوظ من اليوم")
        capture(app, "M3-V01-text-editor-L")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["سطر محفوظ من اليوم"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-today-L")
    }
    func testHomeReadFailureAfterFirstSnapshotShowsRetryInsteadOfStalePage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "home",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_DIARY_HOME_READ_FAILURE_AFTER_FIRST": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        let retry = app.buttons["diary-home-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-today"].exists, "A stale page must not remain available after its refresh fails.")
        capture(app, "AU-95-diary-home-read-failure-L")
        retry.tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "AU-95-diary-home-read-recovered-L")
        app.terminate()
    }
    func testEntryRouteScrollsToAndBrieflyHighlightsItsLine() throws {
        let app = launch("entryRoute")
        let id = "44444444-4444-4444-8444-444444440001"
        app.open(URL(string: "madar://notes/entry/\(id)")!)
        let target = app.descendants(matching: .any)["diary-entry-\(id)"]
        XCTAssertTrue(target.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(target.isHittable, "The diary entry link must land on its exact line.")
        capture(app, "AU-95-diary-entry-route-highlight-L")
        app.terminate()
    }
    func testRepeatedEntryRouteTargetsAnotherLineInTheSameOpenDay() throws {
        let app = launch("entryRoute")
        let first = "44444444-4444-4444-8444-444444440001"
        let second = "44444444-4444-4444-8444-444444440002"
        app.open(URL(string: "madar://notes/entry/\(first)")!)
        XCTAssertTrue(app.descendants(matching: .any)["diary-entry-\(first)"].waitForExistence(timeout: 15), app.debugDescription)
        app.open(URL(string: "madar://notes/entry/\(second)")!)
        let target = app.descendants(matching: .any)["diary-entry-\(second)"]
        XCTAssertTrue(target.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(target.isHittable, "A second entry route must retarget the already-open day sheet.")
        capture(app, "AU-95-diary-entry-route-repeat-L")
        app.terminate()
    }
    func testDiarySearchRouteUpdatesTheAlreadyOpenSearch() throws {
        let app = launch("home")
        func openSearch(_ query: String) {
            var url = URLComponents(); url.scheme = "madar"; url.host = "search"
            url.queryItems = [.init(name: "q", value: query), .init(name: "room", value: "notes")]
            app.open(url.url!)
        }
        openSearch("عشاء")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary-search-result-")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        openSearch("اتصلت")
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary-search-result-")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(second.label.contains("اتصلت"), second.label)
        XCTAssertEqual(app.textFields["diary-search-query"].value as? String, "اتصلت")
        app.terminate()
    }
    func testSameLetterAndProjectRoutesReopenTheirDetails() throws {
        let app = launch("letters")
        let letterURL = URL(string: "madar://notes/letter/33333333-3333-4333-8333-333333333331")!
        app.open(letterURL)
        let letterOpen = app.buttons["diary-letter-open"]
        XCTAssertTrue(letterOpen.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["diary-letter-done"].tap()
        XCTAssertTrue(letterOpen.waitForNonExistence(timeout: 8), app.debugDescription)
        app.open(letterURL)
        XCTAssertTrue(app.buttons["diary-letter-open"].waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["diary-letter-done"].tap()

        let projectURL = URL(string: "madar://notes/project/44444444-4444-4444-8444-444444444441")!
        app.open(projectURL)
        let projectTitle = app.navigationBars["ترتيب البيت"]
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["تمّ"].tap()
        XCTAssertTrue(projectTitle.waitForNonExistence(timeout: 8), app.debugDescription)
        app.open(projectURL)
        XCTAssertTrue(app.navigationBars["ترتيب البيت"].waitForExistence(timeout: 12), app.debugDescription)
        app.terminate()
    }
    func testMemoriesReadFailureCanRetryInTheArchive() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "letters",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_DIARY_MEMORIES_READ_FAILURE_ONCE": "1"]
        app.launch(); XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://notes/letters")!)
        let memories = app.buttons["diary-hub-memories"]
        XCTAssertTrue(memories.waitForExistence(timeout: 15), app.debugDescription)
        memories.tap()
        XCTAssertTrue(app.staticTexts["diary-hub-memory-error"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["diary-hub-memories-retry"].tap()
        XCTAssertTrue(app.staticTexts["diary-hub-memory-error"].waitForNonExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    /// OR-13: a heading and bold written with the editor's tools show formatted on the page, never as raw marks.
    func testEditorHeadingAndBoldShowFormatted() throws {
        continueAfterFailure = false
        let app = launch("home")
        app.buttons["diary-write"].tap()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10))
        func waitValue(_ contains: String) { _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", contains), object: editor)], timeout: 8) }
        // The text view's accessibility value lags programmatic edits, so the result is checked on the saved page.
        editor.tap(); editor.typeText("مساء هادئ"); waitValue("مساء هادئ")
        app.buttons["diary-editor-heading"].tap()
        editor.typeText("\nكان يومًا طويلًا"); waitValue("طويلًا")
        app.buttons["diary-editor-bold"].tap()
        capture(app, "OR-13-editor-tools-L")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10)); app.buttons["diary-today"].tap()
        let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "كان يومًا طويلًا")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(line.label.contains("*") || line.label.contains("#"), line.label)
        XCTAssertTrue(line.label.contains("مساء هادئ"), line.label)
        capture(app, "OR-13-formatted-page-L")
    }
    func testFirstDayHasWorkingOneTapKeyboardAndCancelWritesNothing() throws {
        continueAfterFailure = false
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["صفحتك الأولى"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-first-day-L")
        app.buttons["diary-write"].tap()
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textViews["diary-editor-text"].typeText("لن يحفظ")
        app.buttons["diary-editor-cancel"].tap()
        app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["صفحة تنتظر سطرك."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["لن يحفظ"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
