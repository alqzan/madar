import XCTest

@MainActor final class HabitsUITests:XCTestCase {
    private func app(_ fixture:String)->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_HABIT_FIXTURE":fixture,"MADAR_UI_NOW":"2026-10-15T20:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"];app.launch();return app
    }
    private func open(_ app:XCUIApplication){let block=app.descendants(matching:.any).matching(identifier:"bahw-block-habits").firstMatch;XCTAssertTrue(block.waitForExistence(timeout:20));let header=app.buttons["bahw-habits-open"]; if header.exists { header.tap() } else { block.tap() };XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout:10))}
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testEmptyAddCompleteFreezeRestoreAndRelaunch() throws {
        continueAfterFailure=false;let app=app("empty");open(app)
        XCTAssertTrue(app.buttons["habit-first"].exists);shot(app,"M4-V02-empty-L");app.buttons["habit-first"].tap()
        let name=app.textFields["habit-name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("أذكار هادئة");shot(app,"M4-V02-editor-L");app.buttons["habit-save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout:10))
        func row()->XCUIElement{app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","habit-row-")).firstMatch}
        XCTAssertTrue(row().waitForExistence(timeout:10));row().tap();let complete=app.buttons["habit-complete"];XCTAssertTrue(complete.waitForExistence(timeout:5));complete.tap();XCTAssertTrue(complete.waitForNonExistence(timeout:5))
        row().tap();XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["habit-progress"].label.contains("١ من ١"));app.buttons["habit-freeze"].tap();app.buttons["حتى أفكّه"].tap();XCTAssertTrue(app.buttons["habit-freeze"].waitForNonExistence(timeout:5))
        row().tap();XCTAssertTrue(app.buttons["habit-resume"].waitForExistence(timeout:5));shot(app,"M4-V02-frozen-L");app.buttons["habit-resume"].tap();XCTAssertTrue(app.buttons["habit-resume"].waitForNonExistence(timeout:5))
        row().tap();app.buttons["habit-delete"].tap();XCTAssertTrue(app.buttons["habit-first"].waitForExistence(timeout:5));app.buttons["habit-archived"].tap();app.buttons["استعد"].tap();XCTAssertTrue(row().waitForExistence(timeout:5))
        app.terminate();app.launch();open(app);XCTAssertTrue(row().waitForExistence(timeout:10));shot(app,"M4-V02-accessory-after-L");XCTAssertTrue(row().isHittable)
        let accessory=app.descendants(matching:.any).matching(identifier:"tab-accessory-next-prayer").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout:10))
        XCTAssertLessThanOrEqual(row().frame.maxY,accessory.frame.minY,"The first habit row should finish above the floating room accessory.")
        row().tap();XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["habit-progress"].label.contains("١ من ١"))
        app.buttons["تمّ"].tap();row().tap();app.buttons["habit-delete"].tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForExistence(timeout:5));app.buttons["habit-archived"].tap()
        let finalDelete=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","حذف نهائي")).firstMatch
        XCTAssertTrue(finalDelete.waitForExistence(timeout:5));finalDelete.tap();app.buttons["احذف نهائيًا"].tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForNonExistence(timeout:5))
        let undo=app.buttons["تراجع"];XCTAssertTrue(undo.waitForExistence(timeout:5));undo.tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForExistence(timeout:5));if !app.buttons["استعد"].exists {app.buttons["habit-archived"].tap()};app.buttons["استعد"].tap()
        XCTAssertTrue(row().waitForExistence(timeout:5))
    }
    func testOrbitAndAllFrequencyListsMatchDefaultBoards() throws {
        continueAfterFailure=false;let app=app("showcase");open(app);shot(app,"M4-V02-Adat-L")
        app.swipeUp(velocity:.slow);shot(app,"M4-V02-Adat-s1-L");app.swipeUp(velocity:.slow);shot(app,"M4-V02-Adat-s2-L")
        // Each period card shows only its own habits (owner 20 Oct).
        app.swipeDown(velocity:.fast);app.swipeDown(velocity:.fast)
        for (kind,habit) in [("weekly","الاتصال بالأخوال"),("monthly","صدقة الشهر"),("yearly","العمرة")] {
            let card=app.buttons["habits-period-"+kind];XCTAssertTrue(card.waitForExistence(timeout:5),app.debugDescription);card.tap()
            XCTAssertTrue(card.isSelected,kind)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",habit)).firstMatch.waitForExistence(timeout:5),kind)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","الماء،")).firstMatch.exists,kind)
            shot(app,"M4-V02-Adat-"+kind+"-L")
        }
        XCTAssertFalse(app.segmentedControls["عرض العادات"].exists) // RA8: alternate designs are v2.
    }
}
