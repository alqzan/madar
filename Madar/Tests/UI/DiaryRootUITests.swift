import XCTest

/// 14 Nov (T10): the room opens on today's page itself, with the year strip over it, and writing needs no send button.
/// The legacy suites run with the home-first flag; this suite runs the shipping root (`MADAR_UI_DIARY_ROOT=1`).
@MainActor final class DiaryRootUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_DIARY_ROOT": "1",
                                 "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }

    func testRoomOpensOnTodaysPageWithNothingPushed() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10), "Today's lines are on the first screen")
        XCTAssertFalse(app.buttons["diary-today"].exists, "No home card to tap before the page")
        XCTAssertFalse(app.staticTexts["diary-home-title"].exists)
        capture(app, "T10-root-today-L")
    }
    func testWritingNeedsNoSendButtonAndKeyboardDoneWritesTheLine() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        let field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        field.tap(); field.typeText("سطر بلا زر إرسال")
        XCTAssertFalse(app.buttons["diary-inline-send"].exists, "New words have no send button")
        XCTAssertTrue(app.buttons["diary-keyboard-done"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["diary-keyboard-done"].tap()
        XCTAssertTrue(app.staticTexts["سطر بلا زر إرسال"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "T10-root-written-L")
    }
    func testWriteRouteStaysOnTheRootPageAndFocusesTheField() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://notes/write")!)
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-day-close"].exists, "Nothing was pushed: there is no page to close")
    }
    func testYearStripSitsOverTodayAndOpensThatDay() throws {
        continueAfterFailure = false
        let app = launch("home")
        let strip = app.descendants(matching: .any)["diary-year-strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-day-more"].exists, "The strip is over today's page, not instead of it")
        capture(app, "T10-root-year-strip-L")
        strip.tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testLeavingTheAppWritesWhatWasTypedAsOneLine() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        let field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        field.tap(); field.typeText("كتبته ثم غادرت")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["كتبته ثم غادرت"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.staticTexts.matching(identifier: "كتبته ثم غادرت").count, 1, "One paragraph, one line")
    }
    func testScrollingThePageDoesNotCommitHalfAParagraph() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        let field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        field.tap(); field.typeText("نصف فقرة")
        app.swipeDown()
        XCTAssertFalse(app.staticTexts["نصف فقرة"].exists, "Dragging the page is not a boundary: the words stay in the field")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard stays up while writing on the page")
    }
    func testRestoredDraftIsNotCommittedWhenTheAppLeavesUntouched() throws {
        continueAfterFailure = false
        let store = UUID().uuidString
        func start() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1",
                                     "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
            app.launch(); return app
        }
        var app = start()
        var field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        field.tap(); field.typeText("مسودة لم ألمسها")
        Thread.sleep(forTimeInterval: 2)   // autosave runs 600 ms after the last key
        app.terminate()
        app = start()
        field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(((field.value as? String) ?? "").contains("مسودة لم ألمسها"), "The draft is restored into the field")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["مسودة لم ألمسها"].exists, "An untouched restored draft is never committed at a boundary")
    }
}
