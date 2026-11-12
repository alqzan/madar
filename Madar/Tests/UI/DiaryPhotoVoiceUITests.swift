import XCTest

/// Owner 12 Nov evening: a photo opens full size and takes a comment; a recording always shows its title above it, editable.
@MainActor final class DiaryPhotoVoiceUITests: XCTestCase {
    private func openEditorDay() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        let card = app.buttons["diary-today"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.staticTexts["diary-day-title"].waitForExistence(timeout: 10))
        return app
    }

    func testPhotoOpensFullSizeAndTakesAComment() throws {
        continueAfterFailure = false
        let app = openEditorDay()
        let photo = app.buttons["افتح الصورة"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
        photo.tap()
        let open = app.buttons["diary-photo-comment-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["صورة احتفظت بها اليوم."].exists, "The photo's line is its comment")
        open.tap()
        let field = app.descendants(matching: .any)["diary-photo-comment-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(" غروب من الشرفة")
        app.buttons["diary-photo-comment-save"].tap()
        let saved = app.staticTexts["صورة احتفظت بها اليوم. غروب من الشرفة"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "The viewer shows the saved comment: " + app.debugDescription)
        app.buttons["diary-photo-viewer-close"].tap()
        XCTAssertTrue(app.staticTexts["صورة احتفظت بها اليوم. غروب من الشرفة"].waitForExistence(timeout: 10), "The page shows the comment as the photo's line")
        XCTAssertTrue(app.buttons["افتح الصورة"].exists, "Editing the comment keeps the photo on the page")
    }

    func testRecordingTitleIsAlwaysAboveItAndEditable() throws {
        continueAfterFailure = false
        let app = openEditorDay()
        let title = app.buttons["diary-audio-title-open"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(title.label, "أضف عنوانًا للتسجيل")
        title.tap()
        let field = app.textFields["diary-audio-title-edit"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap(); field.typeText("صباح هادئ")
        app.buttons["diary-audio-title-save"].tap()
        XCTAssertTrue(app.buttons["diary-audio-title-open"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["diary-audio-title-open"].label.contains("صباح هادئ"), app.debugDescription)
        let transcript = app.staticTexts["diary-audio-transcript-text"]
        XCTAssertTrue(transcript.exists, "The whole transcript stays on the page under its recording")
    }
}
