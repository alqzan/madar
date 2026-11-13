import XCTest

@MainActor final class DiaryMarginUITests: XCTestCase {
    func testDeletingOriginalKeepsMarginAndUndoRestoresIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "margin", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        // 12 Nov: the home has no margin shape; a past year's card opens that day, and its «اكتب في هامشها» writes the margin.
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["diary-year-2024-10-15"].tap()
        let originalText = "مشينا بعد المغرب، والجو صار يحتمل."
        XCTAssertTrue(app.staticTexts[originalText].waitForExistence(timeout: 8))
        app.buttons["diary-day-write"].tap()
        let editor = app.textViews["diary-editor-text"]; XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let marginText = "ما زلت أذكر ذلك المساء."
        editor.typeText(marginText)
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marginText)).firstMatch.waitForExistence(timeout: 10))
        app.closeDiaryDay()
        app.buttons["diary-today"].tap()
        let targetText = "ما زال في اليوم متّسع."
        let target = app.staticTexts.matching(identifier: "diary-day-line").matching(NSPredicate(format: "label == %@", targetText)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let marginReference = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", marginText)).firstMatch
        XCTAssertTrue(marginReference.exists)
        capture(app, "M3-J05-delete-before-L")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.1)
        let deleteAction = app.buttons["diary-line-delete"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()
        // Quick win 4: deleting a line needs no confirmation; the undo badge below is the safety net.
        XCTAssertTrue(target.waitForNonExistence(timeout: 8))
        XCTAssertTrue(marginReference.waitForExistence(timeout: 8))
        capture(app, "M3-J05-delete-margin-remains-L")

        let undo = app.descendants(matching: .any)["diary-day-undo"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        XCTAssertTrue(marginReference.exists)
        capture(app, "M3-J05-delete-undo-L")
    }

    func testMarginHasOriginalDatedReplyAndTodayReferenceAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "margin", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].waitForExistence(timeout: 25), app.debugDescription)
        capture(app, "M3-V03-margin-L")
        app.buttons["diary-year-2024-10-15"].tap()
        XCTAssertTrue(app.staticTexts["مشينا بعد المغرب، والجو صار يحتمل."].waitForExistence(timeout: 8))
        app.buttons["diary-day-write"].tap()
        let text = app.textViews["diary-editor-text"]; XCTAssertTrue(text.waitForExistence(timeout: 10)); text.typeText("ما زلت أذكر ذلك المساء.")
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ما زلت أذكر ذلك المساء.")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "M3-V03-dated-reply-L")
        app.closeDiaryDay()
        app.buttons["diary-today"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ما زلت أذكر ذلك المساء.")).firstMatch.waitForExistence(timeout: 10))
        app.closeDiaryDay()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["diary-year-2024-10-15"].waitForExistence(timeout: 25)); app.buttons["diary-year-2024-10-15"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ما زلت أذكر ذلك المساء.")).firstMatch.waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
