import XCTest

@MainActor final class MoneyZakatUITests:XCTestCase {
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    private func open(_ fixture:String)->XCUIApplication{
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MONEY_FIXTURE":fixture,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-17T12:00:00+03:00"]
        app.launch();let tab=app.tabBars.buttons["خصّص"];XCTAssertTrue(tab.waitForExistence(timeout:20));tab.tap()
        let search=app.textFields["settings-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("المال");app.buttons["money-open"].tap()
        let door=app.buttons["money-zakat-open"];XCTAssertTrue(door.waitForExistence(timeout:10));for _ in 0..<8 where !door.isHittable{app.swipeUp(velocity:.slow)};door.tap();XCTAssertTrue(app.staticTexts["money-zakat-result"].waitForExistence(timeout:10));return app
    }
    func testScaleHawlPriceUpdateDoesNotChangeTheResultAndUndoRestoresPrice(){
        continueAfterFailure=false
        let app=open("zakat"),before=app.staticTexts["money-zakat-result"].label
        XCTAssertTrue(before.contains("٣٬٢١٢"),before);XCTAssertTrue(app.staticTexts["money-zakat-hawl"].exists);shot(app,"M5-V22-zakat-L")
        let price=app.buttons["money-zakat-price"];for _ in 0..<4 where !price.isHittable{app.swipeUp(velocity:.slow)};shot(app,"M5-V22-zakat-s1-L");price.tap()
        let field=app.textFields["money-zakat-gold-price"];XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:12)+"410");app.buttons["money-zakat-keyboard-done"].tap()
        let save=app.buttons["money-zakat-save"];for _ in 0..<5 where !save.isHittable{app.swipeUp(velocity:.slow)};shot(app,"M5-V22-editor-L");save.tap()
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["money-zakat-result"].label,before);app.buttons["تراجع"].tap()
        XCTAssertTrue(app.staticTexts["السعر أقدم من ٣٠ يومًا؛ حدّثه"].exists)
    }
    func testFirstUseAsksBeforeANumberAndHiddenDoesNotRevealTheScale(){
        continueAfterFailure=false
        let empty=open("empty");XCTAssertTrue(empty.staticTexts["money-zakat-result"].label.contains("اختر أساس"));shot(empty,"M5-V22-first-L");empty.buttons["money-zakat-basis-silver"].tap();XCTAssertTrue(empty.staticTexts["money-zakat-result"].label.contains("الديون"));empty.terminate()
        let hidden=open("zakatHidden");XCTAssertEqual(hidden.staticTexts["money-zakat-result"].label,"•••");shot(hidden,"M5-V22-hidden-L");hidden.buttons["money-zakat-reveal"].tap();XCTAssertTrue(hidden.staticTexts["money-zakat-result"].label.contains("٣٬٢١٢"))
    }

    func testAnnualReminderStartsOffSavesAndUndoRestoresOff(){
        continueAfterFailure=false
        let app=open("zakat")
        shot(app,"M5-V22-zakat-L")
        let week=app.buttons["money-zakat-reminder-option-1week"]
        for _ in 0..<8 where !week.isHittable { app.swipeUp(velocity:.slow) }
        XCTAssertTrue(week.waitForExistence(timeout:5))
        let date=app.descendants(matching:.any)["money-zakat-reminder-date"]
        XCTAssertTrue(date.exists);XCTAssertFalse(date.label.isEmpty,"The annual date is exposed as a dual-calendar label")
        XCTAssertFalse(app.staticTexts["money-zakat-reminder-state"].exists,"A new reminder is opt-in")
        week.tap()
        let save=app.buttons["money-zakat-reminder-save"]
        XCTAssertTrue(save.waitForExistence(timeout:5));XCTAssertTrue(week.isSelected)
        shot(app,"M5-V22-zakat-reminder-s1-L")
        save.tap()
        XCTAssertTrue(app.staticTexts["money-zakat-reminder-state"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["تراجع"].waitForExistence(timeout:5))
        app.buttons["تراجع"].tap()
        XCTAssertFalse(app.staticTexts["money-zakat-reminder-state"].exists,"Undo restores the default off setting")
        XCTAssertFalse(week.isSelected)
    }
}
