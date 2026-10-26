import XCTest
@MainActor final class QuranPlanSetupUITests:XCTestCase {
    func testCustomStartingAyahSurvivesSwitchingStartModes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        let streak = app.buttons["quran-streak"]
        XCTAssertTrue(streak.waitForExistence(timeout: 25), app.debugDescription); streak.tap()
        let edit = app.buttons["quran-plan-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription)
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: edit)
        waitForExpectations(timeout: 15)
        edit.tap()

        let custom = app.buttons["quran-setup-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10), app.debugDescription); custom.tap()
        let ayahPicker = app.descendants(matching: .any)["quran-setup-ayah"]
        XCTAssertTrue(ayahPicker.waitForExistence(timeout: 5), app.debugDescription); ayahPicker.tap()
        let seventhAyah = app.buttons["الفَاتِحة ٧"].firstMatch
        XCTAssertTrue(seventhAyah.waitForExistence(timeout: 5), app.debugDescription); seventhAyah.tap()
        capture(app, "M2-V13-custom-ayah-before-toggle-L")

        app.buttons["quran-setup-continue"].tap()
        custom.tap()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: custom)
        waitForExpectations(timeout: 5)
        capture(app, "M2-V13-custom-ayah-after-toggle-L")
        for _ in 0..<4 { app.buttons["quran-setup-next"].tap() }
        let selectedStart = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "الفَاتِحة ٧")).firstMatch
        XCTAssertTrue(selectedStart.waitForExistence(timeout: 5), "Switching start modes must retain the chosen custom ayah.\n\(app.debugDescription)")
        capture(app, "M2-V13-start-mode-toggle-summary-L")
    }

    func testFourStepsSummarySaveNewVersionAndRetainHistory() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.buttons["quran-streak"].waitForExistence(timeout:25));app.buttons["quran-streak"].tap()
        let edit = app.buttons["quran-plan-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout:10))
        // The plan remains disabled while the launch's queued write finishes.
        // XCUITest can call it hittable before it is enabled; that tap never reaches the action.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: edit)
        waitForExpectations(timeout: 15)
        capture(app,"M2-V12-before-edit-L")
        edit.tap()
        XCTAssertTrue(app.buttons["quran-setup-continue"].waitForExistence(timeout:10),app.debugDescription);capture(app,"M2-V13-start-L")
        app.buttons["quran-setup-custom"].tap()
        XCTAssertTrue(app.steppers["quran-setup-page"].waitForExistence(timeout:5));app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-unit-quarter"].tap();capture(app,"M2-V13-amount-L");app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-rhythm-light"].tap();app.buttons["quran-setup-next"].tap()
        app.buttons["quran-setup-rest-none"].tap();app.buttons["quran-setup-next"].tap();capture(app,"M2-V13-summary-L")
        app.buttons["quran-setup-next"].tap();XCTAssertTrue(app.buttons["quran-plan-edit"].waitForExistence(timeout:10))
        for _ in 0..<5 { if app.staticTexts["quran-plan-version"].isHittable { break };app.swipeUp() }
        XCTAssertTrue(app.staticTexts["quran-plan-version"].label.contains("٢"))
        for _ in 0..<6 { if app.buttons["quran-screen-close"].isHittable { break };app.swipeDown() }
        app.buttons["quran-screen-close"].tap();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["quran-coverage-title"].label.contains("١٤"))
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
