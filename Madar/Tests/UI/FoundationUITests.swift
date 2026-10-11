import XCTest

@MainActor final class FoundationUITests: XCTestCase {
    func test_M0S2_CaptureFocusedSecureKeyboard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); openBackupSettings(app)
        defer { app.terminate() }
        let password = app.secureTextFields["backup-password"]
        scrollTo(password, in: app)
        password.tap()

        // Capture the untouched, isolated fixture before sending any input.
        attachScreenshot(app, named: "M0-backup-focused-empty-keyboard-L")
        print("M0 focused secure field hierarchy:\n\(app.debugDescription)")
        let keyboards = app.keyboards.allElementsBoundByIndex
        print("M0 focused secure field keyboard count: \(keyboards.count)")
        for (index, keyboard) in keyboards.enumerated() {
            let labels = keyboard.keys.allElementsBoundByIndex.map { $0.label }
            print("M0 focused secure field keyboard \(index) native key labels: \(labels)")
            print("M0 focused secure field keyboard \(index) hierarchy:\n\(keyboard.debugDescription)")
        }
    }
    func test_M0S2_NativeArabicKeyAndTypingTransport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); openBackupSettings(app)
        defer { app.terminate() }
        let password = app.secureTextFields["backup-password"]
        let export = app.buttons["backup-now"]
        scrollTo(password, in: app)
        password.tap()
        attachScreenshot(app, named: "M0-backup-native-key-empty-L")

        // The root's focus-only capture observed this Arabic key. The software
        // keyboard must actually be onscreen; an offscreen AX preview is insufficient.
        let nativeKey = app.keyboards.keys["ت"]
        guard nativeKey.waitForExistence(timeout: 3), nativeKey.isHittable,
              app.frame.contains(nativeKey.frame) else {
            print("M0 native Arabic key unavailable:\n\(app.debugDescription)")
            XCTFail("Show the Arabic software keyboard and disable simulated hardware keyboard before this probe.")
            return
        }

        nativeKey.tap()
        let afterNativeTap = export.value as? String
        print("M0 secure input after native Arabic key tap: \(afterNativeTap ?? "no diagnostic")")
        attachScreenshot(app, named: "M0-backup-native-Arabic-key-L")
        XCTAssertEqual(afterNativeTap, "passphrase-count=1;confirmation-count=0;matches=false;busy=false")

        password.typeText("ت")
        let afterArabicTransport = export.value as? String
        print("M0 secure input after Arabic typeText: \(afterArabicTransport ?? "no diagnostic")")
        attachScreenshot(app, named: "M0-backup-Arabic-typing-transport-L")
        XCTAssertEqual(afterArabicTransport, "passphrase-count=2;confirmation-count=0;matches=false;busy=false")

        password.typeText("t")
        let afterLatinTransport = export.value as? String
        print("M0 secure input after Latin typeText: \(afterLatinTransport ?? "no diagnostic")")
        attachScreenshot(app, named: "M0-backup-Latin-typing-transport-L")
        XCTAssertEqual(afterLatinTransport, "passphrase-count=3;confirmation-count=0;matches=false;busy=false")
    }
    func test_M0S2_SecureInputCharacterClasses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); openBackupSettings(app)
        let password = app.secureTextFields["backup-password"]
        let export = app.buttons["backup-now"]
        scrollTo(password, in: app)
        password.tap()
        var observations: [String] = []
        let samples = [("Latin 1", "t"), ("punctuation 1", "-"), ("Latin 2", "e"), ("punctuation 2", "!"), ("Arabic", "س")]
        for (label, character) in samples {
            password.typeText(character)
            let diagnostic = export.value as? String ?? "no diagnostic"
            print("Secure UI input class \(label): \(diagnostic)")
            observations.append(diagnostic)
        }
        let expected = (1...samples.count).map { "passphrase-count=\($0);confirmation-count=0;matches=false;busy=false" }
        XCTAssertEqual(observations, expected, "Every supported character must be retained by actual UI input.")
        app.terminate()
    }
    func test_M0S2_SecurePasswordTypingTransport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); openBackupSettings(app)
        let password = app.secureTextFields["backup-password"]
        let export = app.buttons["backup-now"]
        scrollTo(password, in: app)
        password.tap()
        for (index, character) in "test-only-passphrase".enumerated() {
            password.typeText(String(character))
            let expectedCount = index + 1
            let diagnostic = export.value as? String
            print("Secure UI input stage \(expectedCount): \(diagnostic ?? "no diagnostic")")
            XCTAssertEqual(diagnostic, "passphrase-count=\(expectedCount);confirmation-count=0;matches=false;busy=false")
        }
        attachScreenshot(app, named: "M0-backup-character-transport-L")
        app.terminate()
    }
    func test_M0S2_BackupPasswordConfirmationAndFixtureIsolation() throws {
        continueAfterFailure = false
        // A second fresh fixture must not inherit the first fixture's configured Keychain key.
        for size in ["L", "AX3"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); openBackupSettings(app)
            XCTAssertTrue(app.staticTexts["backup-key-setup"].waitForExistence(timeout: 10), app.debugDescription)
            let passphrase = "test-only-passphrase"
            let export = app.buttons["backup-now"]
            let password = app.secureTextFields["backup-password"]
            scrollTo(password, in: app)
            password.tap(); password.typeText(passphrase)
            attachScreenshot(app, named: "M0-backup-before-confirmation-\(size)")
            XCTAssertEqual(export.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=0;matches=false;busy=false", "Validate first-field input before submitting or changing focus.")
            // Exercise native Next while the keyboard changes the Form's visible area,
            // instead of tapping a row whose frame may be outside that area.
            password.typeText("\n")
            let confirmation = app.secureTextFields["backup-password-confirmation"]
            let mismatch = passphrase + "!"
            confirmation.typeText(mismatch)
            XCTAssertEqual(export.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=\(mismatch.count);matches=false;busy=false")
            XCTAssertFalse(export.isEnabled, "A mismatched confirmation must not permit export.")
            // The insertion point is still at the end; remove only the extra mismatching
            // character. Re-tapping a populated secure field can move the insertion point.
            confirmation.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(export.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=\(passphrase.count);matches=true;busy=false")
            app.buttons["backup-keyboard-done"].tap()
            scrollTo(export, in: app)
            XCTAssertTrue(export.isEnabled, app.debugDescription); export.tap()
            let share = app.buttons["backup-export"]
            XCTAssertTrue(share.waitForExistence(timeout: 20), app.debugDescription)
            scrollTo(share, in: app)
            attachScreenshot(app, named: "M0-backup-native-export-\(size)")

            app.terminate(); app.launch(); openBackupSettings(app)
            XCTAssertTrue(app.buttons["backup-schedule"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.staticTexts["backup-key-setup"].exists, "The same fixture must retain its configured key after relaunch.")
            app.terminate()
        }
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
    private func openBackupSettings(_ app: XCUIApplication) {
        finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let link = app.buttons["backup-settings-link"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.secureTextFields["backup-password"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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
