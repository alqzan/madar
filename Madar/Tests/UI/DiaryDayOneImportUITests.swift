import XCTest

/// M3-V09: settings «النقل» → «من داي ون» → bundled synthetic export → preview → «استورد» → result → open day → undo → re-import preview.
@MainActor final class DiaryDayOneImportUITests: XCTestCase {
    func testPreviewConfirmOpenDayUndoAndReimport() throws {
        continueAfterFailure = false
        let zip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dayone-synthetic", withExtension: "zip"))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
                                 "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_DAYONE_ZIP_B64": try Data(contentsOf: zip).base64EncodedString()]
        app.launch(); XCTAssertTrue(app.buttons["diary-customize"].waitForExistence(timeout: 25)); app.buttons["diary-customize"].tap()
        let entry = app.buttons["diary-transfer-import"]; XCTAssertTrue(entry.waitForExistence(timeout: 10)); reveal(entry, app); capture(app, "M3-V09-settings-transfer-L"); entry.tap()
        let choose = app.buttons["dayone-choose"]; XCTAssertTrue(choose.waitForExistence(timeout: 10)); capture(app, "M3-V09-import-L")
        choose.tap()
        // Preview: nothing written yet. Five entries over five days; one video missing; three skipped rows.
        let confirm = app.buttons["dayone-confirm"]; XCTAssertTrue(app.descendants(matching: .any)["dayone-preview-entries"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["dayone-preview-entries"].label.contains("٥"))
        XCTAssertTrue(app.descendants(matching: .any)["dayone-preview-days"].label.contains("٥"))
        XCTAssertTrue(app.descendants(matching: .any)["dayone-preview-missing"].exists)
        capture(app, "M3-V09-preview-L")
        reveal(confirm, app); capture(app, "M3-V09-preview-s1-L"); confirm.tap()
        let done = app.descendants(matching: .any)["dayone-done"]; XCTAssertTrue(done.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["dayone-done-added"].label.contains("٥"))
        capture(app, "M3-V09-done-L")
        // The last imported day (London, 15 July 2025) opens with its Day One line and the shared photo.
        let open = app.buttons["dayone-open-day"]; reveal(open, app); open.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "الصورة نفسها مرة أخرى")).firstMatch.waitForExistence(timeout: 15))
        capture(app, "M3-V09-day-L")
        app.swipeDown(velocity: .fast)
        let undo = app.buttons["dayone-undo"]; XCTAssertTrue(undo.waitForExistence(timeout: 10)); reveal(undo, app); undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dayone-undone"].waitForExistence(timeout: 15)); capture(app, "M3-V09-undone-L")
        // Re-import after undo: the same five come back (restored, not duplicated).
        app.buttons["اختر ملفًا"].tap()
        XCTAssertTrue(app.buttons["dayone-confirm"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["dayone-preview-entries"].label.contains("٥"))
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
