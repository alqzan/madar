import XCTest

@MainActor final class MoneyZakatUITests:XCTestCase {
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    private func open(_ fixture:String,styles:String?=nil,moneyWriteHoldMS:Int?=nil)->XCUIApplication{
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MONEY_FIXTURE":fixture,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-17T12:00:00+03:00"];if let styles{app.launchEnvironment["MADAR_UI_STYLE_SETTINGS"]=styles}
        if let moneyWriteHoldMS{app.launchEnvironment["MADAR_UI_MONEY_WRITE_HOLD_MS"]=String(moneyWriteHoldMS)}
        app.launch();let tab=app.buttons["tab-customize"];XCTAssertTrue(tab.waitForExistence(timeout:20));tab.tap()
        let search=app.textFields["settings-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("المال");app.buttons["money-open"].tap()
        let door=app.buttons["money-zakat-open"];XCTAssertTrue(door.waitForExistence(timeout:10));for _ in 0..<8 where !door.isHittable{app.swipeUp(velocity:.slow)};door.tap();XCTAssertTrue(app.staticTexts["money-zakat-result"].waitForExistence(timeout:10));return app
    }
    /// OR-27: each hawl drawing and figure style the owner can pick in the room settings.
    func testHawlAndFigureStylesFromSettings(){
        continueAfterFailure=false
        for (hawl,figure) in [("crescents","heritage"),("orbit","modern"),("calendar","classic")] {
            let app=open("zakat",styles:"mal.hawlStyle="+hawl+",mal.figureStyle="+figure)
            XCTAssertTrue(app.descendants(matching:.any)["money-zakat-hawl-art-"+hawl].waitForExistence(timeout:10),hawl)
            XCTAssertTrue(app.staticTexts["money-zakat-hawl"].exists,hawl);shot(app,"M5-V22-style-"+hawl+"-L");app.terminate()
        }
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
    func testZakatEditorStaysOpenWhileSaving(){
        continueAfterFailure=false
        let app=open("zakat",moneyWriteHoldMS:3000)
        shot(app,"M5-V22-zakat-frame-guard-L")
        let price=app.buttons["money-zakat-price"];for _ in 0..<4 where !price.isHittable{app.swipeUp(velocity:.slow)};XCTAssertTrue(price.isHittable);price.tap()
        let field=app.textFields["money-zakat-gold-price"];XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:12)+"410");app.buttons["money-zakat-keyboard-done"].tap()
        let save=app.buttons["money-zakat-save"];for _ in 0..<5 where !save.isHittable{app.swipeUp(velocity:.slow)};XCTAssertTrue(save.isEnabled)
        let close=app.buttons["money-zakat-editor-close"];XCTAssertTrue(close.exists);XCTAssertTrue(close.isEnabled);shot(app,"M5-V22-editor-idle-L")
        save.tap()
        XCTAssertTrue(app.staticTexts["بيانات الزكاة"].exists);XCTAssertTrue(save.exists);XCTAssertFalse(save.isEnabled);XCTAssertTrue(save.label.contains("جارٍ الحفظ"))
        XCTAssertTrue(close.exists);XCTAssertFalse(close.isEnabled);shot(app,"M5-V22-editor-saving-L")
        XCTAssertTrue(app.staticTexts["بيانات الزكاة"].waitForNonExistence(timeout:10));XCTAssertTrue(app.staticTexts["money-zakat-result"].waitForExistence(timeout:10))
    }
    func testFirstUseAsksBeforeANumberAndHiddenDoesNotRevealTheScale(){
        continueAfterFailure=false
        let empty=open("empty");XCTAssertTrue(empty.staticTexts["money-zakat-result"].label.contains("اختر أساس"));shot(empty,"M5-V22-first-L");empty.buttons["money-zakat-basis-silver"].tap();XCTAssertTrue(empty.staticTexts["money-zakat-result"].label.contains("الديون"));empty.terminate()
        let hidden=open("zakatHidden");XCTAssertEqual(hidden.staticTexts["money-zakat-result"].label,"•••");shot(hidden,"M5-V22-hidden-L");hidden.buttons["money-zakat-reveal"].tap();XCTAssertTrue(hidden.staticTexts["money-zakat-result"].label.contains("٣٬٢١٢"))
    }
    func testHiddenEditorKeepsOtherAssetsHiddenUntilReveal(){
        continueAfterFailure=false
        let app=open("zakatHidden");let price=app.buttons["money-zakat-price"];for _ in 0..<4 where !price.isHittable{app.swipeUp(velocity:.slow)};price.tap()
        let reveal=app.buttons["money-zakat-editor-reveal"];for _ in 0..<4 where !reveal.isHittable{app.swipeUp(velocity:.slow)};XCTAssertTrue(reveal.waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["money-zakat-other"].exists);XCTAssertFalse(app.buttons["money-zakat-save"].isEnabled);shot(app,"M5-V22-editor-hidden-L")
        reveal.tap();XCTAssertTrue(app.textFields["money-zakat-other"].waitForExistence(timeout:5))
    }

    func testSourcesExplainTheChosenCalculationWithoutSelectingADebtRuling(){
        continueAfterFailure=false
        let app=open("zakat"),before=app.staticTexts["money-zakat-result"].label
        let sources=app.buttons["money-zakat-sources"]
        for _ in 0..<10 where !sources.isHittable { app.swipeUp(velocity:.slow) }
        XCTAssertTrue(sources.waitForExistence(timeout:5));sources.tap()
        let explanation=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","أثر الديون محل خلاف")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout:5))
        shot(app,"M5-V22-sources-L")
        for _ in 0..<10 where !app.staticTexts["money-zakat-result"].isHittable { app.swipeDown(velocity:.slow) }
        XCTAssertEqual(app.staticTexts["money-zakat-result"].label,before)
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
