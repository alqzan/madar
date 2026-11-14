import XCTest

/// 12 Nov: the home opens on today's page (one card with the write control) and the composer grows in place.
@MainActor final class DiaryHomeTodayUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }

    func testTodayCardShowsLatestLinesWithOneWriteControl() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["diary-today-date"].exists)
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].exists, "The card quotes the latest lines of today")
        XCTAssertTrue(app.staticTexts["سطر اختبار رابط اليوميات"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "diary-write").count, 1, "One write control on screen, not a card and a bar")
        capture(app, "B-home-today-card-L")
        app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10))
    }
    func testWriteCapsuleOpensTodayWithTheComposerFocused() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); app.buttons["diary-write"].tap()
        XCTAssertTrue(app.textFields["diary-inline-field"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "The cursor is already in the composer")
    }
    func testEmptyTodayIsAWarmInvitation() throws {
        continueAfterFailure = false
        let app = launch("empty")
        XCTAssertTrue(app.descendants(matching: .any)["diary-today-invitation"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-write"].exists)
    }
    func testYearsStripOpensThatDay() throws {
        continueAfterFailure = false
        let app = launch("home")
        XCTAssertTrue(app.descendants(matching: .any)["diary-years"].waitForExistence(timeout: 25), app.debugDescription)
        let year = app.buttons["diary-year-2025-10-15"]; XCTAssertTrue(year.exists)
        year.tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
    }

    // MARK: Composer that grows

    func testExpandTypeDoneWritesTheLine() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); app.buttons["diary-write"].tap()
        let field = app.textFields["diary-inline-field"]; XCTAssertTrue(field.waitForExistence(timeout: 15))
        app.buttons["diary-day-write"].tap()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(field.exists, "Grown, the quiet field gives way to the writing surface")
        editor.tap(); editor.typeText("نص يبقى بعد الطيّ")
        capture(app, "B-composer-expanded-L")
        app.buttons["diary-editor-save"].tap()   // 14 Nov: «تمّ» folds the surface and the words become the line
        XCTAssertTrue(app.staticTexts["نص يبقى بعد الطيّ"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.textViews["diary-editor-text"].exists)
    }
    func testExpandSendCommitsLikeTheQuietField() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); app.buttons["diary-write"].tap()
        XCTAssertTrue(app.textFields["diary-inline-field"].waitForExistence(timeout: 15))
        app.buttons["diary-day-write"].tap()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("سطر من الورقة الكبيرة")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["سطر من الورقة الكبيرة"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.textFields["diary-inline-field"].waitForExistence(timeout: 10), "The composer is folded again after sending")
        XCTAssertEqual((app.textFields["diary-inline-field"].value as? String) ?? "", "اكتب ما تيسّر…", "The field is empty after the commit")
    }
    func testNotesWriteRouteOpensTodayWithTheComposerGrown() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25))
        app.open(URL(string: "madar://notes/write")!)
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 15), app.debugDescription)
    }
}
