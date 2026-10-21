import XCTest
import notify

@MainActor final class DiaryLockPreferenceUITests: XCTestCase {
    func testFreshInstallStartsAtTheSingleAppFaceIDGate() throws {
        continueAfterFailure = false
        // Unenrolled, the gate stays on its own branded screen instead of the system prompt.
        setFaceIDEnrolled(false)
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
        XCTAssertFalse(app.buttons["tab-notes"].exists, "Room shortcuts must wait behind the single app gate")
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
        app.buttons["tab-customize"].tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("القفل")
        let none = app.buttons["option-core.faceIDLock-none"]
        XCTAssertTrue(none.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(none.isSelected, "This simulator fixture explicitly opts out of the app lock.")
        XCTAssertTrue(app.buttons["option-core.faceIDLock-app"].exists)
        XCTAssertFalse(app.buttons["option-core.faceIDLock-notesOnly"].exists)
        capture(app, "UX-01-lock-options-L")
    }
    /// Regression: a successful match used to leave «محتوى مدار محمي» on screen for good,
    /// because unlocking dismantled the scene privacy bridge and disconnected the lock.
    func testFaceIDMatchOpensMadarAndSurvivesAppSwitch() throws {
        continueAfterFailure = false
        setFaceIDEnrolled(true)
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_PRESERVE_FACE_ID_DEFAULT": "1",
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light"
        ]
        app.launch()
        // While the system prompt is up the scene is inactive, so the privacy cover sits above the gate.
        let lobby = app.descendants(matching: .any)["foundation-tab"]
        let gate = app.descendants(matching: .any)["protected-lock-screen"]
        let cover = app.windows["scene-privacy-cover"].staticTexts["محتوى مدار محمي"]
        XCTAssertTrue(gate.waitForExistence(timeout: 20) || cover.exists, app.debugDescription)
        XCTAssertFalse(lobby.exists, "Rooms wait behind the gate until the match")
        let start = app.buttons["first-run-continue"]
        // The system prompt appears a moment after launch; repeat the simulated match until it lands.
        for _ in 0..<15 where !start.exists {
            notify_post("com.apple.BiometricKit_Sim.pearl.match")
            _ = start.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(start.exists, "A Face ID match must open Madar. \(app.debugDescription)")
        XCTAssertFalse(cover.exists, "The privacy cover must lift after the match")
        capture(app, "UX-01-face-id-unlocked-L")
        if app.buttons["first-run-skip"].exists { app.buttons["first-run-skip"].tap() }
        if start.exists { start.tap(); if start.exists && start.isHittable { start.tap() } }
        XCTAssertTrue(lobby.waitForExistence(timeout: 20), app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(lobby.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(cover.waitForExistence(timeout: 2), "Returning to the app must not strand the privacy cover")
        capture(app, "UX-01-face-id-lobby-L")
    }
    private func setFaceIDEnrolled(_ enrolled: Bool) {
        var token: Int32 = 0
        notify_register_check("com.apple.BiometricKit.enrollmentChanged", &token)
        notify_set_state(token, enrolled ? 1 : 0)
        notify_post("com.apple.BiometricKit.enrollmentChanged")
        notify_cancel(token)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
