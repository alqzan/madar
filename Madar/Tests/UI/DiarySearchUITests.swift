import XCTest
@MainActor final class DiarySearchUITests:XCTestCase {
    func testSearchReplacesOldResultsWhenQueryChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-search"].waitForExistence(timeout: 25)); app.buttons["diary-search"].tap()
        let field = app.textFields["diary-search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("#سفر\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'diary-search-result-'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["مسح البحث"].tap(); field.tap(); field.typeText("كلمةغيرموجودة\n")
        XCTAssertTrue(app.staticTexts["diary-search-empty"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(result.exists, "The previous query's results must not remain visible")
        app.buttons["مسح البحث"].tap(); field.tap(); field.typeText("#سفر\n")
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
    }
    func testSearchIndexReadFailureCanRetry() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00","MADAR_UI_DIARY_SEARCH_READ_FAILURE_ONCE":"1"]
        app.launch();XCTAssertTrue(app.buttons["diary-search"].waitForExistence(timeout:25));app.buttons["diary-search"].tap()
        XCTAssertTrue(app.staticTexts["diary-search-read-error"].waitForExistence(timeout:10),app.debugDescription)
        app.buttons["diary-search-retry"].tap()
        XCTAssertTrue(app.staticTexts["فهرس الكتاب"].waitForExistence(timeout:10),app.debugDescription)
    }
    func testChipsOpenSourceEditRemoveAndNoResults() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-search"].waitForExistence(timeout:25));app.buttons["diary-search"].tap()
        let field=app.textFields["diary-search-query"];XCTAssertTrue(field.waitForExistence(timeout:10));capture(app,"M3-V08-search-L")
        field.tap();field.typeText("#سفر\n")
        XCTAssertTrue(app.buttons["diary-search-edit-#سفر"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'diary-search-result-'" )).firstMatch.waitForExistence(timeout:5));capture(app,"M3-V08-tag-results-L")
        app.buttons["مسح البحث"].tap()
        field.tap();field.typeText("ماذا كتبت العام الماضي؟\n")
        XCTAssertTrue(app.buttons["diary-search-edit-العام الماضي"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'diary-search-result-'")).firstMatch.waitForExistence(timeout:5));capture(app,"M3-V08-results-L")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'diary-search-result-'")).firstMatch.tap();XCTAssertTrue(app.buttons["diary-day-write"].waitForExistence(timeout:5));app.buttons["diary-day-close"].tap()
        app.buttons["diary-search-edit-العام الماضي"].tap();let edit=app.alerts.textFields.firstMatch;XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap();edit.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:30)+"2024");app.alerts.buttons["تطبيق"].tap()
        XCTAssertTrue(app.buttons["diary-search-remove-2024"].waitForExistence(timeout:5), app.debugDescription);app.buttons["diary-search-remove-2024"].tap()
        app.buttons["مسح البحث"].tap();field.tap();field.typeText("ما معنى حياتي؟\n");XCTAssertTrue(app.staticTexts["diary-search-empty"].waitForExistence(timeout:5));capture(app,"M3-V08-empty-L")
        app.buttons["diary-search-restart"].tap()
        XCTAssertEqual(field.value as? String, "ابحث في مذكراتك: كلمة، أو تاريخ")
        field.typeText("العام الماضي\n")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'diary-search-result-'")).firstMatch.waitForExistence(timeout:5))
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
