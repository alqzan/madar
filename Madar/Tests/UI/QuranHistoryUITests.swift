import XCTest
@MainActor final class QuranHistoryUITests: XCTestCase {
    func testHistoryDeepLinkOpensExactSessionWithGradeAndMistake() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "historyRoute"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-history-coverage"].waitForExistence(timeout: 25))
        let firstTarget = app.descendants(matching: .any)["quran-history-route-target-11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(firstTarget.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quran-history-grade-mastered"].waitForExistence(timeout: 5))
        let mistake = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "quran-history-mistake-")).firstMatch
        for _ in 0..<5 where !mistake.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(mistake.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(mistake.isHittable, app.debugDescription)
        app.open(URL(string: "madar://quran/history/22222222-2222-4222-8222-222222222222")!)
        XCTAssertTrue(app.descendants(matching: .any)["quran-history-route-target-22222222-2222-4222-8222-222222222222"].waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["quran-screen-close"].tap()
        let week = app.buttons["quran-week-open"]
        for _ in 0..<6 where !week.isHittable { app.swipeUp() }
        XCTAssertTrue(week.isHittable, app.debugDescription); week.tap()
        let weekTab = app.buttons["quran-log-week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(weekTab.isSelected, "A later ordinary «الأسبوع» open must not reuse the routed session tab.")
    }

    func testHistoryRouteReadFailureCanRetry() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "historyRoute",
            "MADAR_UI_QURAN_SESSION_LOG_READ_FAILURE_ONCE": "1"]
        app.launch()
        let retry = app.buttons["quran-history-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 25), app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-history-route-target-11111111-1111-4111-8111-111111111111"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()
    }

    func testEditGradeDeleteAndUndoKeepSession() throws {
        continueAfterFailure = false
        let app=XCUIApplication(); app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch(); XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<4 { if app.buttons["quran-week-open"].isHittable { break };app.swipeUp() }
        app.buttons["quran-week-open"].tap();app.buttons["quran-log-sessions"].tap()
        XCTAssertTrue(app.staticTexts["quran-history-coverage"].waitForExistence(timeout:10))
        app.buttons["quran-history-filter-hifz"].tap()
        let row=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","quran-history-record-")).firstMatch
        let id=row.identifier;row.tap();capture(app,"M2-V11-history-L")
        func selectGrade(_ id: String) {
            let choice = app.buttons["quran-history-grade-" + id]
            choice.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: choice)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
            for other in ["mastered", "good", "needs"] where other != id {
                XCTAssertFalse(app.buttons["quran-history-grade-" + other].isSelected)
            }
        }
        selectGrade("good")
        XCTAssertFalse(app.staticTexts["quran-history-warning"].exists)
        capture(app, "OR-17-history-good-L")
        selectGrade("needs")
        XCTAssertTrue(app.staticTexts["quran-history-warning"].waitForExistence(timeout:5));capture(app,"M2-V11-grade-L")
        selectGrade("mastered")
        XCTAssertTrue(app.staticTexts["quran-history-warning"].waitForNonExistence(timeout: 5))
        capture(app, "OR-17-history-mastered-L")
        app.buttons["quran-history-delete"].tap();app.alerts.buttons["احذف"].tap()
        XCTAssertTrue(app.buttons[id].waitForNonExistence(timeout:8))
        app.otherElements["quran-history-undo"].buttons["undo-button"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout:8));capture(app,"M2-V11-restored-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
}
