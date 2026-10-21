import XCTest

@MainActor final class QuranHomeUITests: XCTestCase {
    func testHomeLevelsDetailsAndDraftResumeAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), store = UUID().uuidString
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        for level in ["simple", "medium", "deep", "max"] {
            let option = app.buttons["quran-level-hifz-" + level]
            XCTAssertFalse(option.label.contains("×"), option.label)
            XCTAssertTrue(option.label.contains("صفح") || option.label.contains("سطر") || option.label.contains("آي"), option.label)
        }
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
        let begin = app.buttons["quran-begin"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: begin)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        begin.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        let resume = app.buttons["quran-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), app.debugDescription)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "M2-improve-resume-L"; capture.lifetime = .keepAlways; add(capture)
        resume.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15))
        app.terminate()
    }
    /// Owner 20 Oct: the day is flexible; a later open step starts directly from its sheet.
    func testLaterStepStartsOutOfOrderFromItsSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-step-hifz"].exists, app.debugDescription)
        let later = app.buttons["quran-step-review"], laterID = later.identifier
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
        if !later.isHittable { app.swipeUp(velocity: .slow) }
        later.tap()
        let start = app.buttons["quran-step-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "\(laterID) " + app.debugDescription)
        XCTAssertEqual(start.label, "ابدأ بها الآن", "review must be a later step than hifz here")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "M2-V01-step-start-L"; shot.lifetime = .keepAlways; add(shot)
        start.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()
    }

    func testFirstUseShowsPlanActionWithoutZeroStreakOrDepthControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), app.debugDescription)
        for title in ["البهو", "الصلاة", "القرآن", "المال", "المحبرة"] {
            XCTAssertTrue(tabBar.buttons[title].waitForExistence(timeout: 5), "Missing native destination: \(title)\n\(app.debugDescription)")
        }
        let notes = app.buttons["tab-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "Notes must stay directly reachable.\n\(app.debugDescription)")
        let tabsShot = XCTAttachment(screenshot: app.screenshot()); tabsShot.name = "M0-native-glass-room-shortcuts-L"; tabsShot.lifetime = .keepAlways; add(tabsShot)
        notes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["notes-tab"].waitForExistence(timeout: 8), app.debugDescription)
        app.tabBars.buttons["المال"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-home"].waitForExistence(timeout: 10), app.debugDescription)
        let moneyShot = XCTAttachment(screenshot: app.screenshot()); moneyShot.name = "M0-native-glass-money-active-L"; moneyShot.lifetime = .keepAlways; add(moneyShot)
        app.tabBars.buttons["المحبرة"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        tabBar.buttons["القرآن"].tap()
        XCTAssertTrue(app.buttons["quran-start-plan"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-streak"].exists)
        XCTAssertFalse(app.buttons["quran-level-hifz-medium"].exists)
        XCTAssertFalse(app.buttons["quran-level-review-medium"].exists)
        attach(app, "UX-09-first-use-L")
        app.buttons["quran-start-plan"].tap()
        XCTAssertTrue(app.staticTexts["quran-setup-title"].waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 { let next = app.buttons["quran-setup-next"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap() }
        XCTAssertTrue(app.buttons["quran-open-plan"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-streak"].exists)
        XCTAssertTrue(app.buttons["quran-level-hifz-medium"].exists)
        attach(app, "UX-09-new-plan-L")
        app.buttons["quran-open-plan"].tap()
        XCTAssertTrue(app.staticTexts["quran-plan-forecast"].waitForExistence(timeout: 10))
    }
    private func waitSelected(_ button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "محدد"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
