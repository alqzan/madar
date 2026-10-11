import XCTest

@MainActor final class FoundationUITests: XCTestCase {
    func test_M0T08_PlainExportNativeShareAtDefaultAX3AndDark() throws {
        continueAfterFailure = false
        for (size, theme) in [("L", "light"), ("AX3", "light"), ("L", "dark")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launchEnvironment["MADAR_UI_THEME"] = theme
            app.launch(); openBackupSettings(app)
            let export = app.buttons["plain-export-now"]
            XCTAssertTrue(export.waitForExistence(timeout: 10), app.debugDescription)
            scrollTo(export, in: app)
            attachScreenshot(app, named: "M0-plain-export-before-\(theme)-\(size)")
            XCTAssertTrue(export.isEnabled)
            export.tap()
            let share = app.buttons["plain-export-share"]
            XCTAssertTrue(share.waitForExistence(timeout: 20), app.debugDescription)
            scrollTo(share, in: app)
            attachScreenshot(app, named: "M0-plain-export-ready-\(theme)-\(size)")
            share.tap()
            print("M0 plain export native share \(theme)/\(size):\n\(app.debugDescription)")
            // BackupCoordinator names the portable archive Madar-<timestamp>-plain.zip.
            // Native sharing may omit the extension from the displayed item title.
            let file = app.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@", "Madar-", "-plain"
            )).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
            let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Save to Files", "الملفات"
            )).firstMatch
            XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10), app.debugDescription)
            attachScreenshot(app, named: "M0-plain-export-native-share-\(theme)-\(size)")
            let dismiss = app.buttons.matching(NSPredicate(
                format: "label IN %@", ["Close", "Cancel", "إغلاق", "إلغاء"]
            )).firstMatch
            if dismiss.exists && dismiss.isHittable { dismiss.tap() }
            else { app.swipeDown() }
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: file)
            waitForExpectations(timeout: 10)
            scrollTo(share, in: app)
            attachScreenshot(app, named: "M0-plain-export-dismissed-\(theme)-\(size)")
            // Sharing/dismissal does not establish a successful write to a Files destination.
            app.terminate()
        }
    }

    func test_M0S2_RU3_CustomizationPluralsAtDefaultAndAX3() throws {
        continueAfterFailure = false
        for size in ["L", "AX3"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); finishOnboarding(app)
            XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
            app.buttons["settings-button"].tap()
            let changes = app.staticTexts["customization-changes"]
            XCTAssertTrue(changes.waitForExistence(timeout: 10))
            XCTAssertEqual(changes.label, "كما اتفقنا")
            attachScreenshot(app, named: "M0-RU3-zero-\(size)")
            let edits = [
                ("core.theme", "light", "تعديل واحد عن المتفق عليه"),
                ("core.firstCalendar", "gregorian", "تعديلان عن المتفق عليه"),
                ("core.numerals", "western", "\u{2068}3\u{2069} تعديلات عن المتفق عليه")
            ]
            for (key, value, expected) in edits {
                let search = app.textFields["settings-search"]
                scrollTo(search, in: app)
                search.tap(); search.typeText(key + "\n")
                let option = app.buttons["option-\(key)-\(value)"]
                XCTAssertTrue(option.waitForExistence(timeout: 10))
                scrollTo(option, in: app); option.tap()
                expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: option)
                waitForExpectations(timeout: 10)
                // The same disposable store verifies persistence; a fresh screen clears search.
                app.terminate(); app.launch(); finishOnboarding(app)
                XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
                app.buttons["settings-button"].tap()
                XCTAssertTrue(changes.waitForExistence(timeout: 10))
                XCTAssertEqual(changes.label, expected)
                attachScreenshot(app, named: "M0-RU3-\(key)-\(size)")
            }
            app.terminate()
        }
    }

    func test_M0S2_CutSettingsAndDeferredEntryPointsStayHidden() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        let hiddenQueries = ["core.fontScale", "core.motion", "core.roomIdentity", "tabbar.style", "tabbar.labels", "tabbar.openOn", "tabbar.minimizeOnScroll", "الأنماط", "المزامنة"]
        // Relaunch keeps the same disposable store but gives every query a clean search field.
        for query in hiddenQueries + ["core.theme"] {
            app.launch(); finishOnboarding(app)
            XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
            app.buttons["settings-button"].tap()
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["sync-settings-link"].exists)
            XCTAssertFalse(app.buttons["الأنماط المحفوظة"].exists)
            XCTAssertFalse(app.staticTexts["الشريط السفلي"].exists)
            search.tap(); search.typeText(query + "\n")
            XCTAssertEqual(search.value as? String, query)
            if query == "core.theme" {
                XCTAssertTrue(app.buttons["option-core.theme-auto"].waitForExistence(timeout: 10), "A shipped setting must remain searchable.")
            } else {
                let options = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "option-"))
                let controls = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "setting-"))
                XCTAssertEqual(options.count, 0, query)
                XCTAssertEqual(controls.count, 0, query)
                XCTAssertFalse(app.buttons["sync-settings-link"].exists, query)
                XCTAssertFalse(app.buttons["الأنماط المحفوظة"].exists, query)
            }
            app.terminate()
        }
        app.launch(); finishOnboarding(app)
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "M0-native-bar-before-scroll")
        app.swipeUp(); app.swipeUp()
        // Native minimization has no stable public XCTest state; review these two images.
        attachScreenshot(app, named: "M0-native-bar-after-scroll")
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
