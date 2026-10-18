import XCTest

@MainActor final class MihbaraHomeUITests: XCTestCase {
    private func app(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MIHBARA_FIXTURE":fixture,"MADAR_UI_NOW":"2026-10-17T12:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"]; return app
    }
    private func open(_ app: XCUIApplication) {
        let customize = app.tabBars.buttons["خصّص"]; XCTAssertTrue(customize.waitForExistence(timeout:20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout:10)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout:5)); door.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout:10), app.debugDescription)
    }
    private func undo(_ app: XCUIApplication) {
        let button = app.descendants(matching: .any)["mihbara-undo"].buttons["undo-button"]
        XCTAssertTrue(button.waitForExistence(timeout:8), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reach(_ app: XCUIApplication, _ button: XCUIElement) { for _ in 0..<7 where !button.isHittable { app.swipeUp(velocity:.slow) }; XCTAssertTrue(button.isHittable) }
    func testHomeWirdExplicitUnderstandingUndoAndRelaunch() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        XCTAssertFalse(app.tabBars.buttons["خصّص"].isHittable)
        XCTAssertTrue(app.staticTexts["خزانة «قديمًا»"].waitForExistence(timeout:8))
        shot(app,"M6-V01-home-L")
        var wird = app.buttons["mihbara-wird-open"]; reach(app,wird)
        XCTAssertTrue(app.staticTexts["بقي ٣٠ حديثًا"].exists)
        XCTAssertTrue(app.staticTexts["١٢ من ٤٢"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","لا يؤمن أحدكم")).firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.66)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.637)))
        XCTAssertTrue(wird.isHittable)
        shot(app,"M6-V01-desk-L"); wird.tap()
        XCTAssertTrue(app.textViews["mihbara-hadith-text"].waitForExistence(timeout:8)); XCTAssertTrue(String(describing: app.textViews["mihbara-hadith-text"].value).contains("لا يؤمن أحدكم")); shot(app,"M6-V01-hadith-L")
        let returnTo = app.buttons["mihbara-hadith-return"]; reach(app,returnTo); returnTo.tap()
        undo(app)
        shot(app,"M6-V01-return-undone-L")
        wird = app.buttons["mihbara-wird-open"]; XCTAssertTrue(wird.waitForExistence(timeout:8)); wird.tap()
        let understood = app.buttons["mihbara-hadith-understood"]; reach(app,understood); understood.tap()
        XCTAssertTrue(app.buttons["mihbara-wird-closed"].waitForExistence(timeout:8)); shot(app,"M6-V01-understood-L"); undo(app)
        XCTAssertTrue(app.buttons["mihbara-wird-open"].waitForExistence(timeout:8)); app.terminate(); app.launch(); open(app)
        reach(app,app.buttons["mihbara-book-continue"]); app.buttons["mihbara-book-continue"].tap()
        let page = app.textFields["mihbara-book-page"]; XCTAssertTrue(page.waitForExistence(timeout:8)); page.tap(); page.press(forDuration:1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout:2) { app.menuItems["تحديد الكل"].tap() }
        else { page.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        page.typeText("١٤٨"); let done = app.toolbars.buttons["تمّ"]; if done.exists { done.tap() }; app.buttons["mihbara-book-save-position"].tap()
        app.terminate(); app.launch(); open(app); reach(app,app.buttons["mihbara-book-continue"]); app.buttons["mihbara-book-continue"].tap(); XCTAssertTrue(app.textFields["mihbara-book-page"].waitForExistence(timeout:8)); XCTAssertTrue(String(describing: app.textFields["mihbara-book-page"].value).contains("١٤٨")); shot(app,"M6-V01-position-L")
    }
    func testEmptyShelfPaperAddAndUndo() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app); shot(app,"M6-V01-empty-L")
        app.buttons["mihbara-add-paper"].tap(); let title = app.textFields["mihbara-paper-title"]; XCTAssertTrue(title.waitForExistence(timeout:8)); title.tap(); title.typeText("كتابي الأول")
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("٢٥٠"); if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let save = app.buttons["mihbara-paper-save"]; reach(app,save); shot(app,"M6-V01-add-paper-L"); save.tap()
        XCTAssertTrue(app.staticTexts["كتابي الأول"].firstMatch.waitForExistence(timeout:8)); undo(app)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout:8))
    }
    func testPrivateNotebookHidesNoteTextUntilDeviceAuthentication() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let notebook = app.buttons["mihbara-notebook"]; reach(app, notebook); notebook.tap()
        XCTAssertTrue(app.buttons["mihbara-notebook-unlock"].waitForExistence(timeout:8), app.debugDescription)
        XCTAssertFalse(app.staticTexts["سر لا يظهر قبل المصادقة"].exists)
        app.buttons["mihbara-notebook-close"].tap()
    }
    func testRahlOpeningChoiceResetUndoAndRelaunch() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let preferences = app.buttons["mihbara-opening-preference"]; reach(app, preferences); preferences.tap()
        let afterFajr = app.buttons["mihbara-rahlOpens-afterFajr"]
        let untilDone = app.buttons["mihbara-rahlOpens-untilDone"]
        let manual = app.buttons["mihbara-rahlOpens-manual"]
        XCTAssertTrue(afterFajr.waitForExistence(timeout:8)); shot(app,"M6-V02-opening-L")
        XCTAssertEqual(afterFajr.value as? String, "محدد")
        untilDone.tap(); XCTAssertEqual(untilDone.value as? String, "محدد")
        undo(app); XCTAssertEqual(afterFajr.value as? String, "محدد")
        manual.tap(); XCTAssertEqual(manual.value as? String, "محدد")
        app.buttons["mihbara-rahlOpens-reset"].tap()
        XCTAssertEqual(afterFajr.value as? String, "محدد")
        undo(app); XCTAssertEqual(manual.value as? String, "محدد")
        app.buttons["mihbara-rahlOpens-close"].tap(); app.terminate(); app.launch(); open(app)
        reach(app, preferences); preferences.tap()
        XCTAssertEqual(app.buttons["mihbara-rahlOpens-manual"].value as? String, "محدد")
    }
}
