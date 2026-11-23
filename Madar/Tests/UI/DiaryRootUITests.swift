import XCTest

/// 14 Nov (T10): the room opens on today's page itself, with the year strip over it, and writing needs no send button.
/// The legacy suites run with the home-first flag; this suite runs the shipping root (`MADAR_UI_DIARY_ROOT=1`).
@MainActor final class DiaryRootUITests: XCTestCase {
    private func launch(_ fixture: String, now: String = "2026-10-15T15:00:00+03:00") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_DIARY_ROOT": "1",
                                 "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": now]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = app.screenshot(), shot = XCTAttachment(screenshot: image)
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if let directory = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"))
        }
    }
    private func openWriter(_ app: XCUIApplication) {
        let control = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["diary-day-write", "diary-inline-expand"])).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), app.debugDescription)
        control.tap()
    }

    func testRoomOpensOnTodaysPageWithNothingPushed() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10), "Today's lines are on the first screen")
        XCTAssertFalse(app.buttons["diary-today"].exists, "No home card to tap before the page")
        XCTAssertFalse(app.staticTexts["diary-home-title"].exists)
        capture(app, "T10-root-today-L")
    }
    func testEmptyPageInvitationClearsTheWritingRule() throws {
        continueAfterFailure = false
        let app = launch("empty")
        let invitation = app.staticTexts["diary-day-empty-invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 25), app.debugDescription)
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5), app.debugDescription)
        let clearance = page.frame.maxX - invitation.frame.maxX
        XCTAssertGreaterThanOrEqual(
            clearance,
            58,
            "The Arabic invitation must begin to the left of the vertical writing rule; clearance was \(clearance) pt."
        )
        capture(app, "OWNER-diary-empty-invitation-L")
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
        // 14 Nov: the memories strip under today's date holds one card per past year on this day.
        let strip = app.buttons["diary-year-2025-10-15"]
        XCTAssertTrue(strip.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-day-more"].exists, "The strip is over today's page, not instead of it")
        capture(app, "T10-root-year-strip-L")
        strip.tap()
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٥"].waitForExistence(timeout: 10), app.debugDescription)
        let todayQuery = app.buttons.matching(identifier: "diary-day-today")
        XCTAssertGreaterThan(todayQuery.count, 0, app.debugDescription)
        let today = todayQuery.element(boundBy: todayQuery.count - 1)
        XCTAssertTrue(today.waitForExistence(timeout: 10), app.debugDescription)
        today.tap()
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testDaysEntryOpensCalendarAndPastDayReturnsToToday() throws {
        continueAfterFailure = false
        let app = launch("home")
        // 14 Nov: on today's page the archive is «كل الذكريات», beside the memories of this day.
        let days = app.buttons["diary-all-memories"]
        XCTAssertTrue(days.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertEqual(days.label, "كل الذكريات", "Past-day browsing is named on the page: \(days.label)")
        capture(app, "OWNER-notes-days-entry-L")
        days.tap()
        // The archive opens on «الأيام»; the calendar is a view chosen from «طريقة العرض».
        let menu = app.buttons["diary-hub-view-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription); menu.tap()
        let calendar = app.buttons["diary-hub-view-calendar"]; XCTAssertTrue(calendar.waitForExistence(timeout: 5), app.debugDescription); calendar.tap()
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["diary-calendar-scale"].tap()
        let past = app.buttons["diary-calendar-day-2026-10-14"]
        XCTAssertTrue(past.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !past.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(past.isHittable, app.debugDescription)
        past.tap()
        XCTAssertTrue(app.staticTexts["١٤ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 15), app.debugDescription)
        let todayQuery = app.buttons.matching(identifier: "diary-day-today")
        XCTAssertGreaterThan(todayQuery.count, 0, app.debugDescription)
        let today = todayQuery.element(boundBy: todayQuery.count - 1)
        XCTAssertTrue(today.waitForExistence(timeout: 10), app.debugDescription)
        today.tap()
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testHistoricalFridayCanReturnToToday() throws {
        continueAfterFailure = false
        let app = launch("entryRoute", now: "2026-10-17T15:00:00+03:00")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://notes/day/2026-10-16")!)
        XCTAssertEqual(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10) ? app.staticTexts["diary-day-title"].label : "", "جمعة مباركة")
        let today = app.buttons["diary-day-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "OWNER-notes-historical-friday-return-before-L")
        today.tap()
        XCTAssertTrue(app.staticTexts["١٧ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(today.waitForNonExistence(timeout: 5), "Back on today, «العودة إلى اليوم» has nowhere to go and leaves")
        capture(app, "OWNER-notes-historical-friday-return-after-L")
    }
    func testRootRouteReturnsFromAnOlderDayToToday() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://notes/day/2026-10-14")!)
        XCTAssertTrue(app.staticTexts["١٤ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        app.open(URL(string: "madar://notes")!)
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 15), app.debugDescription)
    }
    func testReturningToTodayKeepsPastAndTodayDraftsSeparateAcrossRelaunch() throws {
        continueAfterFailure = false
        let store = UUID().uuidString
        func start() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1",
                                     "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
            app.launch(); return app
        }
        func waitForSavedDraft(_ app: XCUIApplication) {
            let status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "المسودة محفوظة")).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        }
        var app = start()
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://notes/day/2026-10-14")!)
        XCTAssertTrue(app.staticTexts["١٤ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        openWriter(app)
        let pastField = app.textViews["diary-editor-text"]
        XCTAssertTrue(pastField.waitForExistence(timeout: 10), app.debugDescription)
        pastField.typeText("مسودة هامش أمس")
        waitForSavedDraft(app)
        app.open(URL(string: "madar://notes")!)
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 15), app.debugDescription)
        openWriter(app)
        let todayField = app.textViews["diary-editor-text"]
        XCTAssertTrue(todayField.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(todayField.value as? String, "", "A past-day margin draft must never appear in today's writer")
        todayField.typeText("مسودة اليوم")
        waitForSavedDraft(app)
        app.open(URL(string: "madar://notes/day/2026-10-14")!)
        XCTAssertTrue(app.staticTexts["١٤ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        openWriter(app)
        let restoredPast = app.textViews["diary-editor-text"]
        XCTAssertTrue(restoredPast.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(restoredPast.value as? String, "مسودة هامش أمس", app.debugDescription)
        let todayQuery = app.buttons.matching(identifier: "diary-day-today")
        XCTAssertGreaterThan(todayQuery.count, 0, app.debugDescription)
        todayQuery.element(boundBy: todayQuery.count - 1).tap()
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        openWriter(app)
        let restoredToday = app.textViews["diary-editor-text"]
        XCTAssertTrue(restoredToday.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(restoredToday.value as? String, "مسودة اليوم", app.debugDescription)
        app.terminate()

        app = start()
        XCTAssertTrue(app.staticTexts["١٥ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 25), app.debugDescription)
        openWriter(app)
        let afterRelaunchToday = app.textViews["diary-editor-text"]
        XCTAssertTrue(afterRelaunchToday.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(afterRelaunchToday.value as? String, "مسودة اليوم", app.debugDescription)
        app.open(URL(string: "madar://notes/day/2026-10-14")!)
        XCTAssertTrue(app.staticTexts["١٤ أكتوبر ٢٠٢٦"].waitForExistence(timeout: 10), app.debugDescription)
        openWriter(app)
        let afterRelaunchPast = app.textViews["diary-editor-text"]
        XCTAssertTrue(afterRelaunchPast.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(afterRelaunchPast.value as? String, "مسودة هامش أمس", app.debugDescription)
    }
    func testWritingQuestionsAreReachableFromTodaysPage() throws {
        continueAfterFailure = false
        let app = launch("entryRoute")
        XCTAssertTrue(app.buttons["diary-day-more"].waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["diary-day-more"].tap()
        let openQuestions = app.buttons["diary-day-questions"]
        XCTAssertTrue(openQuestions.waitForExistence(timeout: 8), app.debugDescription)
        openQuestions.tap()
        XCTAssertTrue(app.descendants(matching: .any)["diary-questions-card"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "OWNER-notes-questions-from-today-L")
        app.buttons["diary-questions-aboutDiary"].tap()
        let question = app.buttons["diary-question-0"]
        XCTAssertTrue(question.waitForExistence(timeout: 20), app.debugDescription)
        question.tap()
        XCTAssertTrue(app.staticTexts["diary-day-prompt"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "OWNER-notes-question-on-day-L")
        let field = app.textViews["diary-editor-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap(); field.typeText("أجبت من صفحة اليوم")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["أجبت من صفحة اليوم"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts.matching(identifier: "diary-day-line").matching(NSPredicate(format: "label CONTAINS %@", app.staticTexts["diary-day-prompt"].label)).firstMatch.exists,
                       "The prompt is a guide and must not be saved as diary text")
    }
    func testIntentionReviewAppearsOnTheRootDayPage() throws {
        continueAfterFailure = false
        let app = launch("intentionReview")
        let card = app.descendants(matching: .any)["diary-intention-follow-up"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.staticTexts["مضى أسبوع على نيّتك"].exists)
        let review = app.textFields["diary-intention-review-text"]
        XCTAssertTrue(review.exists, "The due review appears on the current day page itself")
        review.tap(); review.typeText("راجعتها من صفحة اليوم")
        app.buttons["diary-intention-review-save"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 12), app.debugDescription)
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
