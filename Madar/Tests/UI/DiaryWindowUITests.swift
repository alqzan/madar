import XCTest

@MainActor final class DiaryWindowUITests: XCTestCase {
    private func launch(_ variant: String, rootRouteHarness: Bool = false, diaryCommandHoldMS: Int? = nil,
                        now: String = "2026-10-15T15:00:00+03:00", dayBoundaryHarness: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var environment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": variant,
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": now]
        if rootRouteHarness { environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] = "1" }
        if dayBoundaryHarness { environment["MADAR_UI_DIARY_DAY_BOUNDARY_HARNESS"] = "1" }
        if let diaryCommandHoldMS { environment["MADAR_UI_DIARY_COMMAND_HOLD_MS"] = String(diaryCommandHoldMS) }
        app.launchEnvironment = environment
        app.launch(); XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        return app
    }
    /// 12 Nov: the words live in today's composer, not in a page of their own: the root route goes home and the draft is kept for the next visit.
    func testDiaryRootRouteClosesSearchAndKeepsTheComposerDraft() throws {
        continueAfterFailure = false
        let app = launch("empty", rootRouteHarness: true)
        app.buttons["diary-search"].tap()
        XCTAssertTrue(app.textFields["diary-search-query"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["ui-test-open-diary-root"].tap()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.textFields["diary-search-query"].exists)

        app.openDiaryEditorFromHome()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        editor.tap(); editor.typeText("مسودة تحفظ قبل الرجوع")
        app.buttons["ui-test-open-diary-root"].tap()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertFalse(editor.exists)
        app.diaryOpener.tap()
        let field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), app.debugDescription)
        let predicate = NSPredicate(format: "value CONTAINS %@", "مسودة تحفظ قبل الرجوع")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: field)], timeout: 10), .completed, "The draft is read again when today's page reopens: \(String(describing: field.value))")
    }
    func testDiaryWriteRouteKeepsTheGrownComposerAndYesterdayOpensTheSameDraft() {
        continueAfterFailure = false
        let app = launch("empty", rootRouteHarness: true)
        app.openDiaryEditorFromHome()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        editor.tap(); editor.typeText("مسودة اليوم")
        let todayRoute = app.buttons["ui-test-open-diary-today"]
        todayRoute.tap(); todayRoute.tap()
        XCTAssertEqual(editor.value as? String, "مسودة اليوم", "The same write target must not replace its live draft.")
        XCTAssertEqual(app.textViews.matching(identifier: "diary-editor-text").count, 1, "Repeating the same route must not stack a second editor.")
        app.buttons["ui-test-open-diary-yesterday"].tap()
        // «أمس» keeps its own writing page; it opens on the draft already begun, still for today.
        let page = app.textViews["diary-editor-text"]
        XCTAssertTrue(page.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(NSPredicate(format: "value CONTAINS %@", "مسودة اليوم").evaluate(with: page), "\(String(describing: page.value))")
        XCTAssertTrue(app.buttons["diary-editor-today"].isSelected, app.debugDescription)
        app.terminate()
    }
    func testDiaryTodayDraftDisclosesAndKeepsItsOriginalDayAfterFajr() {
        continueAfterFailure = false
        let app = launch("empty", rootRouteHarness: true, now: "2026-10-15T03:00:00+03:00", dayBoundaryHarness: true)
        app.openDiaryEditorFromHome()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-editor-today"].isSelected, app.debugDescription)
        editor.tap(); editor.typeText("كتابة عبر فجر اليوم")
        // The draft is written (with its day) before the day turns.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "المسودة محفوظة")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["ui-test-advance-diary-clock"].tap()
        let originalDayNotice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "تُحفظ في صفحتها الأصلية")).firstMatch
        XCTAssertTrue(originalDayNotice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-editor-today"].isSelected, app.debugDescription)
        app.buttons["diary-editor-save"].tap()
        // The words went to the page they were begun on (the 14th, before the day turned), not to the new day.
        app.open(URL(string: "madar://notes/day/2026-10-14")!)
        let savedLine = app.staticTexts.matching(identifier: "diary-day-line").matching(NSPredicate(format: "label CONTAINS %@", "كتابة عبر فجر اليوم")).firstMatch
        XCTAssertTrue(savedLine.waitForExistence(timeout: 15), app.debugDescription)
        app.open(URL(string: "madar://notes/day/2026-10-15")!)
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "كتابة عبر فجر اليوم")).firstMatch.waitForExistence(timeout: 3), "The new day's page must not take the old day's draft")
        app.terminate()
    }
    func testDiaryRootClosesCleanYearbookAndExport() {
        continueAfterFailure = false
        let app = launch("home", rootRouteHarness: true)
        let days = app.buttons["diary-days"]
        XCTAssertTrue(days.waitForExistence(timeout: 8), app.debugDescription); days.tap()
        app.buttons["diary-hub-more"].tap()
        let yearbook = app.buttons["diary-yearbook"]
        XCTAssertTrue(yearbook.isHittable, app.debugDescription); yearbook.tap()
        let bookRoot = app.buttons["diary-book-root-route"]
        XCTAssertTrue(bookRoot.waitForExistence(timeout: 8), app.debugDescription); bookRoot.tap()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-book-close"].exists, app.debugDescription)

        app.buttons["diary-days"].tap()
        app.buttons["diary-hub-more"].tap()
        let export = app.buttons["diary-export"]
        XCTAssertTrue(export.isHittable, app.debugDescription); export.tap()
        let exportRoot = app.buttons["diary-export-root-route"]
        XCTAssertTrue(exportRoot.waitForExistence(timeout: 8), app.debugDescription); exportRoot.tap()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-export-close"].exists, app.debugDescription)
        app.terminate()
    }
    func testDiaryRootClosesCleanLetterComposerAndReschedule() {
        continueAfterFailure = false
        let app = launch("lettersRoutes", rootRouteHarness: true)
        app.buttons["diary-days"].tap()
        app.buttons["diary-hub-letters"].tap()
        app.buttons["diary-letter-compose"].tap()
        let composer = app.textViews["diary-letter-text-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["diary-letter-root-route"].tap()
        XCTAssertTrue(composer.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 10), app.debugDescription)

        app.buttons["diary-days"].tap()
        app.buttons["diary-hub-letters"].tap()
        app.buttons["diary-letter-orphan-date"].tap()
        let reschedule = app.buttons["diary-letter-reschedule-save"]
        XCTAssertTrue(reschedule.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["diary-letter-reschedule-root-route"].tap()
        XCTAssertTrue(reschedule.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    func testDiaryRootWaitsForDirtyLetterComposerUntilExplicitDiscard() {
        continueAfterFailure = false
        let app = launch("letters", rootRouteHarness: true)
        app.buttons["diary-days"].tap(); app.buttons["diary-hub-letters"].tap()
        app.buttons["diary-letter-compose"].tap()
        let composer = app.textViews["diary-letter-text-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), app.debugDescription)
        let draft = "رسالة تبقى حتى أختار تجاهلها"
        composer.tap(); composer.typeText(draft)
        app.buttons["diary-letter-root-route"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The root route must wait for an unsaved letter.\n" + app.debugDescription)
        XCTAssertTrue((composer.value as? String)?.contains(draft) == true, app.debugDescription)
        app.buttons["diary-letter-cancel"].tap()
        let discard = app.alerts.buttons["تجاهل الرسالة"]
        XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription); discard.tap()
        XCTAssertTrue(composer.waitForNonExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }
    func testDiaryLetterLocksInputsAndWaitsForSealBeforeRootRoute() {
        continueAfterFailure = false
        let app = launch("letters", rootRouteHarness: true, diaryCommandHoldMS: 3500)
        app.buttons["diary-days"].tap(); app.buttons["diary-hub-letters"].tap()
        app.buttons["diary-letter-compose"].tap()
        let composer = app.textViews["diary-letter-text-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), app.debugDescription)
        composer.tap(); composer.typeText("رسالة محفوظة مرة واحدة")
        let seal = app.buttons["diary-letter-seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 8), app.debugDescription)
        let readyToSeal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: seal)
        XCTAssertEqual(XCTWaiter.wait(for: [readyToSeal], timeout: 8), .completed, app.debugDescription); seal.tap()
        XCTAssertFalse(composer.isEnabled, app.debugDescription)
        XCTAssertFalse(app.buttons["diary-letter-cancel"].isEnabled, app.debugDescription)

        let root = app.buttons["diary-letter-root-route"]
        if !root.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(root.isHittable, app.debugDescription); root.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The root request must wait for the sealing command.")
        XCTAssertFalse(composer.isEnabled, app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(composer.waitForNonExistence(timeout: 8), app.debugDescription)
        app.terminate()
    }
    func testWindowYearsMarginTodayAndRelaunch() throws {
        continueAfterFailure = false
        let app = launch("home")
        let currentMonth = app.descendants(matching: .any)["diary-current-month"]
        XCTAssertTrue(currentMonth.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(currentMonth.label.contains("أكتوبر"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("ربيع"), currentMonth.label)
        XCTAssertTrue(currentMonth.label.contains("جمادى"), currentMonth.label)
        XCTAssertTrue(app.buttons["diary-year-2025-10-15"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "M3-V01-window-L")
        // OR-10: one card per past year, newest first; a card opens that day, whose «اكتب في هامشها» writes the margin.
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].exists, app.debugDescription)
        // The strip runs right to left: the newest year is the rightmost card.
        XCTAssertGreaterThan(app.buttons["diary-year-2025-10-15"].frame.minX, app.buttons["diary-year-2024-10-15"].frame.minX)
        XCTAssertFalse(app.buttons["diary-year-previous"].exists)
        app.swipeUp()
        capture(app, "M3-V01-window-scrolled-L")
        app.swipeDown()
        app.buttons["diary-year-2024-10-15"].tap()
        XCTAssertTrue(app.staticTexts["مشينا بعد المغرب، والجو صار يحتمل."].waitForExistence(timeout: 8))
        let margin = app.buttons["diary-day-write"]
        XCTAssertTrue(margin.waitForExistence(timeout: 8)); margin.tap()
        let editor = app.textViews["diary-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("هامش من يومي")
        capture(app, "M3-V01-margin-editor-L")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForNonExistence(timeout: 10))
        app.closeDiaryDay()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "هامش من يومي")).firstMatch.waitForExistence(timeout: 10))
        app.closeDiaryDay()
        app.openDiaryEditorFromHome()
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText("سطر محفوظ من اليوم")
        capture(app, "M3-V01-text-editor-L")
        app.buttons["diary-editor-save"].tap()
        app.closeDiaryDay()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 25)); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["سطر محفوظ من اليوم"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-today-L")
    }
    func testHomeReadFailureAfterFirstSnapshotShowsRetryInsteadOfStalePage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "home",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_DIARY_HOME_READ_FAILURE_AFTER_FIRST": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 25), app.debugDescription)
        let retry = app.buttons["diary-home-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-today"].exists, "A stale page must not remain available after its refresh fails.")
        capture(app, "AU-95-diary-home-read-failure-L")
        retry.tap()
        XCTAssertTrue(app.buttons["diary-today"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "AU-95-diary-home-read-recovered-L")
        app.terminate()
    }
    func testEntryRouteScrollsToAndBrieflyHighlightsItsLine() throws {
        let app = launch("entryRoute")
        let id = "44444444-4444-4444-8444-444444440001"
        app.open(URL(string: "madar://notes/entry/\(id)")!)
        let target = app.descendants(matching: .any)["diary-entry-\(id)"]
        XCTAssertTrue(target.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(target.isHittable, "The diary entry link must land on its exact line.")
        capture(app, "AU-95-diary-entry-route-highlight-L")
        app.terminate()
    }
    func testRepeatedEntryRouteTargetsAnotherLineInTheSameOpenDay() throws {
        let app = launch("entryRoute")
        let first = "44444444-4444-4444-8444-444444440001"
        let second = "44444444-4444-4444-8444-444444440002"
        app.open(URL(string: "madar://notes/entry/\(first)")!)
        XCTAssertTrue(app.descendants(matching: .any)["diary-entry-\(first)"].waitForExistence(timeout: 15), app.debugDescription)
        app.open(URL(string: "madar://notes/entry/\(second)")!)
        let target = app.descendants(matching: .any)["diary-entry-\(second)"]
        XCTAssertTrue(target.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(target.isHittable, "A second entry route must retarget the already-open day sheet.")
        capture(app, "AU-95-diary-entry-route-repeat-L")
        app.terminate()
    }
    func testDiarySearchRouteUpdatesTheAlreadyOpenSearch() throws {
        let app = launch("home")
        func openSearch(_ query: String) {
            var url = URLComponents(); url.scheme = "madar"; url.host = "search"
            url.queryItems = [.init(name: "q", value: query), .init(name: "room", value: "notes")]
            app.open(url.url!)
        }
        openSearch("عشاء")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary-search-result-")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        openSearch("اتصلت")
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary-search-result-")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(second.label.contains("اتصلت"), second.label)
        XCTAssertEqual(app.textFields["diary-search-query"].value as? String, "اتصلت")
        app.terminate()
    }
    func testSameLetterRouteReopensItsDetails() throws {
        let app = launch("letters", rootRouteHarness: true)
        let letterURL = URL(string: "madar://notes/letter/33333333-3333-4333-8333-333333333331")!
        app.open(letterURL)
        let letterOpen = app.buttons["diary-letter-open"]
        XCTAssertTrue(letterOpen.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["diary-letter-done"].tap()
        XCTAssertTrue(letterOpen.waitForNonExistence(timeout: 8), app.debugDescription)
        app.open(letterURL)
        XCTAssertTrue(app.buttons["diary-letter-open"].waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["diary-letter-done"].tap()

        app.terminate()
    }
    func testDiaryRootLinkClosesTheOpenArchiveAndLetter() throws {
        let app = launch("letters")
        app.open(URL(string: "madar://notes/letter/33333333-3333-4333-8333-333333333331")!)
        XCTAssertTrue(app.buttons["diary-letter-open"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["diary-letter-done"].tap()
        XCTAssertTrue(app.buttons["diary-hub-letters"].waitForExistence(timeout: 10), app.debugDescription)
        app.open(URL(string: "madar://notes")!)
        XCTAssertTrue(app.buttons["diary-hub-letters"].waitForNonExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(app.staticTexts["diary-home-title"].exists, app.debugDescription)
        app.terminate()
    }
    /// OR-13 (12 Nov): heading, bold and italic show formatted while writing and are stored as Markdown; no raw mark is ever visible.
    func testEditorFormattingNeverShowsRawMarks() throws {
        continueAfterFailure = false
        let app = launch("home")
        app.openDiaryEditorFromHome()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("مساء هادئ")
        app.buttons["diary-editor-heading"].tap()
        editor.typeText("\n")
        app.buttons["diary-editor-heading"].tap()
        editor.typeText("كان يومًا ")
        app.buttons["diary-editor-bold"].tap()
        editor.typeText("طويلًا")
        let value = (editor.value as? String) ?? ""
        XCTAssertFalse(value.contains("*") || value.contains("#"), "The writing surface shows formatting, never marks: \(value)")
        capture(app, "OR-13-editor-tools-L")
        app.buttons["diary-editor-save"].tap()
        let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "كان يومًا")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(line.label.contains("*") || line.label.contains("#"), line.label)
        XCTAssertTrue(line.label.contains("طويلًا"), line.label)
        capture(app, "OR-13-formatted-page-L")
    }
    func testFirstDayHasWorkingOneTapKeyboardAndCancelWritesNothing() throws {
        continueAfterFailure = false
        let app = launch("empty")
        XCTAssertTrue(app.descendants(matching: .any)["diary-today-invitation"].waitForExistence(timeout: 10))
        capture(app, "M3-V01-first-day-L")
        app.openDiaryEditorFromHome()
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textViews["diary-editor-text"].typeText("لن يحفظ")
        // 14 Nov: «تمّ» writes what is there; emptying the draft first is how a writer discards it.
        app.textViews["diary-editor-text"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        app.buttons["diary-editor-save"].tap()
        app.closeDiaryDay()
        // An empty day offers one «اكتب» action and no page to read; the closed draft wrote nothing visible.
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["لن يحفظ"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
