import XCTest

@MainActor final class FoundationUITests: XCTestCase {
    func testBackupExportAndLocalSyncThroughNativeSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch(); finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let backupLink = app.buttons["backup-settings-link"]
        for _ in 0..<8 { if backupLink.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(backupLink.isHittable, app.debugDescription); backupLink.tap()
        let password = app.secureTextFields["backup-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10), app.debugDescription)
        password.tap(); password.typeText("test-only-passphrase")
        let confirmation = app.secureTextFields["backup-password-confirmation"]
        confirmation.tap(); confirmation.typeText("test-only-passphrase")
        app.buttons["backup-keyboard-done"].tap()
        let export = app.buttons["backup-now"]
        if !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isEnabled); export.tap()
        let share = app.buttons["backup-export"]
        XCTAssertTrue(share.waitForExistence(timeout: 20), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "M0-backup-native-export"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let sync = app.buttons["sync-settings-link"]
        for _ in 0..<8 { if sync.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(sync.isHittable, app.debugDescription); sync.tap()
        XCTAssertTrue(app.staticTexts["sync-status"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["sync-status"].label, "هذه النسخة تعمل محليًا؛ اتصال iCloud غير مهيّأ.")
        XCTAssertFalse(app.switches["sync-enabled"].isEnabled)
    }

    func testWholeAppLockPersistsWithoutRenderingProtectedContent() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch(); finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let search = app.textFields["settings-search"]
        search.tap(); search.typeText("core.faceIDLock\n")
        let wholeApp = app.buttons["option-core.faceIDLock-app"]
        XCTAssertTrue(wholeApp.waitForExistence(timeout: 10)); wholeApp.tap()
        XCTAssertTrue(app.buttons["lock-authenticate"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-button"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["lock-authenticate"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-button"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "M0-lock-native-persisted"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    /// The host script supplies a real simctl URL after this test terminates the app.
    func testColdSettingsLinkOpenedByOS() throws {
        guard ProcessInfo.processInfo.environment["MADAR_TEST_EXTERNAL_LINK"] == "1" else {
            throw XCTSkip("Run scripts/deep-link-test.py for the external URL orchestration.")
        }
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.buttons["إلغاء"].exists { system.buttons["إلغاء"].tap() }
        let app = XCUIApplication()
        app.launch(); finishOnboarding(app)
        app.terminate()
        NSLog("MADAR_DEEP_LINK_READY")
        let open = system.buttons["فتح"]
        if open.waitForExistence(timeout: 20) { open.tap() }
        XCTAssertTrue(app.buttons["option-core.theme-dark"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.textFields["settings-search"].value as? String, "الوضع")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "M0-deep-link-cold-settings"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testFirstRunAndSettingsRenderWithoutUnbuiltRooms() throws {
        let app = XCUIApplication()
        app.launch()
        finishOnboarding(app)
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["الصلاة"].exists)
        XCTAssertFalse(app.buttons["القرآن"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "M0-iPhone17Pro-RTL-light-L"; shot.lifetime = .keepAlways; add(shot)
        settings.tap()
        XCTAssertTrue(app.buttons["reset-settings"].waitForExistence(timeout: 10), app.debugDescription)
        let settingsShot = XCTAttachment(screenshot: app.screenshot()); settingsShot.name = "M0-customize-RTL"; settingsShot.lifetime = .keepAlways; add(settingsShot)
    }
    func testLightDarkAndAccessibilityScreenshots() throws {
        for theme in ["light", "dark"] {
            for size in ["L", "AX3", "AX5"] {
                let app = XCUIApplication()
                app.launchEnvironment["MADAR_UI_THEME"] = theme
                app.launchEnvironment["MADAR_UI_SIZE"] = size
                app.launch()
                finishOnboarding(app)
                XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15))
                let home = XCTAttachment(screenshot: app.screenshot()); home.name = "M0-home-\(theme)-\(size)"; home.lifetime = .keepAlways; add(home)
                app.buttons["settings-button"].tap()
                XCTAssertTrue(app.buttons["reset-settings"].waitForExistence(timeout: 10))
                let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "M0-settings-\(theme)-\(size)"; settings.lifetime = .keepAlways; add(settings)
                app.terminate()
            }
        }
    }
    func testThemePersistenceResetAndUndoThroughUI() throws {
        let app = XCUIApplication()
        app.launch(); finishOnboarding(app)
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("core.theme\n")
        // The real store survives repeat runs; choose a known different starting value.
        let light = app.buttons["option-core.theme-light"]
        XCTAssertTrue(light.waitForExistence(timeout: 10))
        light.tap()
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: light)
        waitForExpectations(timeout: 10)
        let dark = app.buttons["option-core.theme-dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 10))
        dark.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let newSearch = app.textFields["settings-search"]
        newSearch.tap(); newSearch.typeText("core.theme\n")
        XCTAssertTrue(app.buttons["option-core.theme-dark"].isSelected)
        app.buttons["reset-settings"].tap()
        app.buttons["أعِد الافتراضي"].firstMatch.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["option-core.theme-auto"].isSelected)
        app.buttons["undo-button"].tap()
        let selectedAgain = app.buttons["option-core.theme-dark"]
        let predicate = NSPredicate(format: "selected == true")
        expectation(for: predicate, evaluatedWith: selectedAgain)
        waitForExpectations(timeout: 10)
    }
    func testSharedComponentsAtEveryRequiredSizeAndMode() throws {
        for theme in ["light", "dark"] {
            for size in ["L", "AX3", "AX5"] {
                let app = XCUIApplication()
                app.launchEnvironment = ["MADAR_UI_GALLERY": "1", "MADAR_UI_THEME": theme, "MADAR_UI_SIZE": size]
                app.launch()
                XCTAssertTrue(app.staticTexts["مكونات مدار"].waitForExistence(timeout: 10))
                let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "M0-components-\(theme)-\(size)"; screenshot.lifetime = .keepAlways; add(screenshot)
                app.swipeUp()
                let lower = XCTAttachment(screenshot: app.screenshot()); lower.name = "M0-components-lower-\(theme)-\(size)"; lower.lifetime = .keepAlways; add(lower)
                app.terminate()
            }
        }
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) {
            start.tap()
            if start.exists && start.isHittable { start.tap() }
        }
    }
}
