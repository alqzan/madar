import XCTest

@MainActor final class DiaryLockPreferenceUITests: XCTestCase {
    func testFreshInstallStartsAtTheSingleAppFaceIDGate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_PRESERVE_FACE_ID_DEFAULT": "1",
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light"
        ]
        app.launch()
        let gate = app.descendants(matching: .any)["protected-lock-screen"]
        XCTAssertTrue(gate.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["scene-lock-authenticate"].exists, "The app's own Face ID gate should own the active locked screen")
        XCTAssertFalse(app.buttons["tab-foundation"].exists, "Room navigation must wait behind the single app gate")
        XCTAssertFalse(app.buttons["tab-mihbara"].exists, "Room shortcuts must wait behind the single app gate")
        capture(app, "UX-01-face-id-gate-L")
    }

    func testDiaryOpensAndOnlyWholeAppLockIsOffered() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 3) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 3) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        let notes = app.buttons["tab-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 20), app.debugDescription); notes.tap()
        XCTAssertTrue(app.buttons["diary-welcome-next"].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.buttons["diary-welcome-next"].tap() }
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["المذكرات مقفلة"].exists)
        capture(app, "UX-01-diary-L")
        app.tabBars.buttons["خصّص"].tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("القفل")
        let none = app.buttons["option-core.faceIDLock-none"]
        XCTAssertTrue(none.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(none.isSelected, "This simulator fixture explicitly opts out of the app lock.")
        XCTAssertTrue(app.buttons["option-core.faceIDLock-app"].exists)
        XCTAssertFalse(app.buttons["option-core.faceIDLock-notesOnly"].exists)
        capture(app, "UX-01-lock-options-L")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
