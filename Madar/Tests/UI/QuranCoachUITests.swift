import XCTest

@MainActor final class QuranCoachUITests: XCTestCase {
    func testCoachRepetitionResumeMethodsAndDiscardAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["quran-begin"].tap()
        let advance = app.buttons["quran-session-advance"]
        XCTAssertTrue(advance.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(advance.label, "ابدأ الورد")
        advance.tap()
        waitLabel(advance, contains: "٠ من ٥")
        advance.tap()
        waitLabel(advance, contains: "١ من ٥")
        attach(app, "M2-V02-hifz-L")
        app.buttons["quran-session-full-page"].tap()
        XCTAssertTrue(app.buttons["quran-session-show-tools"].waitForExistence(timeout: 5))
        attach(app, "M2-V02-full-page-L")
        app.buttons["quran-session-show-tools"].tap()
        waitLabel(advance, contains: "١ من ٥")
        app.terminate(); app.launch()
        let resume = app.buttons["quran-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20)); resume.tap()
        waitLabel(advance, contains: "١ من ٥")
        app.buttons["quran-session-hint"].tap()
        let method = app.buttons["quran-session-method"]
        // The hint is saved before the controls take taps again.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: method); waitForExpectations(timeout: 10)
        method.tap()
        XCTAssertTrue(app.buttons["quran-method-completeAyah"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-method-voice"].exists)
        attach(app, "M2-V02-methods-L")
        app.buttons["quran-method-completeAyah"].tap()
        waitLabel(advance, contains: "سمّعتها")
        app.buttons["quran-session-close"].tap()
        XCTAssertTrue(app.buttons["quran-session-discard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quran-session-discard-explanation"].exists)
        attach(app, "M2-V02-exit-L")
        app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quran-resume"].exists)
        app.terminate()
    }
    private func waitLabel(_ element: XCUIElement, contains text: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 12), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
