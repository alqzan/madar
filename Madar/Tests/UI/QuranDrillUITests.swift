import XCTest

@MainActor final class QuranDrillUITests: XCTestCase {
    /// M2-V04: today's word spot, reveal, answer, then the whole-ayah spot; «أخطائي» keeps the §7.4 order.
    func testDrillRevealAnswerNextSpotAndTabsAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "drill"]
        app.launch()
        let step = app.buttons["quran-step-drill"]
        XCTAssertTrue(step.waitForExistence(timeout: 20), app.debugDescription)
        step.tap()
        let start = app.buttons["quran-drill-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), app.debugDescription); start.tap()
        let reveal = app.buttons["quran-drill-reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 15), app.debugDescription)
        let title = app.staticTexts["quran-drill-title"]
        XCTAssertTrue(title.label.hasSuffix("١١٤، الوجه ١٤٢"), title.label)
        XCTAssertTrue(app.staticTexts["تعثّرت هنا مرتين"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["quran-drill-ayah"].label, "الكلمة مستورة")
        attach(app, "M2-V04-drill-L")
        reveal.tap()
        let pass = app.buttons["quran-drill-pass"]
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        attach(app, "M2-V04-revealed-L")
        pass.tap()
        // The next spot of today's tab is the whole ayah, hidden whole.
        let next = NSPredicate(format: "label == %@", "الآية مستورة")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: next, object: app.descendants(matching: .any)["quran-drill-ayah"])], timeout: 15), .completed, app.debugDescription)
        attach(app, "M2-V04-whole-ayah-L")
        app.buttons["quran-drill-tab-mine"].tap()
        let older = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "٢٥٥، الوجه ٤٢"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [older], timeout: 15), .completed, title.label)
        // §7.4 order in «أخطائي»: equal counts, the most recent first, so today's whole ayah leads the older spot.
        XCTAssertTrue(app.buttons["quran-drill-tab-mine"].isSelected)
        attach(app, "M2-V04-mine-L")
        app.buttons["quran-drill-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quran-resume"].exists, "An unanswered spot leaves no draft")
        app.terminate()
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
