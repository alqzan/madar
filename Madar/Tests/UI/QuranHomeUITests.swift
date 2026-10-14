import XCTest

@MainActor final class QuranHomeUITests: XCTestCase {
    func testHomeLevelsDetailsAndDraftResumeAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), store = UUID().uuidString
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        let coverageLabel = app.staticTexts["quran-coverage-label"]
        let hadith = app.buttons["quran-coverage-hadith"]
        XCTAssertLessThan(hadith.frame.maxY, coverageLabel.frame.minY)
        let countFrame = app.staticTexts["quran-coverage-title"].frame
        XCTAssertGreaterThan(countFrame.minY, coverageLabel.frame.maxY)
        XCTAssertLessThanOrEqual(countFrame.minY - coverageLabel.frame.maxY, 7)
        XCTAssertTrue(hadith.label.contains("يُقال لصاحب القرآن"))
        XCTAssertTrue(hadith.label.contains("فإن منزلك عند آخر آية تقرؤها"))
        attach(app, "M2-V01-home-L")
        app.swipeUp()
        XCTAssertTrue(app.otherElements["quran-log14"].exists)
        attach(app, "M2-V01-home-scrolled-L")
        app.swipeDown()
        let coverageBeforeHadith = app.staticTexts["quran-coverage-title"].label
        app.buttons["quran-coverage-hadith"].tap()
        XCTAssertTrue(app.staticTexts["quran-hadith-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quran-hadith-text"].label.contains("فإن منزلك عند آخر آية تقرؤها"))
        XCTAssertTrue(app.staticTexts["quran-hadith-source"].label.contains("١٤٦٤"))
        attach(app, "M2-V01-hadith-L")
        app.buttons["quran-hadith-close"].tap()
        XCTAssertEqual(app.staticTexts["quran-coverage-title"].label, coverageBeforeHadith)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        app.buttons["quran-step-hifz"].tap()
        XCTAssertTrue(app.buttons["تمّ"].waitForExistence(timeout: 5)); app.buttons["تمّ"].tap()
        let deep = app.buttons["quran-level-hifz-deep"]; deep.tap()
        waitSelected(app.buttons["quran-level-hifz-deep"])
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-level-hifz-deep"].waitForExistence(timeout: 20)); waitSelected(app.buttons["quran-level-hifz-deep"])
        app.buttons["quran-level-hifz-medium"].tap()
        app.buttons["quran-begin"].tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        let resume = app.buttons["quran-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), app.debugDescription); resume.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15))
        app.terminate()
    }
    private func waitSelected(_ button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "محدد"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
