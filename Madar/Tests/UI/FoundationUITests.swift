import XCTest
import UIKit

@MainActor final class FoundationUITests: XCTestCase {
    func testFirstLaunchTourHighlightsLobbyAndSkipPersistsAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_TOUR": "1"
        ]
        app.launch()

        let title = app.staticTexts["madar-tour-title"]
        XCTAssertFalse(title.exists)
        let name = UIDevice.current.userInterfaceIdiom == .pad ? nil : "سالم"
        saveTourTestCity(in: app, name: name)
        waitForTourTitle("جولة في مدار", in: app)

        let next = app.buttons["madar-tour-next"]
        next.tap()
        waitForTourTitle("ابحث في مدار", in: app)
        let spotlight = app.descendants(matching: .any)["madar-tour-spotlight"].firstMatch
        XCTAssertTrue(spotlight.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.frame.contains(spotlight.frame), app.debugDescription)
        attachScreenshot(app, named: "madar-tour-lobby-search")

        app.buttons["madar-tour-back"].tap()
        waitForTourTitle("جولة في مدار", in: app)
        next.tap()
        waitForTourTitle("ابحث في مدار", in: app)
        next.tap()
        waitForTourTitle("رتّب البهو", in: app)

        app.terminate()
        app.launch()
        waitForTourTitle("رتّب البهو", in: app)

        app.buttons["madar-tour-skip"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), app.debugDescription)
        let lobbySettings = app.buttons["bahw-customize"]
        XCTAssertTrue(lobbySettings.waitForExistence(timeout: 15), app.debugDescription)
        if let name { checkTourTestGreeting(in: app, name: name) }

        app.terminate()
        app.launch()
        XCTAssertTrue(lobbySettings.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["first-run-continue"].exists, app.debugDescription)
        XCTAssertFalse(title.exists, app.debugDescription)
        if let name { checkTourTestGreeting(in: app, name: name) }
        lobbySettings.tap()
        let citySettings = app.buttons["settings-link-اليوم والتقويم"]
        XCTAssertTrue(citySettings.waitForExistence(timeout: 8), app.debugDescription)
        scrollTo(citySettings, in: app)
        citySettings.tap()
        let savedCity = app.buttons["setting-core.homeCity"]
        XCTAssertTrue(savedCity.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(savedCity.label, "مكة المكرمة")
    }

    func testTourCanRestartFromSettingsAndContinueThroughRooms() {
        continueAfterFailure = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if isPad { XCUIDevice.shared.orientation = .portrait } }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_DIARY_ROOT": "1"]
        app.launch()
        saveTourTestCity(in: app)

        let search = app.buttons["bahw-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        let showSidebar = app.buttons["pad-sidebar-show"]
        var foldedForTest = false
        defer { if foldedForTest && showSidebar.isHittable { showSidebar.tap() } }
        if isPad {
            let hideSidebar = app.buttons["pad-sidebar-hide"]
            if hideSidebar.exists {
                hideSidebar.tap()
                foldedForTest = true
            }
            XCTAssertTrue(showSidebar.waitForExistence(timeout: 8), app.debugDescription)
        }

        let searchFrame = search.frame
        let settings = app.buttons["bahw-customize"]
        settings.tap()
        let replay = app.buttons["settings-tour-start"]
        XCTAssertTrue(replay.waitForExistence(timeout: 8), app.debugDescription)
        scrollTo(replay, in: app)
        replay.tap()

        waitForTourTitle("جولة في مدار", in: app)
        let next = app.buttons["madar-tour-next"]
        next.tap()
        waitForTourTitle("ابحث في مدار", in: app)
        let spotlight = app.descendants(matching: .any)["madar-tour-spotlight"].firstMatch
        XCTAssertTrue(spotlight.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(spotlight.frame.midX, searchFrame.midX, accuracy: 8)
        XCTAssertEqual(spotlight.frame.midY, searchFrame.midY, accuracy: 8)

        for step in [
            "رتّب البهو", "إعدادات مدار", "انتقل بين الأقسام",
            "فترات العادات", "أضف عادة", "المصحف", "خطة الحفظ",
            "اكتب يومك", "تصفّح مذكراتك", "سجّل مصروفًا", "حساباتك",
            "أضف كتابًا", "رفوفك", "السنة", "الأيام القادمة",
            "ابحث في الإعدادات", "ودجات البهو", "النسخ والاستعادة"
        ] {
            next.tap()
            waitForTourTitle(step, in: app)
            if step == "انتقل بين الأقسام" {
                XCTAssertTrue(spotlight.waitForExistence(timeout: 8), app.debugDescription)
                if isPad {
                    // The sidebar is 250 points wide; the button that opens it is only 44.
                    XCTAssertGreaterThan(spotlight.frame.width, 240)
                    XCTAssertGreaterThan(spotlight.frame.height, 200)
                    attachScreenshot(app, named: "madar-tour-folded-sidebar")
                } else {
                    XCTAssertGreaterThan(spotlight.frame.width, 200)
                }
            }
            if step == "تصفّح مذكراتك" {
                let instructions = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "«اقرأ»", "«كل الذكريات»")).firstMatch
                XCTAssertTrue(instructions.exists, app.debugDescription)
            }
            if ["أضف عادة", "المصحف", "الأيام القادمة", "النسخ والاستعادة"].contains(step) {
                XCTAssertTrue(spotlight.waitForExistence(timeout: 8), app.debugDescription)
            }
            if step == "المصحف" {
                attachScreenshot(app, named: "madar-tour-quran")
            }
        }
        let title = app.staticTexts["madar-tour-title"]
        XCTAssertEqual(next.label, "تمّ")
        next.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(settings.isHittable, app.debugDescription)
        if isPad {
            XCTAssertTrue(showSidebar.isHittable, "The tour must keep the saved folded preference.")
        } else {
            app.buttons["tab-notes"].tap()
            let more = app.buttons["diary-day-more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
            let archive = app.buttons["diary-all-memories"]
            XCTAssertTrue(archive.waitForExistence(timeout: 10), app.debugDescription)
            archive.tap()
            let displayMenu = app.buttons["diary-hub-view-menu"]
            XCTAssertTrue(displayMenu.waitForExistence(timeout: 10), app.debugDescription)
            app.buttons["diary-hub-close"].tap()
            XCTAssertTrue(displayMenu.waitForNonExistence(timeout: 8), app.debugDescription)
            more.tap()
            XCTAssertTrue(app.buttons["diary-day-read"].waitForExistence(timeout: 5), app.debugDescription)
        }
    }

    func testWelcomeNameCanBeRemovedFromPrivacy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L"]
        app.launch()
        let name = "نور"
        saveTourTestCity(in: app, name: name)
        checkTourTestGreeting(in: app, name: name)

        app.buttons["bahw-customize"].tap()
        let privacy = app.buttons["settings-link-الخصوصية والبحث"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 8), app.debugDescription)
        scrollTo(privacy, in: app)
        privacy.tap()
        let door = app.buttons["settings-link-اسم الترحيب"]
        XCTAssertTrue(door.waitForExistence(timeout: 8), app.debugDescription)
        door.tap()
        let field = app.textFields["welcome-name-setting"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(field.value as? String, name)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count))
        app.buttons["welcome-name-save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), app.debugDescription)

        app.terminate()
        app.launch()
        let greeting = app.staticTexts["bahw-greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(greeting.label.contains(name), app.debugDescription)
    }

    private func saveTourTestCity(in app: XCUIApplication, name: String? = nil) {
        let start = app.buttons["first-run-continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
        attachScreenshot(app, named: "madar-welcome-name")
        if let name {
            let field = app.textFields["first-run-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
            field.typeText(name)
            XCTAssertEqual(field.value as? String, name)
        }
        start.tap()
        let city = app.buttons["first-run-city"]
        XCTAssertTrue(city.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "madar-welcome-city")
        city.tap()
        let makkah = app.buttons["مكة المكرمة"]
        XCTAssertTrue(makkah.waitForExistence(timeout: 8), app.debugDescription)
        makkah.tap()
        XCTAssertTrue(city.waitForNonExistence(timeout: 15), app.debugDescription)
    }

    private func checkTourTestGreeting(in app: XCUIApplication, name: String) {
        let greeting = app.staticTexts["bahw-greeting"]
        let mentionsName = NSPredicate(format: "exists == true AND label CONTAINS %@", name)
        let ready = XCTNSPredicateExpectation(predicate: mentionsName, object: greeting)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, app.debugDescription)
    }

    private func waitForTourTitle(_ expected: String, in app: XCUIApplication) {
        let title = app.staticTexts["madar-tour-title"]
        let matches = NSPredicate(format: "exists == true AND label == %@", expected)
        let ready = XCTNSPredicateExpectation(predicate: matches, object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription)
    }

    func testFirstQuranVisitExplainsItsThreeStepsAndOpensTheRoom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_THEME": "light", "MADAR_UI_INTRO": "1"]
        app.launch(); finishOnboarding(app); app.buttons["tab-quran"].tap()
        let start = app.buttons["intro-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
        for number in 1...3 {
            XCTAssertTrue(app.descendants(matching: .any)["intro-step-\(number)"].firstMatch.exists, app.debugDescription)
        }
        attachScreenshot(app, named: "OWNER-quran-first-visit-guide-L")
        start.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quran-home"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }

    func test_M1T04_NotificationPermissionPrompt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); finishOnboarding(app)
        let settings = app.buttons["tab-customize"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        let notifications = app.buttons["settings-link-الإشعارات"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(notifications, in: app); notifications.tap()
        let request = app.buttons["prayer-notification-permission-request"]
        let deniedSettings = app.buttons["prayer-notification-permission-settings"]
        // The system asks once per install, and the shared simulator cannot reset that answer. Once it is granted,
        // the page must show neither the request nor the system-settings door; the prompt path runs on a fresh install.
        XCTAssertTrue(app.descendants(matching: .any)["setting-notif.thisDeviceReminders"].waitForExistence(timeout: 10), app.debugDescription)
        if !request.waitForExistence(timeout: 3) {
            XCTAssertFalse(deniedSettings.exists, app.debugDescription)
            app.terminate(); return
        }
        scrollTo(request, in: app)
        attachScreenshot(app, named: "M1-T04-notification-permission-default")

        request.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), springboard.debugDescription)
        let promptButtons = alert.buttons.allElementsBoundByIndex
        let allow = promptButtons.first { button in
            let label = button.label
            let normalized = label.replacingOccurrences(of: "’", with: "'")
            let positive = normalized.localizedCaseInsensitiveContains("allow") || label.contains("السماح")
            let negative = normalized.localizedCaseInsensitiveContains("don't") || label.localizedCaseInsensitiveContains("deny")
                || label.contains("لا تسمح") || label.contains("عدم")
            return positive && !negative
        }
        XCTAssertNotNil(allow, "Notification prompt buttons: \(promptButtons.map(\.label))")
        try XCTUnwrap(allow).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: request)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: deniedSettings)
        waitForExpectations(timeout: 10)
        app.terminate()
    }

    func test_M1T04_QuietHoursSettings() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); finishOnboarding(app)
            let settingsButton = app.buttons["tab-customize"]
            XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), app.debugDescription)
            settingsButton.tap()
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
            search.tap(); search.typeText("notif.quietAfterIsha\n")
            let quietToggle = app.switches["setting-notif.quietAfterIsha"]
            XCTAssertTrue(quietToggle.waitForExistence(timeout: 10), app.debugDescription)
            let quietTime = app.descendants(matching: .any).matching(identifier: "setting-notif.quietFrom").firstMatch
            XCTAssertFalse(quietTime.exists)
            if (quietToggle.value as? String) != "1" { quietToggle.tap() }
            search.tap()
            let currentSearch = search.value as? String ?? ""
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentSearch.count))
            search.typeText("notif.quietFrom\n")
            XCTAssertTrue(quietTime.waitForExistence(timeout: 10), app.debugDescription)
            scrollTo(quietTime, in: app)
            attachScreenshot(app, named: "M1-T04-quiet-hours-\(size)")
            // Owner, 29 Oct 2026: the owner chooses where quiet ends.
            search.tap()
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (search.value as? String ?? "").count))
            search.typeText("notif.quietUntil\n")
            let quietEnd = app.buttons["option-notif.quietUntil-fajr"]
            XCTAssertTrue(quietEnd.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(quietEnd.isSelected, "Fajr is the agreed default end")
            XCTAssertTrue(app.buttons["option-notif.quietUntil-sunrise"].exists && app.buttons["option-notif.quietUntil-midnight"].exists)
            scrollTo(quietEnd, in: app)
            attachScreenshot(app, named: "M1-T04-quiet-end-\(size)")
            app.terminate()
        }
    }

    func test_fixPrevious_M0T13_BackupCountsHonorSelectedNumerals() throws {
        continueAfterFailure = false
        for (style, expected) in [("hindi", "النسخ المحفوظة: ٠ نسخ تلقائية، ٠ نسخ يدوية."), ("western", "النسخ المحفوظة: 0 نسخ تلقائية، 0 نسخ يدوية.")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launch(); finishOnboarding(app)
            if style == "western" {
                app.buttons["tab-customize"].tap()
                let search = app.textFields["settings-search"]
                scrollTo(search, in: app); search.tap(); search.typeText("core.numerals\n")
                let option = app.buttons["option-core.numerals-western"]
                XCTAssertTrue(option.waitForExistence(timeout: 10))
                scrollTo(option, in: app); option.tap()
                expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: option)
                waitForExpectations(timeout: 10)
                app.terminate(); app.launch()
            }
            openBackupSettings(app)
            let counts = app.staticTexts["backup-saved-counts"]
            scrollBackupForm(to: counts, in: app, towardsTop: true)
            XCTAssertEqual(counts.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }, expected)
            attachScreenshot(app, named: "M0-backup-count-numerals-\(style)")
            app.terminate()
        }
    }

    func test_M0T08_PlainExportNativeShareAtDefaultAndDark() throws {
        continueAfterFailure = false
        for (size, theme) in [("L", "light"), ("L", "dark")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launchEnvironment["MADAR_UI_THEME"] = theme
            app.launch(); openPlainExportSettings(app)
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
            // BackupCoordinator names the portable archive Madar-<date>-plain.zip.
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

    func test_M0S2_RU3_CustomizationPlurals() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); finishOnboarding(app)
            XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
            app.buttons["tab-customize"].tap()
            // The count line is the subtitle of the reset door (SettingsHome «أعِد الإعدادات المتفق عليها»).
            let changes = app.buttons["settings-door-أعِد الإعدادات المتفق عليها"]
            XCTAssertTrue(changes.waitForExistence(timeout: 10))
            // The app lock is off by default now, so a fresh store has no saved change.
            XCTAssertTrue(changes.label.contains("كما اتفقنا"), changes.label)
            attachScreenshot(app, named: "M0-RU3-fixture-baseline-\(size)")
            let edits = [
                ("core.theme", "light", "تعديل واحد عن المتفق عليه"),
                ("core.firstCalendar", "hijri", "تعديلان عن المتفق عليه"),
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
                XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
                app.buttons["tab-customize"].tap()
                XCTAssertTrue(changes.waitForExistence(timeout: 10))
                XCTAssertTrue(changes.label.contains(expected), changes.label)
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
            XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
            app.buttons["tab-customize"].tap()
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
        XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
        app.buttons["tab-customize"].tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "M0-native-bar-before-scroll")
        app.swipeUp(); app.swipeUp()
        // Native minimization has no stable public XCTest state; review these two images.
        attachScreenshot(app, named: "M0-native-bar-after-scroll")
        app.terminate()
    }

    func testSettingsRouteScrollsToAndHighlightsExactSetting() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_SETTINGS_ROUTE": "madar://settings/core/core.dayStart"]
        app.launch(); finishOnboarding(app)
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription)
        customize.tap()
        let option = app.buttons["option-core.dayStart-maghrib"]
        XCTAssertTrue(option.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.frame.contains(option.frame), app.debugDescription)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: option)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "The deep link must reach the editable setting.")
        XCTAssertEqual(app.textFields["settings-search"].value as? String, "يبدأ يومك من")
        attachScreenshot(app, named: "AU-95-settings-route-core-dayStart-L")
        app.terminate()
    }

    func testUnknownSettingsRouteShowsInSettingsMessage() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SETTINGS_ROUTE": "madar://settings/core/no.such.key"]
        app.launch(); finishOnboarding(app)
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription)
        customize.tap()
        XCTAssertTrue(app.staticTexts["settings-route-missing"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-clear-search"].exists, "A missing setting key must not remain as an active search.")
        app.terminate()
    }

    func testSettingsRoomRouteOpensTheExactQuranSetting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_SETTINGS_ROUTE": "madar://settings/quran/quran.reviewSchedule"]
        app.launch()
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription)
        customize.tap()
        let option = app.buttons["quran-plan-quran.reviewSchedule"]
        XCTAssertTrue(option.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(option.isHittable, app.debugDescription)
    }

    func testSettingsRoomRouteRejectsAKeyFromAnotherRoom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_SETTINGS_ROUTE": "madar://settings/notes/quran.reviewSchedule"]
        app.launch()
        let customize = app.buttons["tab-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription)
        customize.tap()
        let error = app.alerts.staticTexts["هذا الرابط غير متاح في إصدار مدار الحالي."]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-plan-quran.reviewSchedule"].exists)
    }

    func testBackupFolderPickerCancellationKeepsLocalBackupSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); openBackupSettings(app)
        let policy = app.staticTexts["backup-background-policy"]
        XCTAssertTrue(policy.waitForExistence(timeout: 10))
        scrollBackupForm(to: policy, in: app, towardsTop: true)
        XCTAssertTrue(elementIsOnscreenAndHittable(policy, in: app))
        attachScreenshot(app, named: "B01-background-policy-L")
        let choose = app.buttons["backup-folder-choose"]
        scrollBackupForm(to: choose, in: app, towardsTop: true)
        XCTAssertTrue(choose.isHittable, app.debugDescription)
        attachScreenshot(app, named: "B01-backup-folder-choice-L")
        choose.tap()
        let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["backup-folder-name"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["backup-folder-uploaded"].exists)
        attachScreenshot(app, named: "B01-backup-folder-cancelled-L")
    }

    func testBackupProgressAndCancellationStayVisibleFromTheBottomOfThePage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_BACKUP_HOLD": "1"]
        app.launch(); openBackupSettings(app)
        let location = app.staticTexts.matching(identifier: "backup-storage-location").firstMatch
        scrollBackupForm(to: location, in: app, towardsTop: true)
        XCTAssertTrue(location.label.contains("ستُحفظ"))
        let export = app.buttons["plain-export-now"]
        // B2-18: the unencrypted export sits folded under «متقدم».
        let advanced = app.descendants(matching: .any)["backup-advanced"].firstMatch
        scrollBackupForm(to: advanced, in: app); advanced.tap()
        scrollBackupForm(to: export, in: app); XCTAssertTrue(export.isHittable); export.tap()
        let cancel = app.buttons["backup-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); XCTAssertTrue(elementIsOnscreenAndHittable(cancel, in: app))
        attachScreenshot(app, named: "B01-visible-progress-L")
        cancel.tap()
        let result = app.staticTexts["backup-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10)); XCTAssertTrue(result.label.contains("أُلغي"))
        XCTAssertTrue(elementIsOnscreenAndHittable(result, in: app)); attachScreenshot(app, named: "B01-visible-cancel-result-L")
        app.buttons["backup-result-dismiss"].tap(); XCTAssertTrue(result.waitForNonExistence(timeout: 5))
    }

    func testBackupRestorePickerAcceptsFileAndPackageTypesAndCancellationKeepsData() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); openBackupSettings(app)
        let select = app.buttons["restore-select-file"]
        scrollBackupForm(to: select, in: app)
        XCTAssertTrue(elementIsOnscreenAndHittable(select, in: app)); select.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); attachScreenshot(app, named: "B01-restore-picker-L")
        cancel.tap()
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["restore-confirm"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot(app, named: "B01-restore-picker-cancelled-L")
    }

    func test_M0S2_SecurePasswordTypingTransport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); openBackupSettings(app)
        let password = app.secureTextFields["backup-password"]
        let keyboardDone = app.buttons["backup-keyboard-done"]
        let roomBar = app.tabBars["fixed-tab-bar"]
        let checksRoomBar = UIDevice.current.userInterfaceIdiom == .phone
        if checksRoomBar { XCTAssertTrue(roomBar.exists) }
        scrollBackupForm(to: password, in: app)
        password.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), app.debugDescription)
        if checksRoomBar { XCTAssertTrue(roomBar.waitForNonExistence(timeout: 5)) }
        // XCTest's secure input is limited to characters in the active Arabic keyboard layout.
        for (index, character) in "تجربةنسخةمدار".enumerated() {
            password.typeText(String(character))
            let expected = "passphrase-count=\(index + 1);confirmation-count=0;matches=false;busy=false;can-export=false"
            let update = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: keyboardDone)
            XCTAssertEqual(XCTWaiter.wait(for: [update], timeout: 3), .completed, "Keyboard state: \(keyboardDone.value ?? "unavailable")")
        }
        attachScreenshot(app, named: "M0-backup-character-transport-L")
        keyboardDone.tap()
        if checksRoomBar { XCTAssertTrue(roomBar.waitForExistence(timeout: 5)) }
        app.terminate()
    }
    func test_M0S2_BackupPasswordConfirmationAndFixtureIsolation() throws {
        continueAfterFailure = false
        // A second fresh fixture must not inherit the first fixture's configured Keychain key.
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); openBackupSettings(app)
            let keySetup = app.staticTexts["backup-key-setup"]
            scrollBackupForm(to: keySetup, in: app)
            XCTAssertTrue(keySetup.exists, "A fresh fixture must not inherit a configured backup key.")
            // The approved simulator uses an Arabic keyboard. Secure entry
            // cannot insert characters that are absent from the active layout.
            let passphrase = "تجربةنسخةمدارطويلة"
            let export = app.buttons["backup-now"]
            let password = app.secureTextFields["backup-password"]
            scrollBackupForm(to: password, in: app, towardsTop: true)
            password.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let keyboardDone = app.buttons["backup-keyboard-done"]
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 10), app.debugDescription)
            password.typeText(passphrase)
            attachScreenshot(app, named: "M0-backup-before-confirmation-\(size)")
            XCTAssertEqual(keyboardDone.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=0;matches=false;busy=false;can-export=false", "Validate first-field input before submitting or changing focus.")
            // Exercise native Next while the keyboard changes the visible area,
            // instead of tapping a row whose frame may be outside that area.
            password.typeText("\n")
            let confirmation = app.secureTextFields["backup-password-confirmation"]
            let mismatch = passphrase + "ب"
            confirmation.typeText(mismatch)
            // The toolbar mirrors the predicate driving the virtualized export
            // button's disabled state. Do not change focus just to query that row.
            XCTAssertEqual(keyboardDone.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=\(mismatch.count);matches=false;busy=false;can-export=false", "A mismatched confirmation must not permit export.")
            // The insertion point is still at the end; remove only the extra mismatching
            // character. Re-tapping a populated secure field can move the insertion point.
            confirmation.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(keyboardDone.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=\(passphrase.count);matches=true;busy=false;can-export=true")
            keyboardDone.tap()
            scrollTo(export, in: app)
            XCTAssertTrue(export.isEnabled, app.debugDescription); export.tap()
            let share = app.buttons["backup-export"]
            XCTAssertTrue(share.waitForExistence(timeout: 20), app.debugDescription)
            scrollTo(share, in: app)
            attachScreenshot(app, named: "M0-backup-native-export-\(size)")

            app.terminate(); app.launch(); openBackupSettings(app)
            // Bring the export card into view before checking that its setup notice is absent.
            scrollBackupForm(to: app.buttons["backup-now"], in: app)
            XCTAssertFalse(keySetup.exists, "The same fixture must retain its configured key after relaunch.")
            app.terminate()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launch(); openBackupSettings(app)
            scrollBackupForm(to: keySetup, in: app)
            XCTAssertTrue(keySetup.exists, "A separate fixture must have its own backup key.")
            app.terminate()
        }
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
    func testFirstRunAndNativeRoomSectionOpensBuiltRooms() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch()
        finishOnboarding(app)
        let settings = app.buttons["tab-customize"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["القرآن"].exists, "M2 Quran home is now built.")
        let mihbara = app.buttons["المحبرة"]
        XCTAssertTrue(mihbara.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M0-native-glass-room-shortcuts-L")
        mihbara.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["settings-door-أعِد الإعدادات المتفق عليها"].waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M0-customize-RTL")
    }

    func testLightDarkAndAccessibilityScreenshots() throws {
        continueAfterFailure = false
        for theme in ["light", "dark"] {
            for size in ["L"] {
                let app = XCUIApplication()
                app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
                app.launchEnvironment["MADAR_UI_THEME"] = theme
                app.launchEnvironment["MADAR_UI_SIZE"] = size
                app.launch()
                finishOnboarding(app)
                XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 15))
                let home = XCTAttachment(screenshot: app.screenshot()); home.name = "M0-home-\(theme)-\(size)"; home.lifetime = .keepAlways; add(home)
                app.buttons["tab-customize"].tap()
                XCTAssertTrue(app.buttons["settings-door-أعِد الإعدادات المتفق عليها"].waitForExistence(timeout: 10))
                let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "M0-settings-\(theme)-\(size)"; settings.lifetime = .keepAlways; add(settings)
                app.terminate()
            }
        }
    }
    func testThemePersistenceResetAndUndoThroughUI() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch(); finishOnboarding(app)
        XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
        app.buttons["tab-customize"].tap()
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
        // FB-32: a setting change shows no undo line any more; the page reset (below) is the way back.
        expectation(for: selected, evaluatedWith: dark)
        waitForExpectations(timeout: 10)
        app.terminate(); app.launch(); finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let newSearch = app.textFields["settings-search"]
        newSearch.tap(); newSearch.typeText("core.theme\n")
        XCTAssertTrue(app.buttons["option-core.theme-dark"].isSelected)
        app.buttons["settings-clear-search"].tap()
        let resetSettings = app.buttons["settings-door-أعِد الإعدادات المتفق عليها"]
        scrollTo(resetSettings, in: app); resetSettings.tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "أعِد الافتراضي", "reset-settings")).firstMatch.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 10))
        // The search sits at the top of the page, above the reset row just used: scroll back up to it.
        for _ in 0..<8 where !newSearch.isHittable { swipeVisibleContent(in: app, down: true) }
        newSearch.tap(); newSearch.typeText("core.theme\n")
        XCTAssertTrue(app.buttons["option-core.theme-auto"].isSelected)
        app.buttons["undo-button"].tap()
        let selectedAgain = app.buttons["option-core.theme-dark"]
        let predicate = NSPredicate(format: "selected == true")
        expectation(for: predicate, evaluatedWith: selectedAgain)
        waitForExpectations(timeout: 10)
    }
    func test_M0T17_LeanFoundationCityNumeralsResetUndoAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launchEnvironment["MADAR_UI_THEME"] = "light"
        app.launchEnvironment["MADAR_UI_NOW"] = "2026-10-15T12:00:00+03:00"
        app.launch(); finishOnboarding(app)
        let settings = app.buttons["tab-customize"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), app.debugDescription)
        let foundation = XCTAttachment(screenshot: app.screenshot())
        foundation.name = "M0-T17-foundation-default-L"; foundation.lifetime = .keepAlways; add(foundation)
        settings.tap()

        func filterSettings(_ query: String) {
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
            search.tap()
            let previous = search.value as? String ?? ""
            if !previous.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            }
            search.typeText(query + "\n")
        }

        filterSettings("core.homeCity")
        let city = app.descendants(matching: .any).matching(identifier: "setting-core.homeCity").firstMatch
        XCTAssertTrue(city.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(city, in: app)
        city.tap()
        let makkah = app.buttons["مكة المكرمة"]
        XCTAssertTrue(makkah.waitForExistence(timeout: 10), app.debugDescription)
        makkah.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "مكة المكرمة"), evaluatedWith: city)
        waitForExpectations(timeout: 10)

        app.terminate(); app.launch(); finishOnboarding(app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        // The lobby no longer shows the city or prayer times: the saved city is read back from its setting.
        filterSettings("core.homeCity")
        let cityAfterRelaunch = app.descendants(matching: .any).matching(identifier: "setting-core.homeCity").firstMatch
        XCTAssertTrue(cityAfterRelaunch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(cityAfterRelaunch.label.contains("مكة المكرمة"), cityAfterRelaunch.label)
        filterSettings("core.numerals")
        let western = app.buttons["option-core.numerals-western"]
        XCTAssertTrue(western.waitForExistence(timeout: 10), app.debugDescription)
        western.tap()
        XCTAssertTrue(western.isSelected)

        app.terminate(); app.launch(); finishOnboarding(app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        filterSettings("core.numerals")
        XCTAssertTrue(app.buttons["option-core.numerals-western"].isSelected)
        app.buttons["settings-clear-search"].tap()
        let resetSettings = app.buttons["settings-door-أعِد الإعدادات المتفق عليها"]
        scrollTo(resetSettings, in: app); resetSettings.tap()
        let reset = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "أعِد الافتراضي", "reset-settings")).firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 10), app.debugDescription)
        reset.tap()
        filterSettings("core.numerals")
        let arabicIndic = app.buttons["option-core.numerals-arabicIndic"]
        XCTAssertTrue(arabicIndic.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(arabicIndic.isSelected)

        filterSettings("core.homeCity")
        let cityAfterReset = app.descendants(matching: .any).matching(identifier: "setting-core.homeCity").firstMatch
        XCTAssertTrue(cityAfterReset.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(cityAfterReset.label.contains("الرياض"), cityAfterReset.label)
        let undo = app.buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), app.debugDescription)
        undo.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "مكة المكرمة"), evaluatedWith: cityAfterReset)
        waitForExpectations(timeout: 10)
        filterSettings("core.numerals")
        XCTAssertTrue(app.buttons["option-core.numerals-western"].isSelected)

        app.terminate(); app.launch(); finishOnboarding(app)
        settings.tap()
        filterSettings("core.homeCity")
        let restoredCity = app.descendants(matching: .any).matching(identifier: "setting-core.homeCity").firstMatch
        XCTAssertTrue(restoredCity.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(restoredCity.label.contains("مكة المكرمة"), restoredCity.label)
        app.terminate()
    }
    func testSharedComponentsAtEveryRequiredSizeAndMode() throws {
        for theme in ["light", "dark"] {
            for size in ["L"] {
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
    private func elementIsOnscreenAndHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        // Ask for hittability only of a key with an on-screen frame: XCTest fails outright on a hidden keyboard copy whose
        // activation point is invalid (the second layout the system keeps off screen).
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 0 && frame.height > 0 && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return element.isHittable
    }
    private func openBackupSettings(_ app: XCUIApplication) {
        finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let link = app.buttons["settings-link-النسخ والاستعادة"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["النسخ والاستعادة"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["backup-schedule"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func scrollBackupForm(to element: XCUIElement, in app: XCUIApplication, towardsTop: Bool = false) {
        let navigation = app.navigationBars["النسخ والاستعادة"].frame
        let roomBar = app.tabBars["fixed-tab-bar"]
        let top = navigation.maxY
        let bottom = roomBar.exists ? roomBar.frame.minY : app.frame.maxY
        let midpoint = (top + bottom) / 2
        for _ in 0..<8 {
            let frame = element.exists ? element.frame : .null
            // Secure fields can have an invalid XCTest activation point while visible.
            // The callers tap the rendered field and assert that the keyboard opened.
            if !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom { return }
            let maxDrag = (bottom - top) / 2
            let distance = frame.isNull ? (towardsTop ? maxDrag : -maxDrag)
                : min(maxDrag, max(-maxDrag, midpoint - frame.midY))
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width / 2, dy: midpoint - distance / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTFail("Could not bring \(element) into the backup viewport. \(app.debugDescription)")
    }
    private func openPlainExportSettings(_ app: XCUIApplication) {
        finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let link = app.buttons["settings-link-النسخ والاستعادة"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["النسخ والاستعادة"].waitForExistence(timeout: 10), app.debugDescription)
        // Form is a CollectionView in the captured AX3 hierarchy. Its offscreen cells
        // are virtualized, so scroll before requiring the export button to exist.
        let form = app.scrollViews.firstMatch // The backup screen is a Madar paper scroll view, not a grouped Form.
        XCTAssertTrue(form.waitForExistence(timeout: 10), app.debugDescription)
        let export = app.buttons["plain-export-now"]
        // B2-18: the unencrypted export sits folded under «متقدم».
        let advanced = app.descendants(matching: .any)["backup-advanced"].firstMatch
        for _ in 0..<12 where !(advanced.exists && advanced.isHittable) { form.swipeUp() }
        if !export.exists { advanced.tap() }
        for _ in 0..<12 {
            if export.exists && export.isHittable { return }
            form.swipeUp()
        }
        XCTAssertTrue(export.exists, app.debugDescription)
        XCTAssertTrue(export.isHittable, app.debugDescription)
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { break }
            swipeVisibleContent(in: app)
        }
        // The undo toast, glass accessory and tab bar float over the lowest ~200 pt; XCUITest still calls a row
        // under them hittable, so its tap lands on the toast. Lift such a row above that band before tapping.
        let floor = app.frame.height - 200
        if element.isHittable, element.frame.maxY > floor, element.frame.height < floor / 2 {
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width / 2, dy: floor - 20))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -(element.frame.maxY - floor + 60))))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func swipeVisibleContent(in app: XCUIApplication, down: Bool = false) {
        // App-wide swipe discovery can pick the retained lobby's hidden ScrollView.
        // Drag the visible content, above the native tab bar, instead.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        (down ? top : bottom).press(forDuration: 0.05, thenDragTo: down ? bottom : top)
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
        // A store without a fixture reaches the location step. The cover closes when the city is saved.
        let city = app.buttons["first-run-city"]
        guard city.waitForExistence(timeout: 2) else { return }
        city.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription); field.tap(); field.typeText("الرياض")
        let hit = app.buttons["city-hit-الرياض"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription); hit.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(city.waitForNonExistence(timeout: 8), app.debugDescription)
    }
}
