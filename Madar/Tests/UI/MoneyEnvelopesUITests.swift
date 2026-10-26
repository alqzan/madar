import XCTest

@MainActor final class MoneyEnvelopesUITests: XCTestCase {
    func make(_ fixture: String = "showcase") -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); return app
    }
    func open(_ app: XCUIApplication) {
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap(); let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelopes"].waitForExistence(timeout: 10))
    }
    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testReservePreviewTargetUndoAndRelaunch() throws {
        continueAfterFailure = false; let app = make(); open(app)
        XCTAssertTrue(app.staticTexts["money-reserve-dailies"].label.contains("٢٥٠"), app.staticTexts["money-reserve-dailies"].label)
        XCTAssertTrue(app.staticTexts["money-reserve-coverage"].label.contains("١٩١"), app.staticTexts["money-reserve-coverage"].label)
        shot(app, "M5-V03-envelopes-L")
        app.buttons["money-reserve-preview-5000000"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-after"].firstMatch.label.contains("٥٠٬٠٠٠"))
        XCTAssertTrue(app.staticTexts["money-envelope-reserve"].label.contains("١٠٠٬٠٠٠"))
        XCTAssertTrue(app.staticTexts["money-reserve-coverage"].label.contains("٩٥"))
        shot(app, "M5-V03-preview-L")
        app.buttons["money-reserve-mode-goal"].tap()
        let input = app.textFields["money-reserve-target-input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("200000")
        app.buttons["money-reserve-target-save"].tap(); XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-target"].firstMatch.label.contains("٢٠٠٬٠٠٠"))
        shot(app, "M5-V03-target-L")
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-reserve-target"].firstMatch.waitForNonExistence(timeout: 10))
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow); shot(app, "M5-V03-envelopes-s1-L")
        app.terminate(); app.launch(); open(app)
        XCTAssertFalse(app.descendants(matching: .any)["money-reserve-after"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["money-reserve-target"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["money-envelope-reserve"].label.contains("١٠٠٬٠٠٠"))
    }
    func testHiddenReserveDoesNotLeakDailiesOrCoverage() throws {
        continueAfterFailure = false; let app = make("hidden"); open(app)
        XCTAssertEqual(app.staticTexts["money-envelope-reserve"].label, "•••")
        XCTAssertFalse(app.staticTexts["money-reserve-dailies"].exists)
        XCTAssertFalse(app.staticTexts["money-reserve-coverage"].exists)
        shot(app, "M5-V03-hidden-L")
        app.buttons["money-envelopes-reveal"].tap()
        XCTAssertTrue(app.staticTexts["money-reserve-dailies"].label.contains("٢٥٠"))
    }
    func testHiddenSavedReserveGoalNeedsRevealInSheet() throws {
        continueAfterFailure = false; let app = make("hidden"); open(app)
        app.buttons["money-envelopes-reveal"].tap()
        app.buttons["money-reserve-mode-goal"].tap()
        let input = app.textFields["money-reserve-target-input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("200000")
        app.buttons["money-reserve-target-save"].tap(); XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        app.terminate(); app.launch(); open(app)
        XCTAssertEqual(app.staticTexts["money-envelope-reserve"].label, "•••")
        app.buttons["money-reserve-mode-goal"].tap()
        let reveal = app.buttons["money-reserve-target-reveal"]; XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(input.exists); XCTAssertFalse(app.buttons["money-reserve-target-save"].exists)
        shot(app, "M5-V03-target-hidden-L")
        reveal.tap(); XCTAssertTrue(input.waitForExistence(timeout: 5))
        let value = input.value as? String ?? ""
        XCTAssertTrue(value.contains("٢٠٠") || value.contains("200"), value)
    }

}
