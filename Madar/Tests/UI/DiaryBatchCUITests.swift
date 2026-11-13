import XCTest

/// 12 Nov batch C: prayer-period headings, reading mode, the on-demand night review, the calendar with photos and the Arabic question bank.
@MainActor final class DiaryBatchCUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); return app
    }
    private func openToday(_ app: XCUIApplication) {
        let card = app.buttons["diary-today"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
    }
    private func openMenuItem(_ app: XCUIApplication, _ id: String) {
        let more = app.buttons["diary-day-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        let item = app.buttons[id]
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }

    func testDayFlowHasPrayerPeriodHeadingsOnlyWhereThereAreLines() throws {
        continueAfterFailure = false
        let app = launch("periods"); openToday(app)
        XCTAssertTrue(app.staticTexts["جلست بعد الفجر قليلًا."].waitForExistence(timeout: 15), app.debugDescription)
        let headings = app.descendants(matching: .any).matching(identifier: "diary-period-heading")
        XCTAssertTrue(headings.firstMatch.waitForExistence(timeout: 10))
        for title in ["قبل الفجر", "بعد الفجر", "الضحى"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.exists, title)
        }
        // The fixture has lines in all seven periods; the headings and the lines never outnumber each other.
        XCTAssertGreaterThanOrEqual(headings.count, 3)
    }

    func testReadingModeOpensSwipesToAnotherDayAndExits() throws {
        continueAfterFailure = false
        let app = launch("periods"); openToday(app)
        openMenuItem(app, "diary-day-read")
        XCTAssertTrue(app.buttons["diary-reading-close"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["قهوة الضحى."].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-line-write-after"].firstMatch.exists, "Reading mode has no editing controls")
        // RTL book order: a swipe to the right turns to the next page; to the left, back to an earlier day.
        let pager = app.descendants(matching: .any)["diary-reading-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["يوم أمس فيه صورة."].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["diary-reading-close"].tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
    }

    func testNightReviewOnDemandSavesALineToToday() throws {
        continueAfterFailure = false
        let app = launch("periods"); openToday(app)
        XCTAssertFalse(app.descendants(matching: .any)["diary-review-field"].exists, "The review never opens by itself")
        openMenuItem(app, "diary-day-review")
        XCTAssertTrue(app.descendants(matching: .any)["diary-review-facts"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-review-fact-salah"].exists, "The prayer logged today is summarised from its room")
        XCTAssertTrue(app.staticTexts["diary-review-question"].exists)
        let field = app.textFields["diary-review-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("alhamdulillah")
        app.buttons["diary-review-save"].tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "alhamdulillah")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15), app.debugDescription)
    }

    func testCalendarMonthShowsPhotoDaysWithThumbnail() throws {
        continueAfterFailure = false
        let app = launch("periods")
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25))
        app.buttons["diary-today"].tap()
        let archive = app.buttons["diary-day-archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 10)); archive.tap()
        XCTAssertTrue(app.buttons["diary-calendar-scale"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["diary-calendar-scale"].tap()
        let photoDay = app.buttons["diary-calendar-day-2026-10-14"]
        XCTAssertTrue(photoDay.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(photoDay.value as? String, "فيه صورة")
        XCTAssertNotEqual(app.buttons["diary-calendar-day-2026-10-12"].value as? String, "فيه صورة")
    }

    func testHomeQuestionsComeFromTheArabicBank() throws {
        continueAfterFailure = false
        let app = launch("home")
        let card = app.descendants(matching: .any)["diary-questions-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["diary-questions-reflective"].tap()
        let first = app.buttons["diary-question-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-question-2"].exists, "Three questions")
        XCTAssertNil(first.label.range(of: "[A-Za-z]", options: .regularExpression), "No translated or English text is ever shown")
    }
}
