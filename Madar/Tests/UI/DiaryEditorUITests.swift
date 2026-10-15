import XCTest

@MainActor final class DiaryEditorUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); return app
    }
    func testDraftRelaunchAndPickerCancelKeepContent() throws {
        continueAfterFailure = false
        let app = launch("empty"); app.buttons["diary-write"].tap()
        let text = app.textViews["diary-editor-text"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.typeText("مسودة من الصفحة")
        XCTAssertTrue(app.staticTexts["المسودة محفوظة"].waitForExistence(timeout: 10)); capture(app, "M3-V06-editor-keyboard-L")
        app.buttons["diary-editor-hide-keyboard"].tap(); capture(app, "M3-V06-editor-L")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); app.buttons["diary-write"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 10)); XCTAssertEqual(text.value as? String, "مسودة من الصفحة")
        app.buttons["diary-editor-photo"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertEqual(text.value as? String, "مسودة من الصفحة")
        app.buttons["diary-editor-save"].tap(); app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts["مسودة من الصفحة"].waitForExistence(timeout: 10))
    }
    func testSavedMediaPlaybackTranscriptCorrectionAndFilePreview() throws {
        continueAfterFailure = false
        let app = launch("editor"); app.buttons["diary-today"].tap()
        let play = app.buttons["diary-play-33333333-3333-4333-8333-333333330002"]
        for _ in 0..<5 where !play.isHittable { app.swipeUp() }; XCTAssertTrue(play.isHittable); play.tap()
        let disclosure = app.buttons["التسجيل والنص"]; XCTAssertTrue(disclosure.waitForExistence(timeout: 5)); disclosure.tap()
        let edit = app.buttons["diary-transcript-edit-33333333-3333-4333-8333-333333330002"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }; edit.tap()
        let text = app.textViews["diary-transcript-text"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap(); text.typeText(" أضفت تصحيحًا.")
        app.buttons["diary-transcript-save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "أضفت تصحيحًا")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "M3-V06-audio-in-day-L")
        let document = app.buttons["diary-media-33333333-3333-4333-8333-333333330003"]
        for _ in 0..<5 where !document.isHittable { app.swipeUp() }; document.tap()
        XCTAssertTrue(app.navigationBars["ورقة"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].exists); capture(app, "M3-V06-file-preview-L")
        app.navigationBars["ورقة"].buttons["تم"].tap()
        XCTAssertTrue(app.buttons["diary-day-write"].waitForExistence(timeout: 8))
    }
    func testMicrophoneDenialKeepsKeyboardWritingAvailable() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.resetAuthorizationStatus(for: .microphone)
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 25)); app.buttons["diary-write"].tap(); app.buttons["diary-editor-record"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "عدم السماح", "لا تسمح"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 10), springboard.debugDescription); deny.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "الميكروفون غير مسموح")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "M3-V06-editor-audio-denied-L")
        app.buttons["diary-editor-keyboard"].tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textViews["diary-editor-text"].typeText("كتبت دون ميكروفون"); app.buttons["diary-editor-save"].tap()
        app.buttons["diary-today"].tap(); XCTAssertTrue(app.staticTexts["كتبت دون ميكروفون"].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
