import XCTest

@MainActor final class QuranOutsideUITests: XCTestCase {
    func testLiveWidgetTemplatesReminderSaveRelaunchResetAndUndoAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); open(app)
        attach(app, "M2-V07-widgets-L")
        let choice = app.buttons["quran-reminder-choice"]
        for _ in 0..<3 { if choice.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(choice.isHittable); choice.tap(); app.buttons["quran-reminder-afterIsha"].tap()
        wait(choice, "بعد العشاء")
        attach(app, "M2-V07-reminders-L")
        app.terminate(); app.launch(); open(app)
        for _ in 0..<3 { if choice.isHittable { break }; app.swipeUp() }
        wait(choice, "بعد العشاء")
        app.buttons["quran-reminder-reset"].tap(); wait(choice, "بعد الفجر")
        app.descendants(matching: .any)["quran-reminder-undo"].buttons["تراجع"].tap(); wait(choice, "بعد العشاء")
        app.terminate()
    }
    func testReviewControlRouteStartsDurableTimerAndCanDiscard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/session/review"]
        app.launch()
        let method = app.buttons["quran-session-method"]
        XCTAssertTrue(method.waitForExistence(timeout: 25), app.debugDescription); method.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-review-timer"].waitForExistence(timeout: 5))
        attach(app, "M2-V07-review-timer-L")
        app.buttons["quran-method-done"].tap()
        app.buttons["quran-session-close"].tap()
        app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        app.terminate()
    }
    func testOutsideReadFailureOffersRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_OUTSIDE_READ_FAILURE_ONCE": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-outside"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.staticTexts["quran-outside-read-error"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["quran-widget-preview-coverage"].exists)
        app.buttons["quran-outside-retry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-widget-preview-coverage"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testFihrisDeepLinkOpensTheIndex() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/fihris"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["quran-index-screen"].waitForExistence(timeout: 25), app.debugDescription)
    }
    func testFihrisDeepLinkCanRetryAfterTheFirstReadFails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/fihris", "MADAR_UI_QURAN_ROUTE_READ_FAILURE_ONCE": "1"]
        app.launch()
        let retry = app.alerts.buttons["حاول مرة أخرى"]
        XCTAssertTrue(retry.waitForExistence(timeout: 25), app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-index-screen"].waitForExistence(timeout: 25), app.debugDescription)
    }
    func testJuzDeepLinkSelectsThatPartInTheIndex() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/juz/30"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-index-selected-item-30"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["افتح في المصحف"].exists, app.debugDescription)
        app.buttons["تمّ"].tap()
        app.open(URL(string: "madar://quran/fihris")!)
        XCTAssertTrue(app.buttons["quran-index-unit-surah"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-index-unit-surah"].isSelected)
        app.open(URL(string: "madar://quran/juz/5")!)
        XCTAssertTrue(app.staticTexts["quran-index-selected-item-5"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["تمّ"].tap()
        app.buttons["quran-screen-close"].tap()
        let index = app.buttons["quran-tool-index"]
        for _ in 0..<6 where !index.isHittable { app.swipeUp() }
        XCTAssertTrue(index.isHittable, app.debugDescription); index.tap()
        let surahUnit = app.buttons["quran-index-unit-surah"]
        XCTAssertTrue(surahUnit.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(surahUnit.isSelected, "The ordinary index must reopen on Surah after dismissing a routed Juz.")
    }
    func testQuranRootLinkClosesTheOpenIndexAndReturnsHome() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/fihris"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-index-unit-surah"].waitForExistence(timeout: 30), app.debugDescription)
        app.open(URL(string: "madar://quran")!)
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-index-unit-surah"].exists, app.debugDescription)
    }
    func testQuranRootLinkClosesTheOpenPlanAndReturnsHome() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_PLAN_ROOT_ROUTE_HARNESS": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["quran-streak"].tap()
        let edit = app.buttons["quran-plan-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15), app.debugDescription)
        let route = app.buttons["quran-plan-root-route"]
        XCTAssertTrue(route.waitForExistence(timeout: 8), app.debugDescription)
        route.tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(edit.exists, "The Quran root link must dismiss the replaceable plan presentation.")
        app.terminate()
    }
    func testPageLinkReplacesTheOpenIndexAfterItDismisses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/fihris"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["quran-index-screen"].waitForExistence(timeout: 30), app.debugDescription)

        app.open(URL(string: "madar://quran/page/2")!)

        let page = app.descendants(matching: .any)["quran-mushaf-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["quran-index-screen"].exists, app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["quran-mushaf-number"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["quran-mushaf-number"].label, "الوجه ٢")
        app.buttons["quran-mushaf-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    func testLatestQuranLinkWinsWhenAnotherPresentationIsDismissing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_ROUTE": "madar://quran/fihris", "MADAR_UI_QURAN_ROUTE_DISMISS_HOLD_MS": "5000"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["quran-index-screen"].waitForExistence(timeout: 30), app.debugDescription)

        app.open(URL(string: "madar://quran/page/2")!)
        app.open(URL(string: "madar://quran/juz/30")!)

        XCTAssertTrue(app.staticTexts["quran-index-selected-item-30"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["quran-mushaf-page"].exists, app.debugDescription)
        app.terminate()
    }
    func testQuranPageLinkWaitsForPlanSetupToClose() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_ROUTE_SETUP_HARNESS": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["quran-streak"].tap()
        let edit = app.buttons["quran-plan-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 12), app.debugDescription)
        let editReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: edit)
        XCTAssertEqual(XCTWaiter.wait(for: [editReady], timeout: 15), .completed, app.debugDescription)
        edit.tap()
        let custom = app.buttons["quran-setup-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10), app.debugDescription); custom.tap()

        app.buttons["ui-test-open-quran-page-from-setup"].tap()
        XCTAssertTrue(app.staticTexts["quran-setup-title"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["quran-mushaf-page"].exists, app.debugDescription)

        let closeSetup = app.buttons.matching(identifier: "quran-screen-close").firstMatch
        XCTAssertTrue(closeSetup.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(closeSetup.isHittable, app.debugDescription); closeSetup.tap()
        let page = app.descendants(matching: .any)["quran-mushaf-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-plan-edit"].exists, "After setup closes, the queued page link replaces the plan cover.")
        let pageNumber = app.staticTexts.matching(identifier: "quran-mushaf-page")
            .matching(NSPredicate(format: "label == %@", "٢")).firstMatch
        XCTAssertTrue(pageNumber.exists, app.debugDescription)
        app.terminate()
    }
    func testQuranSaveFailureStaysVisibleBeforeQueuedPageLinkOpens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_LEVEL_WRITE_HOLD_MS": "5000", "MADAR_UI_QURAN_LEVEL_WRITE_FAIL_ONCE": "1",
            "MADAR_UI_QURAN_ROUTE_FAILURE_HARNESS": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25), app.debugDescription)
        let level = app.buttons["quran-level-hifz-simple"]
        XCTAssertTrue(level.waitForExistence(timeout: 8), app.debugDescription)
        let levelReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: level)
        XCTAssertEqual(XCTWaiter.wait(for: [levelReady], timeout: 10), .completed, app.debugDescription)
        level.tap()
        let levelLocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: level)
        XCTAssertEqual(XCTWaiter.wait(for: [levelLocked], timeout: 5), .completed, app.debugDescription)
        let route = app.buttons["ui-test-quran-page-route-during-save"]
        XCTAssertTrue(route.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(route.isHittable, app.debugDescription); route.tap()
        let refresh = app.buttons["ui-test-quran-refresh-during-save"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(refresh.isHittable, app.debugDescription); refresh.tap()

        let error = app.alerts["تعذّر إتمام العملية"]
        XCTAssertTrue(error.waitForExistence(timeout: 15), app.debugDescription)
        let message = error.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "تعذّر حفظ مستوى الورد")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["quran-mushaf-page"].exists, app.debugDescription)
        error.buttons["تمّ"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-mushaf-page"].waitForExistence(timeout: 20), app.debugDescription)
        let pageNumber = app.staticTexts.matching(identifier: "quran-mushaf-page")
            .matching(NSPredicate(format: "label == %@", "٢")).firstMatch
        XCTAssertTrue(pageNumber.exists, app.debugDescription)
        app.terminate()
    }
    func testQuranRouteArrivingDuringBusyOperationRunsAfterward() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_RUN_HOLD_MS": "2000"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25), app.debugDescription)
        app.open(URL(string: "madar://quran/fihris")!)
        app.open(URL(string: "madar://quran/juz/30")!)
        XCTAssertTrue(app.staticTexts["quran-index-selected-item-30"].waitForExistence(timeout: 25), app.debugDescription)
        app.terminate()
    }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        let entry = app.buttons["quran-outside"]
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-widget-preview-coverage"].waitForExistence(timeout: 10))
    }
    private func wait(_ item: XCUIElement, _ label: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", label), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
