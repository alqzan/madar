import XCTest
@MainActor final class QuranFreeUITests:XCTestCase {
    func testSelectFreeRangeEnterOriginalPageAndDiscard() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 { if app.buttons["quran-tool-free"].isHittable { break };app.swipeUp() };app.buttons["quran-tool-free"].tap()
        XCTAssertTrue(app.buttons["quran-free-start"].waitForExistence(timeout:10));capture(app,"M2-V14-free-L")
        app.buttons["quran-free-start"].tap();XCTAssertTrue(app.buttons["quran-session-method"].waitForExistence(timeout:15));capture(app,"M2-V14-session-L")
        app.buttons["quran-session-close"].tap();app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(app.buttons["quran-free-start"].waitForExistence(timeout:10))
    }
    func testSurahChoiceSurvivesSlowIndexAndStartRetry() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home","MADAR_UI_QURAN_INDEX_DELAY_ONCE":"1","MADAR_UI_QURAN_FREE_START_FAILURE_ONCE":"1"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 { if app.buttons["quran-tool-free"].isHittable { break };app.swipeUp() };app.buttons["quran-tool-free"].tap()
        let last=app.buttons["quran-free-preset-last"]
        XCTAssertTrue(last.waitForExistence(timeout:10));last.tap()
        let lastAction=app.buttons["quran-free-preset-action-last"]
        XCTAssertTrue(lastAction.waitForExistence(timeout:5));lastAction.tap()
        let surahPreset=app.buttons["quran-free-preset-surah"]
        XCTAssertTrue(surahPreset.waitForExistence(timeout:10));surahPreset.tap()
        let baqarah=app.buttons["quran-free-surah-2"]
        XCTAssertTrue(baqarah.waitForExistence(timeout:5));baqarah.tap()
        let summary=app.staticTexts["quran-free-range-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout:5));XCTAssertTrue(summary.label.contains("٢ إلى ٤٩"),summary.label)

        let start=app.buttons["quran-free-start"]
        XCTAssertTrue(start.waitForExistence(timeout:5))
        let ready=NSPredicate(format:"isEnabled == true")
        expectation(for:ready,evaluatedWith:start);waitForExpectations(timeout:12)
        XCTAssertTrue(summary.label.contains("٢ إلى ٤٩"),"Index completion overwrote the chosen surah: \(summary.label)")
        start.tap()
        let error=app.staticTexts["quran-free-error"]
        XCTAssertTrue(error.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(summary.label.contains("٢ إلى ٤٩"),"A failed start lost the chosen surah: \(summary.label)")
        start.tap()
        XCTAssertTrue(app.buttons["quran-session-method"].waitForExistence(timeout:15),app.debugDescription)
        app.buttons["quran-session-close"].tap();app.buttons["quran-session-discard"].tap()
        XCTAssertTrue(start.waitForExistence(timeout:10))
    }
    func testStrengthSuggestedRangeDoesNotOverrideChoiceWhileIndexLoads() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home","MADAR_UI_QURAN_INDEX_DELAY_ONCE":"1"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 {if app.buttons["quran-tool-strength"].isHittable {break};app.swipeUp()};app.buttons["quran-tool-strength"].tap()
        XCTAssertTrue(app.staticTexts["quran-strength-mean"].waitForExistence(timeout:10))
        for _ in 0..<6 {if app.buttons["quran-strength-review"].isHittable {break};app.swipeUp()};app.buttons["quran-strength-review"].tap()
        let surahPreset=app.buttons["quran-free-preset-surah"]
        XCTAssertTrue(surahPreset.waitForExistence(timeout:10));surahPreset.tap()
        let baqarah=app.buttons["quran-free-surah-2"]
        XCTAssertTrue(baqarah.waitForExistence(timeout:5));baqarah.tap()
        let summary=app.staticTexts["quran-free-range-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout:5));XCTAssertTrue(summary.label.contains("٢ إلى ٤٩"),summary.label)
        capture(app,"M2-V14-free-strength-choice-L")
        let start=app.buttons["quran-free-start"]
        let ready=NSPredicate(format:"isEnabled == true")
        expectation(for:ready,evaluatedWith:start);waitForExpectations(timeout:12)
        XCTAssertTrue(summary.label.contains("٢ إلى ٤٩"),"The initial strength range overwrote the chosen surah: \(summary.label)")
    }
    func testLastFiveFacePresetWaitsForDelayedIndex() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_QURAN_FIXTURE":"home","MADAR_UI_QURAN_INDEX_DELAY_ONCE":"1"]
        app.launch();XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout:25))
        for _ in 0..<5 { if app.buttons["quran-tool-free"].isHittable { break };app.swipeUp() };app.buttons["quran-tool-free"].tap()
        let last=app.buttons["quran-free-preset-last"]
        XCTAssertTrue(last.waitForExistence(timeout:10));last.tap()
        let lastAction=app.buttons["quran-free-preset-action-last"]
        XCTAssertTrue(lastAction.waitForExistence(timeout:5));lastAction.tap()
        let summary=app.staticTexts["quran-free-range-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout:5))
        let start=app.buttons["quran-free-start"]
        let ready=NSPredicate(format:"isEnabled == true")
        expectation(for:ready,evaluatedWith:start);waitForExpectations(timeout:12)
        XCTAssertTrue(summary.label.contains("٢٨٠ إلى ٢٨٤"),"The last-pages preset ran before the page index: \(summary.label)")
    }
    private func capture(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
