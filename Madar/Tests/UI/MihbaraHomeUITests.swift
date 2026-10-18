import XCTest

@MainActor final class MihbaraHomeUITests: XCTestCase {
    private func app(_ fixture: String, epub: Data? = nil, paperIndex: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_MIHBARA_FIXTURE":fixture,"MADAR_UI_NOW":"2026-10-17T12:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"]
        if let epub { app.launchEnvironment["MADAR_UI_MIHBARA_EPUB_BASE64"] = epub.base64EncodedString() }
        if paperIndex { app.launchEnvironment["MADAR_UI_MIHBARA_PAPER_INDEX_FIXTURE"] = "1" }
        return app
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
        openPaperDetails(app)
        let page = app.textFields["mihbara-paper-position"]; XCTAssertTrue(page.waitForExistence(timeout:8)); page.tap(); page.press(forDuration:1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout:2) { app.menuItems["تحديد الكل"].tap() }
        else { page.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        page.typeText("١٤٨"); let done = app.toolbars.buttons["تمّ"]; if done.exists { done.tap() }; let save = app.buttons["mihbara-paper-save"]; reach(app, save); save.tap()
        app.terminate(); app.launch(); open(app); reach(app,app.buttons["mihbara-book-continue"]); app.buttons["mihbara-book-continue"].tap(); openPaperDetails(app); XCTAssertTrue(app.textFields["mihbara-paper-position"].waitForExistence(timeout:8)); XCTAssertTrue(String(describing: app.textFields["mihbara-paper-position"].value).contains("١٤٨")); shot(app,"M6-V01-position-L")
    }
    /// Since M6-V23 the paper-book card opens first; the position field lives in «الفهرس والتفاصيل».
    private func openPaperDetails(_ app: XCUIApplication) {
        let details = app.buttons["mihbara-paper-index-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, details); details.tap()
    }

    func testEmptyShelfPaperAddAndUndo() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app); shot(app,"M6-V01-empty-L")
        app.buttons["mihbara-add-paper"].tap()
        let paperSource = app.descendants(matching: .any)["mihbara-add-source-paper"]
        XCTAssertTrue(paperSource.waitForExistence(timeout:5)); paperSource.tap()
        let title = app.textFields["mihbara-paper-title"]; XCTAssertTrue(title.waitForExistence(timeout:8)); title.tap(); title.typeText("كتابي الأول")
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("٢٥٠"); if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let save = app.buttons["mihbara-paper-save"]; reach(app,save); shot(app,"M6-V01-add-paper-L"); save.tap()
        XCTAssertTrue(app.staticTexts["كتابي الأول"].firstMatch.waitForExistence(timeout:8)); shot(app, "M6-shared-undo-glass-L"); undo(app)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout:8))
    }
    func testPaperIndexUsesEditableChapterRowsAndOneUndoableSave() {
        continueAfterFailure = false; let app = app("empty", paperIndex: true); app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        let title = app.textFields["mihbara-paper-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(title.value as? String, "دفتر البدايات")
        XCTAssertEqual(app.textFields["mihbara-paper-chapter-title-0"].value as? String, "مدخل إلى القراءة")
        shot(app, "M6-V20-paper-index-L")
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            .press(forDuration: 0.33, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.79)))
        shot(app, "M6-V20-paper-index-s1-L")
        let save = app.buttons["mihbara-paper-save"]; reach(app, save); save.tap()
        XCTAssertTrue(app.staticTexts["دفتر البدايات"].waitForExistence(timeout: 8))
        undo(app)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout: 8))
    }
    func testPaperBookCardOpensPrefilledIndexEditorAndUndoRestoresMissingIndex() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        let title = app.textFields["mihbara-paper-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, title)
        title.tap(); title.typeText("كتاب ورقي تجريبي")
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("١٢٠")
        app.buttons["mihbara-paper-shelf"].tap()
        let wantShelf = app.buttons["أبي أقرأه"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 5), app.debugDescription)
        wantShelf.tap()
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let saveBook = app.buttons["mihbara-paper-save"]; reach(app, saveBook); saveBook.tap()

        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 { homeScroll.swipeDown(velocity: .slow) }
        let wantShelfTab = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelfTab.isHittable, app.debugDescription)
        wantShelfTab.tap()
        let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-book-")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        let prompt = app.buttons["mihbara-paper-index-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-paper-start"].exists)
        XCTAssertTrue(app.buttons["mihbara-paper-index-details"].exists)
        app.buttons["mihbara-paper-index-details"].tap()
        let savedPosition = app.textFields["mihbara-paper-position"]
        XCTAssertTrue(savedPosition.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, savedPosition); savedPosition.tap(); savedPosition.press(forDuration: 1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout: 2) { app.menuItems["تحديد الكل"].tap() }
        else { savedPosition.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        savedPosition.typeText("٤٧")
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let savePosition = app.buttons["mihbara-paper-save"]; reach(app, savePosition); savePosition.tap()
        XCTAssertTrue(app.buttons["mihbara-paper-index-prompt"].waitForExistence(timeout: 8), app.debugDescription)
        let positionSummary = app.staticTexts["mihbara-paper-position-summary"]
        XCTAssertTrue(positionSummary.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(positionSummary.label.contains("٤٧"), positionSummary.label)
        XCTAssertTrue(app.buttons["mihbara-paper-start"].label.contains("واصل القراءة"))
        shot(app, "M6-V23-page-progress-after-L")
        app.buttons["mihbara-paper-start"].tap()
        let continueBook = app.buttons["mihbara-book-continue"]
        reach(app, continueBook); continueBook.tap()
        shot(app, "M6-V23-paper-card-s1-L")

        app.buttons["mihbara-paper-index-details"].tap()
        let chapter = app.textFields["mihbara-paper-chapter-title-0"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 8), app.debugDescription)
        chapter.tap(); chapter.typeText("بداية الطريق")
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let saveIndex = app.buttons["mihbara-paper-save"]; reach(app, saveIndex); saveIndex.tap()
        XCTAssertTrue(app.staticTexts["فهرس طبعتك"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["mihbara-paper-start"].tap()
        undo(app)

        let savedBook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-book-")).firstMatch
        XCTAssertTrue(savedBook.waitForExistence(timeout: 8), app.debugDescription); savedBook.tap()
        XCTAssertTrue(app.buttons["mihbara-paper-index-prompt"].waitForExistence(timeout: 8), app.debugDescription)
    }
    func testAddBookSourcesShowsV1FormatsAndHonestEmptyState() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let addBook = app.buttons["mihbara-add-paper"]
        XCTAssertTrue(addBook.label.contains("أضف كتابًا"))
        addBook.tap()
        XCTAssertTrue(app.staticTexts["أضف كتابًا"].waitForExistence(timeout:8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-add-source-file"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-add-source-paper"].exists)
        XCTAssertTrue(app.buttons["mihbara-add-source-goodreads"].exists)
        XCTAssertTrue(app.staticTexts["PDF مصوّر"].exists)
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].exists)
        XCTAssertFalse(app.staticTexts["تصدير الشاملة"].exists)
        shot(app, "M6-V16-add-L")
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        XCTAssertTrue(app.textFields["mihbara-paper-title"].waitForExistence(timeout:8), app.debugDescription)
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

    func testSunnahDrawerUsesRealProgressAndOpensWirdAndImport() {
        continueAfterFailure = false
        let app = app("home"); app.launch(); open(app)
        let drawer = app.buttons["mihbara-sunnah-drawer"]
        reach(app, drawer)
        shot(app, "M6-V15-drawer-L")
        XCTAssertEqual(drawer.value as? String, "مغلق")
        drawer.tap()
        let read = app.buttons["mihbara-sunnah-drawer-read"]
        reach(app, read)
        XCTAssertTrue(app.staticTexts["١٢ من ٤٢ فهمتها"].exists)
        XCTAssertFalse(app.staticTexts["رياض الصالحين"].exists)
        reach(app, app.buttons["mihbara-sunnah-drawer-add"])
        app.swipeUp(velocity: .slow)
        shot(app, "M6-V15-drawer-s1-L")
        read.tap()
        XCTAssertTrue(app.textViews["mihbara-hadith-text"].waitForExistence(timeout: 8))
        app.buttons["تمّ"].tap()
        let add = app.buttons["mihbara-sunnah-drawer-add"]; reach(app, add); add.tap()
        XCTAssertTrue(app.buttons["mihbara-add-source-file"].waitForExistence(timeout: 8))
        app.buttons["mihbara-add-back"].tap()
        XCTAssertTrue(drawer.waitForExistence(timeout: 8))
        reach(app, drawer); drawer.tap()
        XCTAssertEqual(drawer.value as? String, "مغلق")
        XCTAssertFalse(app.buttons["mihbara-sunnah-drawer-add"].exists)
    }

    func testLocalEPUBOpensInArabicReaderAndClosesBackToItsShelf() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["كتاب اختبار القارئ"].exists)
        XCTAssertTrue(app.staticTexts["تأمل في القراءة"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.waitForExistence(timeout: 12), app.debugDescription)
        let printPage = app.staticTexts["mihbara-reader-print-page"]
        XCTAssertTrue(printPage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(printPage.label.contains("في المطبوع"), printPage.label)
        XCTAssertTrue(printPage.label.contains("٤٥٣"), printPage.label)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-progress"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-settings"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-contents"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-listen"].exists)
        shot(app, "M6-V06-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        let defaultSize = app.buttons["mihbara-reader-size-4"]
        XCTAssertTrue(defaultSize.waitForExistence(timeout: 5))
        XCTAssertTrue(defaultSize.isSelected)
        app.buttons["mihbara-reader-size-5"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-amiri"].isSelected)
        app.buttons["mihbara-reader-font-thmanyahSans"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].waitForSelection(timeout: 5))
        shot(app, "M6-V07-font-sheet-L")
        XCTAssertTrue(app.buttons["mihbara-reader-settings-close"].isHittable)
        app.buttons["mihbara-reader-settings-close"].tap()
        sleep(2); shot(app, "M6-V07-font-sans-L")
        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].isSelected)
        app.buttons["mihbara-reader-font-thmanyahSerif"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSerif"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        sleep(2); shot(app, "M6-V07-font-serif-L")
        // Page options: change each, undo the last, then reset to the agreed defaults.
        app.buttons["mihbara-reader-settings"].tap()
        let more = app.buttons["mihbara-reader-more"]; XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        let footerBar = app.buttons["mihbara-reader-footer-bar"]
        for _ in 0..<4 where !footerBar.isHittable { app.swipeUp(velocity: .slow) }
        app.buttons["mihbara-reader-lineSpacing-3"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-3"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-margins-1"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-margins-1"].waitForSelection(timeout: 5))
        let justify = app.switches["mihbara-reader-justify"], heavier = app.switches["mihbara-reader-heavier"]
        XCTAssertEqual(justify.value as? String, "1"); XCTAssertEqual(heavier.value as? String, "0")
        heavier.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(heavier.waitForValue("1", timeout: 5))
        footerBar.tap()
        XCTAssertTrue(footerBar.waitForSelection(timeout: 5))
        shot(app, "M6-V07-options-changed-L")
        let undo = app.descendants(matching: .any)["mihbara-reader-undo"].buttons["undo-button"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-footer-full"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-3"].isSelected)
        footerBar.tap(); XCTAssertTrue(footerBar.waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-progress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["mihbara-reader-print-page"].exists)
        sleep(2); shot(app, "M6-V07-options-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        if !app.buttons["mihbara-reader-reset"].exists { app.buttons["mihbara-reader-more"].tap() }
        let reset = app.buttons["mihbara-reader-reset"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp(velocity: .slow) }
        reset.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-footer-full"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-2"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-margins-2"].isSelected)
        XCTAssertEqual(app.switches["mihbara-reader-heavier"].value as? String, "0")
        for _ in 0..<4 { app.swipeDown(velocity: .slow); if app.buttons["mihbara-reader-size-4"].isHittable { break } }
        XCTAssertTrue(app.buttons["mihbara-reader-size-4"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-font-amiri"].isSelected)
        shot(app, "M6-V07-sheet-L")
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.staticTexts["mihbara-reader-print-page"].waitForExistence(timeout: 5))
        app.buttons["mihbara-reader-contents"].tap()
        XCTAssertTrue(app.staticTexts["فهرس الكتاب"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-contents-close"].isHittable)
        app.buttons["mihbara-reader-contents-close"].tap()
        app.buttons["mihbara-reader-close"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch.exists)
    }

    func testReaderWordCardHighlightsParagraphUndoesNotesAndCopies() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)
        sleep(1)
        // A long press selects a word; Madar's card replaces the system menu.
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        let card = app.descendants(matching: .any)["mihbara-word-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-word-lookup"].exists)
        XCTAssertTrue(app.buttons["mihbara-word-note"].exists)
        XCTAssertTrue(app.buttons["mihbara-word-copy"].exists)
        XCTAssertFalse(app.buttons["mihbara-highlight-yellow"].isSelected)
        shot(app, "M6-V08-card-L")
        app.buttons["mihbara-highlight-yellow"].tap()
        XCTAssertTrue(app.buttons["mihbara-highlight-yellow"].waitForSelection(timeout: 8), app.debugDescription)
        sleep(1); shot(app, "M6-V08-highlight-L")
        app.buttons["mihbara-highlight-green"].tap()
        XCTAssertTrue(app.buttons["mihbara-highlight-green"].waitForSelection(timeout: 8))
        XCTAssertFalse(app.buttons["mihbara-highlight-yellow"].isSelected)
        app.buttons["mihbara-word-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        let undo = app.descendants(matching: .any)["mihbara-reader-toast"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), app.debugDescription); undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 8))
        // Tapping the highlighted paragraph reopens its card with the restored colour.
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1); shot(app, "M6-V08-retap-L")
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-highlight-yellow"].waitForSelection(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-word-lookup"].exists)
        app.buttons["mihbara-word-copy"].tap()
        XCTAssertTrue(app.buttons["mihbara-word-copy"].staticTexts["نُسخت"].waitForExistence(timeout: 3) || app.staticTexts["نُسخت"].exists, app.debugDescription)
        app.buttons["mihbara-word-note"].tap()
        let text = app.textViews["mihbara-note-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        text.typeText("فكرة")
        shot(app, "M6-V08-note-L")
        app.buttons["mihbara-note-save"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 8))
        XCTAssertFalse(card.exists)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-toast"].waitForExistence(timeout: 5), app.debugDescription)
        sleep(1); shot(app, "M6-V08-saved-L")
    }

    func testReaderColoursVersesAndOpensFootnoteInPlace() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "اقْرَأْ")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        sleep(1); shot(app, "M6-V09-verse-L")
        let marker = app.links["١"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        marker.tap()
        let card = app.descendants(matching: .any)["mihbara-footnote-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        let text = app.staticTexts["mihbara-footnote-text"]
        XCTAssertTrue(text.label.contains("هامش تجريبي"), text.label)
        XCTAssertFalse(text.label.contains("عودة إلى المتن"), text.label)
        // The reader stayed on the chapter rather than jumping to the notes file.
        XCTAssertTrue(app.staticTexts["mihbara-reader-print-page"].label.contains("٤٥٣"))
        sleep(1); shot(app, "M6-V09-footnote-L")
        app.buttons["mihbara-footnote-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    func testReaderNightThemeScrollKeepsPlaceAndResets() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        sleep(3); shot(app, "M6-V10-open-L")
        app.buttons["mihbara-reader-settings"].tap()
        let auto = app.buttons["mihbara-reader-theme-auto"]
        XCTAssertTrue(auto.waitForExistence(timeout: 5)); XCTAssertTrue(auto.isSelected)
        for theme in ["paper", "warm", "calm", "black"] { XCTAssertTrue(app.buttons["mihbara-reader-theme-\(theme)"].exists, theme) }
        app.buttons["mihbara-reader-theme-night"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-theme-night"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-mode-scroll"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-mode-scroll"].waitForSelection(timeout: 5))
        shot(app, "M6-V10-sheet-night-L")
        app.buttons["mihbara-reader-settings-close"].tap()
        let printPage = app.staticTexts["mihbara-reader-print-page"]
        XCTAssertTrue(printPage.waitForExistence(timeout: 8))
        sleep(2)
        XCTAssertTrue(printPage.label.contains("٤٥٣"), printPage.label)
        shot(app, "M6-V10-night-scroll-L")
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.swipeUp(velocity: .slow)
        sleep(2); shot(app, "M6-V10-night-scroll-s1-L")
        app.buttons["mihbara-reader-settings"].tap()
        if !app.buttons["mihbara-reader-reset"].exists { app.buttons["mihbara-reader-more"].tap() }
        let reset = app.buttons["mihbara-reader-reset"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp(velocity: .slow) }
        reset.tap()
        for _ in 0..<4 { app.swipeDown(velocity: .slow); if app.buttons["mihbara-reader-theme-auto"].isHittable { break } }
        XCTAssertTrue(app.buttons["mihbara-reader-theme-auto"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-mode-pages"].isSelected)
    }

    func testFocusReaderAdvancesOneParagraphAndKeepsReadingChromeOutOfSight() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["mihbara-reader-settings"].tap()
        let calm = app.buttons["mihbara-reader-theme-calm"]
        XCTAssertTrue(calm.waitForExistence(timeout: 5), app.debugDescription); calm.tap()
        XCTAssertTrue(calm.waitForSelection(timeout: 5), app.debugDescription)
        let focus = app.buttons["mihbara-reader-mode-focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5), app.debugDescription); focus.tap()
        XCTAssertTrue(focus.waitForSelection(timeout: 5), app.debugDescription)
        app.buttons["mihbara-reader-settings-close"].tap()

        let previous = app.buttons["mihbara-focus-previous"]
        let next = app.buttons["mihbara-focus-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["mihbara-focus-print-page"].waitForExistence(timeout: 5), app.debugDescription)
        next.tap()
        let positionReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != ''"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [positionReady], timeout: 8), .completed, app.debugDescription)
        let initialPosition = next.value as? String ?? ""
        XCTAssertFalse(initialPosition.isEmpty, "Advancing focus should expose its paragraph position\n\(app.debugDescription)")
        XCTAssertTrue(previous.exists)
        XCTAssertFalse(app.buttons["mihbara-reader-settings"].exists, "Focus mode should hide its reading chrome")
        shot(app, "M6-V11-focus-L")

        next.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialPosition), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 8), .completed, app.debugDescription)
        shot(app, "M6-V11-focus-s1-L")

        let nextMove = next.value as? String ?? ""
        next.tap()
        let movedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", nextMove), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [movedAgain], timeout: 8), .completed, app.debugDescription)
        sleep(1)
        shot(app, "M6-V11-focus-s2-L")
    }

    func testEnglishEPUBReadsLeftToRightWithItsOwnSettings() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "كتاب اختبار القارئ")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        sleep(4); shot(app, "M6-V12-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.staticTexts["كتاب إنجليزي · إعداداتك للإنجليزي"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-reader-font-amiri"].exists)
        XCTAssertFalse(app.buttons["mihbara-reader-more"].exists)
        app.buttons["mihbara-reader-size-6"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-size-6"].waitForSelection(timeout: 5))
        shot(app, "M6-V12-sheet-L")
        app.buttons["mihbara-reader-reset"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-size-4"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        app.buttons["mihbara-reader-close"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
    }
}

private extension XCUIElement {
    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: self)], timeout: timeout) == .completed
    }
    func waitForSelection(timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: self)], timeout: timeout) == .completed
    }
}
