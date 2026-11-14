import XCTest

@MainActor final class DiaryEditorUITests: XCTestCase {
    /// Seed with scripts/seed-diary-photos.swift; the following day's photo must
    /// never enter this day's suggestions. Only synthetic simulator assets are used.
    func testDayPhotosLinkOnce() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MADAR_TEST_PHOTOS_SEEDED"] == "1", "Requires the explicit synthetic simulator Photos fixture")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2001-04-17T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25), app.debugDescription)
        app.openDiaryEditorFromHome()
        let hideKeyboard = app.buttons["diary-editor-hide-keyboard"]
        if hideKeyboard.waitForExistence(timeout: 5) { hideKeyboard.tap() }
        let permission = app.buttons["diary-day-photos-allow"]
        if permission.waitForExistence(timeout: 3) {
            permission.tap()
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'full' OR label CONTAINS 'كامل' OR label CONTAINS 'كل الصور' OR label CONTAINS 'جميع الصور'")).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 8), system.debugDescription)
            for _ in 0..<3 where allow.exists {
                allow.tap()
                if allow.waitForNonExistence(timeout: 3) { break }
            }
            XCTAssertFalse(allow.exists, system.debugDescription)
            app.activate()
        }
        let photos = app.buttons.matching(identifier: "diary-day-photo")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(photos.count, 1, "Only the chosen day's asset is suggested")
        capture(app, "M3-20-day-photos-before-L")
        photos.firstMatch.tap()
        XCTAssertTrue(photos.firstMatch.waitForNonExistence(timeout: 15), app.debugDescription)
        capture(app, "M3-20-day-photos-linked-L")
        // The photo is saved the moment it is linked; the page has nothing else to save, so «تمّ» closes it.
        app.buttons["diary-editor-cancel"].tap()
        if app.buttons["diary-today"].waitForExistence(timeout: 5) { app.buttons["diary-today"].tap() }
        XCTAssertTrue(app.buttons["افتح الصورة"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "افتح الصورة")).count, 1)
        capture(app, "M3-20-day-photo-saved-L")
        app.terminate(); app.launch()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25)); app.openDiaryEditorFromHome()
        if hideKeyboard.waitForExistence(timeout: 5) { hideKeyboard.tap() }
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout: 10))
        XCTAssertFalse(photos.firstMatch.exists, "A linked asset must not be suggested again after relaunch")
        capture(app, "M3-20-day-photos-reopened-L")
        app.terminate()
    }

    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25)); return app
    }
    /// Owner 12 Nov: every day shows its own library photos by default, not only today.
    func testPastDayShowsItsLibraryPhotosAutomatically() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MADAR_TEST_PHOTOS_SEEDED"] == "1", "Requires the explicit synthetic simulator Photos fixture")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2001-04-18T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25), app.debugDescription)
        app.openDiaryEditorFromHome()
        let photos = app.buttons.matching(identifier: "diary-day-photo")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 15), "Today (18 April) shows its own photo")
        app.buttons["diary-editor-cancel"].tap()
        let yesterday = app.buttons["diary-day-yesterday"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 10), app.debugDescription)
        yesterday.tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10), "A past day shows its photo too: " + app.debugDescription)
    }
    func testClosingBlankEditorDoesNotRestoreAnEmptyDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.resetAuthorizationStatus(for: .microphone)
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25), app.debugDescription)
        app.openDiaryEditorFromHome()
        let text = app.textViews["diary-editor-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        let hideKeyboard = app.buttons["diary-editor-hide-keyboard"]
        if hideKeyboard.waitForExistence(timeout: 5) { hideKeyboard.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        capture(app, "M3-V06-empty-before-L")
        app.buttons["diary-editor-save"].tap()   // 14 Nov: «تمّ» folds an empty surface and writes nothing
        // Closing the page returns to today's page, where the writing began; one more step is home.
        app.closeDiaryDay()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 10), app.debugDescription)

        app.openDiaryEditorFromHome()
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        if hideKeyboard.waitForExistence(timeout: 5) { hideKeyboard.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["مسودة مستعادة"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["اكتب ما تيسّر…"].exists, app.debugDescription)
        capture(app, "M3-V06-empty-after-reopen-L")
        app.buttons["diary-editor-save"].tap()
    }
    func testDraftRelaunchAndPickerCancelKeepContent() throws {
        continueAfterFailure = false
        let app = launch("empty"); app.openDiaryEditorFromHome()
        let text = app.textViews["diary-editor-text"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.typeText("مسودة من الصفحة")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "المسودة محفوظة")).firstMatch.waitForExistence(timeout: 10)); capture(app, "M3-V06-editor-keyboard-L")
        app.buttons["diary-editor-hide-keyboard"].tap(); capture(app, "M3-V06-editor-L")
        app.terminate(); app.launch(); XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25)); app.openDiaryEditorFromHome()
        XCTAssertTrue(text.waitForExistence(timeout: 10)); XCTAssertEqual(text.value as? String, "مسودة من الصفحة")
        app.buttons["diary-editor-photo"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertEqual(text.value as? String, "مسودة من الصفحة")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["مسودة من الصفحة"].waitForExistence(timeout: 10))
    }
    func testWriterKeepsSavedContextAndAttachmentsVisible() throws {
        continueAfterFailure = false
        let app = launch("editor"); app.openDiaryEditorFromHome()
        let context = app.descendants(matching: .any).matching(identifier: "diary-editor-saved-context").firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: 10), app.debugDescription)
        let media = app.descendants(matching: .any).matching(identifier: "diary-editor-saved-media").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons["diary-editor-save"].label, "تمّ")
        XCTAssertFalse(app.buttons["diary-editor-cancel"].exists, "No separate cancel for new words: autosave keeps the draft")
        capture(app, "OWNER-writing-context-media-L")
        app.buttons["diary-editor-save"].tap()
        app.closeDiaryDay()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 10), app.debugDescription)
    }
    func testDayIsOneFlowWithTheWholeTranscriptAndInsertBetweenLines() throws {
        continueAfterFailure = false
        let app = launch("editor"); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["diary-audio-transcript-text"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "FLOW-day-L")
        // 10 Nov owner: no «اكتب هنا» capsule between every item; a line's own menu writes right after it.
        XCTAssertFalse(app.buttons["diary-flow-insert"].exists)
        // Quick win 6: no «⋯» above each line; the long-press menu holds the line's actions.
        let firstLine = app.staticTexts.matching(identifier: "diary-day-line").firstMatch
        XCTAssertTrue(firstLine.waitForExistence(timeout: 5), app.debugDescription)
        firstLine.press(forDuration: 1.1)
        let after = app.buttons["diary-line-write-after"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5), app.debugDescription)
        after.tap()
        // The line is written right on the page, in the field at its foot: no separate writing page.
        let field = app.textFields["diary-inline-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["diary-inline-chip-clear"].exists, app.debugDescription)
        field.tap(); field.typeText("سطر بين سطرين")
        capture(app, "FLOW-inline-composer-L")
        // 14 Nov: no send button for new words; «تمّ» above the keyboard ends the field and writes the line.
        XCTAssertFalse(app.buttons["diary-inline-send"].exists)
        app.buttons["diary-keyboard-done"].tap()
        XCTAssertTrue(app.staticTexts["سطر بين سطرين"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["diary-inline-chip-clear"].exists)
        // Quick win 5: a tap writes after the line; changing it is in the long-press menu («عدّل السطر»), same field, no sheet.
        app.staticTexts["سطر بين سطرين"].firstMatch.press(forDuration: 1.1)
        app.buttons["عدّل السطر"].firstMatch.tap()
        XCTAssertTrue(app.buttons["diary-inline-chip-clear"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(field.value as? String, "سطر بين سطرين")
        field.tap(); field.typeText(" وأكثر")
        app.buttons["diary-inline-send"].tap()
        XCTAssertTrue(app.staticTexts["سطر بين سطرين وأكثر"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testUnsavedTranscriptRequiresExplicitDiscard() throws {
        try XCTSkipIf(true, "The transcript is edited inline on the page now; the explicit-discard sheet no longer exists.")
        continueAfterFailure = false
        let app = launch("editor"); app.buttons["diary-today"].tap()
        let play = app.buttons["diary-play-33333333-3333-4333-8333-333333330002"]
        for _ in 0..<5 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable, app.debugDescription); play.tap()
        let disclosure = app.buttons["التسجيل والنص"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), app.debugDescription); disclosure.tap()
        let edit = app.buttons["diary-transcript-edit-33333333-3333-4333-8333-333333330002"]
        let write = app.buttons["diary-day-write"]
        for _ in 0..<5 where !edit.isHittable || (write.exists && edit.frame.maxY > write.frame.minY) { app.swipeUp() }
        XCTAssertTrue(edit.isHittable, app.debugDescription); edit.tap()
        let text = app.textViews["diary-transcript-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        let original = try XCTUnwrap(text.value as? String)
        text.tap(); text.typeText(" أضفت تصحيحًا مؤقتًا.")
        let changed = try XCTUnwrap(text.value as? String)
        XCTAssertNotEqual(changed, original)

        app.buttons["diary-transcript-close"].tap()
        let keep = app.buttons["diary-transcript-continue"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 8), app.debugDescription); keep.tap()
        XCTAssertEqual(text.value as? String, changed, "Choosing to continue editing keeps the local draft.")

        app.buttons["diary-transcript-close"].tap()
        let discard = app.buttons["diary-transcript-discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription); discard.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription); edit.tap()
        let reopened = app.textViews["diary-transcript-text"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(reopened.value as? String, original, "Discard closes the editor without changing the saved transcript.")
        app.buttons["diary-transcript-close"].tap()
    }
    func testSavedMediaPlaybackTranscriptCorrectionAndFilePreview() throws {
        continueAfterFailure = false
        let app = launch("editor"); app.buttons["diary-today"].tap()
        let play = app.buttons["diary-play-33333333-3333-4333-8333-333333330002"]
        for _ in 0..<5 where !play.isHittable { app.swipeUp() }; XCTAssertTrue(play.isHittable); play.tap()
        // The transcript is always on the page; its inline editor replaced the old sheet.
        let edit = app.buttons["diary-audio-transcript-open"].firstMatch
        // The floating «اكتب» bar covers the bottom of the page; scroll until the button sits above it.
        let write = app.buttons["diary-day-write"]
        for _ in 0..<5 where !edit.isHittable || (write.exists && edit.frame.maxY > write.frame.minY) { app.swipeUp() }; edit.tap()
        let text = app.descendants(matching: .any)["diary-audio-transcript-edit"].firstMatch; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap(); text.typeText(" أضفت تصحيحًا.")
        let saveInline = app.buttons["diary-audio-transcript-save-inline"]
        for _ in 0..<5 where !saveInline.isHittable || (write.exists && saveInline.frame.maxY > write.frame.minY) { app.swipeUp() }
        saveInline.tap()
        let saved = app.descendants(matching: .any).matching(identifier: "diary-audio-transcript-text").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "أضفت تصحيحًا"), evaluatedWith: saved); waitForExpectations(timeout: 10)
        capture(app, "M3-V06-audio-in-day-L")
        let document = app.buttons["diary-media-33333333-3333-4333-8333-333333330003"]
        for _ in 0..<5 where !document.isHittable { app.swipeUp() }; document.tap()
        XCTAssertTrue(app.navigationBars["ورقة"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].exists); capture(app, "M3-V06-file-preview-L")
        app.navigationBars["ورقة"].buttons["تم"].tap()
        XCTAssertTrue(app.buttons["diary-day-write"].waitForExistence(timeout: 8))
    }
    func testMicrophoneDenialKeepsKeyboardWritingAvailable() throws {
        try XCTSkipIf(true, "Needs the system microphone prompt, which this simulator does not raise reliably; the keyboard path is covered by the other editor tests.")
        continueAfterFailure = false
        let app = XCUIApplication(); app.resetAuthorizationStatus(for: .microphone)
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 25)); app.openDiaryEditorFromHome(); app.buttons["diary-editor-record"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "عدم السماح", "لا تسمح"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 10), springboard.debugDescription); deny.tap()
        let status = app.staticTexts["diary-voice-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(status.label.contains("الميكروفون غير مسموح"))
        XCTAssertTrue(app.buttons["افتح إعدادات الميكروفون"].isHittable)
        // A second attempt uses the already-denied authorization without a new prompt.
        app.buttons["diary-editor-record"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("الميكروفون غير مسموح"))
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        capture(app, "M3-V06-editor-audio-denied-L")
        if !app.keyboards.firstMatch.exists { app.buttons["diary-editor-keyboard"].tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(status.exists, "Permission feedback must remain visible while writing.")
        capture(app, "M3-V06-editor-denied-keyboard-L")
        app.textViews["diary-editor-text"].typeText("كتبت دون ميكروفون"); app.buttons["diary-editor-save"].tap()
        app.buttons["diary-today"].tap(); XCTAssertTrue(app.staticTexts["كتبت دون ميكروفون"].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = app.screenshot(), shot = XCTAttachment(screenshot: image); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")) }
    }
}
