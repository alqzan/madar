import XCTest

@MainActor final class QuranDayCloseUITests: XCTestCase {
    func testFullSessionCommitOpensDayCloseWithoutDuplicatingTheSession() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "dayCloseStart"]
        app.launch()
        let begin = app.buttons["quran-begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 20)); begin.tap()
        XCTAssertTrue(app.buttons["quran-session-method"].waitForExistence(timeout: 15))
        app.buttons["quran-session-method"].tap()
        app.buttons["quran-method-completeAyah"].tap()
        let advance = app.buttons["quran-session-advance"]
        for _ in 0..<7 {
            waitLabel(advance, "سمّعتها"); advance.tap()
        }
        waitLabel(advance, "سمّعت الورد"); advance.tap()
        XCTAssertTrue(app.buttons["quran-coach-grade-mastered"].waitForExistence(timeout: 10))
        let save = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", "سجّل"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [save], timeout: 10), .completed)
        advance.tap()
        XCTAssertTrue(app.staticTexts["quran-day-close-title"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(plain(app.staticTexts["quran-day-close-coverage"].label), "٠ أوجه ← وجه واحد")
        attach(app, "M2-V05-first-session-L")
        app.buttons["quran-day-close-home"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        openSummary(app)
        XCTAssertEqual(plain(app.staticTexts["quran-day-close-coverage"].label), "٠ أوجه ← وجه واحد")
        XCTAssertFalse(app.buttons["quran-resume"].exists)
        app.terminate()
    }
    func testDayCloseCoverageStrengthTomorrowAndReopenAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "dayClose"]
        app.launch()
        openSummary(app)
        XCTAssertEqual(app.staticTexts["quran-day-close-title"].label, "أتممت يومك")
        XCTAssertEqual(plain(app.staticTexts["quran-day-close-coverage"].label), "٢٨٤ وجهًا ← ٢٨٥ وجهًا")
        XCTAssertTrue(app.staticTexts["quran-day-close-tomorrow"].label.contains("يوم راحة، مراجعة فقط"))
        attach(app, "M2-V05-day-close-L")
        app.swipeUp()
        attach(app, "M2-V05-day-close-scrolled-L")
        app.buttons["المتانة قبل وبعد، على أي أساس"].tap()
        XCTAssertTrue(app.staticTexts["quran-day-close-strength"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quran-day-close-strength"].label.contains("٪"))
        app.buttons["تمّ"].tap()
        let home = app.buttons["quran-day-close-home"]
        XCTAssertTrue(home.isHittable, app.debugDescription); home.tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        openSummary(app)
        XCTAssertEqual(plain(app.staticTexts["quran-day-close-coverage"].label), "٢٨٤ وجهًا ← ٢٨٥ وجهًا")
        app.buttons["quran-day-close-back"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        app.terminate()
    }
    func testKhatmaMomentAppearsWhenTheFinalAyahCompletesMemorisation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "khatmaStart"]
        app.launch()
        let begin = app.buttons["quran-begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 20), app.debugDescription); begin.tap()
        XCTAssertTrue(app.buttons["quran-session-method"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["quran-session-method"].tap()
        app.buttons["quran-method-completeAyah"].tap()
        let advance = app.buttons["quran-session-advance"]
        let grade = app.buttons["quran-coach-grade-mastered"]
        for _ in 0..<12 {
            if grade.waitForExistence(timeout: 1) { break }
            XCTAssertTrue(advance.waitForExistence(timeout: 5), app.debugDescription)
            advance.tap()
        }
        XCTAssertTrue(grade.waitForExistence(timeout: 8), app.debugDescription)
        grade.tap()
        let save = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", "سجّل"), object: advance)
        XCTAssertEqual(XCTWaiter.wait(for: [save], timeout: 10), .completed, app.debugDescription)
        advance.tap()
        let message = app.staticTexts["quran-khatma-moment-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(message.label.contains("تقبّل الله منك"), message.label)
        XCTAssertTrue(app.buttons["quran-khatma-moment-dismiss"].exists, app.debugDescription)
        attach(app, "M7-khatma-quiet-sheet-L")
        app.buttons["quran-khatma-moment-dismiss"].tap()
        XCTAssertTrue(app.staticTexts["quran-day-close-title"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func openSummary(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20))
        let entry = app.buttons["quran-day-close-open"]
        for _ in 0..<3 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable, app.debugDescription); entry.tap()
        XCTAssertTrue(app.staticTexts["quran-day-close-title"].waitForExistence(timeout: 15))
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func waitLabel(_ element: XCUIElement, _ text: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, element.label)
    }
    // Foundation inserts directional isolates around String Catalog substitutions.
    private func plain(_ value: String) -> String { String(value.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }) }
}
