import XCTest
@MainActor final class QuranQiyamUITests:XCTestCase {
    private func launch()->XCUIApplication {let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T23:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"];app.launch();return app}
    func testNightPreviewRakahProgressResumeAndSave() throws {
        continueAfterFailure=false
        let app=launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 {if app.buttons["quran-tool-qiyam"].isHittable {break};app.swipeUp()};capture(app,"M2-V17-home-tools-L");app.buttons["quran-tool-qiyam"].tap()
        XCTAssertTrue(app.buttons["quran-qiyam-start"].waitForExistence(timeout:10));app.buttons["quran-qiyam-rakaat-8"].tap();XCTAssertTrue(app.buttons["quran-qiyam-rakaat-8"].isSelected);Thread.sleep(forTimeInterval:0.4);capture(app,"M2-V17-qiyam-L");app.buttons["quran-qiyam-rakaat-2"].tap()
        app.buttons["quran-qiyam-start"].tap();XCTAssertTrue(app.buttons["quran-qiyam-rakah-done"].waitForExistence(timeout:15));capture(app,"M2-V17-rakah-L")
        app.buttons["quran-qiyam-rakah-done"].tap()
        let secondRakah = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "الركعة ٢ / ٢"), object: app.buttons["quran-qiyam-rakah-done"])
        XCTAssertEqual(XCTWaiter.wait(for: [secondRakah], timeout: 10), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["جلسة من يوم سابق"].exists)
        app.buttons["quran-qiyam-session-close"].tap();XCTAssertTrue(app.buttons["quran-qiyam-keep"].waitForExistence(timeout:5),app.debugDescription);app.buttons["quran-qiyam-keep"].tap()
        app.terminate();app.launch();XCTAssertTrue(app.buttons["quran-resume"].waitForExistence(timeout:25));app.buttons["quran-resume"].tap()
        XCTAssertTrue(app.buttons["quran-qiyam-rakah-done"].waitForExistence(timeout:15));app.buttons["quran-qiyam-rakah-done"].tap()
        XCTAssertTrue(app.buttons["quran-qiyam-save"].waitForExistence(timeout:8));capture(app,"M2-V17-grade-L");app.buttons["quran-qiyam-save"].tap()
        XCTAssertTrue(app.buttons["quran-day-close-home"].waitForExistence(timeout:15))
        app.buttons["quran-day-close-home"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 25))
        app.tabBars.buttons["الصلاة"].tap()
        let prayerNight = app.buttons["prayer-qiyam"]
        for _ in 0..<8 where !prayerNight.isHittable { app.swipeUp() }
        prayerNight.tap()
        let recorded = app.staticTexts["prayer-qiyam-wird-line"]
        XCTAssertTrue(recorded.waitForExistence(timeout: 10))
        XCTAssertTrue(recorded.label.contains("احتُسبت أوجهه من مراجعتك في القرآن"), recorded.label)
        XCTAssertFalse(app.buttons["prayer-quran-qiyam"].exists, "A saved Quran wird must not invite recording the same night again")
        capture(app, "OR-08-prayer-reads-saved-quran-wird-L")
    }
    func testPrayerEntryOpensBuiltQuranNightPreview() throws {
        continueAfterFailure=false
        let app=launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25));app.tabBars.buttons["الصلاة"].tap()
        for _ in 0..<8 {if app.buttons["prayer-qiyam"].isHittable {break};app.swipeUp()};app.buttons["prayer-qiyam"].tap()
        XCTAssertTrue(app.buttons["prayer-quran-qiyam"].waitForExistence(timeout:10))
        // OR-08: the sheet says what tonight's reading gives the wird before it hands over to the Quran room.
        let line=app.staticTexts["prayer-qiyam-wird-line"];XCTAssertTrue(line.exists && (line.label.contains("وردك") || line.label.contains("سجل القرآن")),app.debugDescription);capture(app,"OR-08-qiyam-sheet-L")
        app.buttons["prayer-quran-qiyam"].tap()
        XCTAssertTrue(app.buttons["quran-qiyam-start"].waitForExistence(timeout:15));capture(app,"M2-V17-prayer-link-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
