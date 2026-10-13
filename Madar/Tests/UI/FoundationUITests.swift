import XCTest

@MainActor final class FoundationUITests: XCTestCase {
    /// M1-V01: the prayer home with canonical-like data, for comparison with screens/salah/01-S1-Home(-s1).jpg.
    func test_M1V01_HomeMatchesCanonical() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
                "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            let header = app.descendants(matching: .any).matching(identifier: "prayer-today-header").firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(header.label.contains("الأربعاء") && header.label.contains("ربيع الآخر") && header.label.contains("أكتوبر"), header.label)
            XCTAssertFalse(header.label.contains("-"), "The header shows dates in words, not ISO: \(header.label)")
            let maghrib = app.descendants(matching: .any).matching(identifier: "prayer-arch-maghrib").firstMatch
            XCTAssertTrue(maghrib.exists, app.debugDescription)
            let asr = app.descendants(matching: .any).matching(identifier: "prayer-arch-asr").firstMatch
            XCTAssertTrue(asr.label.contains("وحدي"), asr.label)
            XCTAssertFalse(app.buttons["prayer-heart-review"].exists, "RP6: the heart question is off by default")
            attachScreenshot(app, named: "M1-V01-home-\(size)")
            let pending = app.buttons["prayer-pending-review"]
            XCTAssertTrue(pending.exists, app.debugDescription)
            XCTAssertTrue(pending.label.contains("العشاء") && pending.label.contains("أمس"), pending.label)
            let makeup = app.buttons["prayer-qada-makeup"]; scrollTo(makeup, in: app)
            attachScreenshot(app, named: "M1-V01-home-scrolled-\(size)")
            let qiyam = app.buttons["prayer-qiyam"]; scrollTo(qiyam, in: app)
            attachScreenshot(app, named: "M1-V01-home-bottom-\(size)")
            app.terminate()
        }
    }

    func test_M1T09_OldMissedSaveUndoRestoreMakeUpAndRelaunch() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-08T09:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-03", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            let add = app.buttons["prayer-old-missed"]; scrollTo(add, in: app); add.tap()
            let save = app.buttons["prayer-old-save"]; scrollTo(save, in: app)
            attachScreenshot(app, named: "M1-T09-old-missed-\(size)"); save.tap()
            let undo = app.buttons["undo-button"]; XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            scrollTo(add, in: app); add.tap()
            let restore = app.buttons["prayer-old-restore"]; scrollTo(restore, in: app)
            XCTAssertFalse(save.exists); restore.tap(); app.buttons["أعد التسجيل"].firstMatch.tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 15))
            app.terminate(); app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            let places = app.buttons["prayer-qada-places"]; scrollTo(places, in: app); places.tap()
            let row = app.descendants(matching: .any).matching(identifier: "prayer-qada-row-2026-10-02-fajr").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
            app.buttons["تم"].firstMatch.tap()
            let makeup = app.buttons["prayer-qada-makeup"]; scrollTo(makeup, in: app); makeup.tap()
            let confirm = app.buttons["prayer-makeup-confirm"]; scrollTo(confirm, in: app); confirm.tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            scrollTo(makeup, in: app); XCTAssertTrue(makeup.isEnabled)
            app.terminate()
        }
    }

    func test_M1T08_OffsetsAffectBothClockScreensResetUndoAndRelaunch() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-07", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app); app.buttons["settings-button"].tap()
            let search = app.textFields["settings-search"]
            scrollTo(search, in: app); search.tap(); search.typeText("salah.offsets\n")
            let plus = app.buttons["offset-isha-plus"]
            let value = app.staticTexts["offset-isha-value"]
            scrollTo(plus, in: app)
            for expected in ["١", "٢", "٣", "٤", "٥"] {
                plus.tap()
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: value)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            }
            attachScreenshot(app, named: "M1-T08-offsets-\(size)")
            app.terminate(); app.launch(); finishOnboarding(app)
            let clock = app.descendants(matching: .any).matching(identifier: "foundation-prayer-time-isha").firstMatch
            scrollTo(clock, in: app); XCTAssertTrue(clock.label.contains("١٩:٠٩"), clock.label)
            app.swipeDown(); app.tabBars.buttons["الصلاة"].tap()
            let isha = app.descendants(matching: .any).matching(identifier: "prayer-arch-isha").firstMatch
            scrollTo(isha, in: app); XCTAssertTrue(isha.label.contains("٧:٠٩"), isha.label)
            app.terminate(); app.launch(); finishOnboarding(app); app.buttons["settings-button"].tap()
            let reset = app.buttons["reset-settings"]
            scrollTo(reset, in: app); reset.tap()
            app.buttons["أعِد الافتراضي"].firstMatch.tap()
            let undo = app.buttons["undo-button"]
            XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            scrollTo(search, in: app); search.tap(); search.typeText("salah.offsets\n")
            XCTAssertTrue(value.waitForExistence(timeout: 10)); XCTAssertEqual(value.label, "٥")
            app.terminate()
        }
    }

    func test_M1T07_QiyamSaveRelaunchUndoRestore() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-08T02:10:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-07", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            let qiyam = app.buttons["prayer-qiyam"]
            scrollTo(qiyam, in: app); qiyam.tap()
            let plus = app.buttons["prayer-qiyam-plus"]
            scrollTo(plus, in: app); for _ in 0..<4 { plus.tap() }
            let count = app.staticTexts["prayer-qiyam-count"]
            XCTAssertEqual(count.label, "٨")
            let witr = app.switches["prayer-qiyam-witr"]
            scrollTo(witr, in: app); witr.tap()
            attachScreenshot(app, named: "M1-T07-qiyam-\(size)")
            let save = app.buttons["prayer-qiyam-save"]
            scrollTo(save, in: app); save.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed)
            let undo = app.buttons["undo-button"]
            XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            scrollTo(qiyam, in: app); qiyam.tap()
            let restore = app.buttons["prayer-qiyam-restore"]
            XCTAssertFalse(save.exists, "Undo must require explicit restoration")
            scrollTo(plus, in: app); for _ in 0..<4 { plus.tap() }
            scrollTo(witr, in: app); witr.tap()
            scrollTo(restore, in: app); restore.tap(); app.buttons["أعد التسجيل"].tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 15))
            app.terminate(); app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            scrollTo(qiyam, in: app); qiyam.tap()
            XCTAssertTrue(count.waitForExistence(timeout: 10)); XCTAssertEqual(count.label, "٨")
            XCTAssertEqual(witr.value as? String, "1")
            let list = app.descendants(matching: .any).matching(identifier: "prayer-qiyam-footprint-list").firstMatch
            XCTAssertTrue(list.exists)
            app.terminate()
        }
    }

    func test_M1T06_OptionalHeartSaveSkipUndoAndRelaunch() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
                "MADAR_UI_PRAYER_FIXTURE": "ratio26of30", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app)
            app.tabBars.buttons["الصلاة"].tap()
            XCTAssertFalse(app.buttons["prayer-heart-review"].exists, "RP6 defaults to off")
            app.terminate(); app.launch(); finishOnboarding(app)
            app.buttons["settings-button"].tap()
            let search = app.textFields["settings-search"]
            scrollTo(search, in: app); search.tap(); search.typeText("salah.askHeart\n")
            let toggle = app.switches["setting-salah.askHeart"]
            scrollTo(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0"); toggle.tap()
            app.swipeDown(); app.tabBars.buttons["الصلاة"].tap()
            let review = app.buttons["prayer-heart-review"]
            scrollTo(review, in: app); review.tap()
            let present = app.buttons["prayer-heart-present"]
            scrollTo(present, in: app); present.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: present)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, app.debugDescription)
            attachScreenshot(app, named: "M1-T06-heart-\(size)")
            let save = app.buttons["prayer-heart-save"]
            scrollTo(save, in: app); save.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed, app.debugDescription)
            let undo = app.buttons["undo-button"]
            XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            scrollTo(review, in: app); review.tap()
            XCTAssertFalse(present.isSelected)
            let skip = app.buttons["prayer-heart-skip"]
            scrollTo(skip, in: app); skip.tap()
            scrollTo(review, in: app); review.tap()
            scrollTo(present, in: app); present.tap(); scrollTo(save, in: app); save.tap()
            app.terminate(); app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            let history = app.buttons["prayer-history"]
            scrollTo(history, in: app); history.tap()
            let day = app.buttons["prayer-history-day-2026-10-06"]
            scrollTo(day, in: app); day.tap()
            app.buttons["prayer-history-log-fajr"].tap()
            let heart = app.buttons["prayer-log-heart"]
            scrollTo(heart, in: app); heart.tap()
            XCTAssertTrue(present.waitForExistence(timeout: 10)); XCTAssertTrue(present.isSelected)
            scrollTo(skip, in: app); skip.tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 15)); undo.tap()
            app.terminate()
        }
    }

    func test_M1T05_HaliGoldenRatioHistoryEditUndo() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": size,
                "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
                "MADAR_UI_PRAYER_FIXTURE": "ratio26of30", "MADAR_UI_THEME": "light"]
            app.launch(); finishOnboarding(app)
            app.tabBars.buttons["الصلاة"].tap()
            let history = app.buttons["prayer-history"]
            scrollTo(history, in: app); history.tap()
            let ratio = app.staticTexts["prayer-stat-percentage"]
            XCTAssertTrue(ratio.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(ratio.label, "٨٧٪")
            let qada = app.staticTexts["prayer-stat-qada"]
            scrollTo(qada, in: app)
            XCTAssertEqual(qada.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }, "قُضيت ٢، عليك ٢")
            attachScreenshot(app, named: "M1-T05-hali-\(size)")
            let day = app.buttons["prayer-history-day-2026-10-06"]
            scrollTo(day, in: app); attachScreenshot(app, named: "M1-T05-history-\(size)"); day.tap()
            let isha = app.buttons["prayer-history-log-isha"]
            XCTAssertTrue(isha.waitForExistence(timeout: 10), app.debugDescription); isha.tap()
            let alone = app.buttons["prayer-status-alone"]
            XCTAssertTrue(alone.waitForExistence(timeout: 10), app.debugDescription); alone.tap()
            app.buttons["prayer-save"].tap()
            let undo = app.buttons["undo-button"]
            XCTAssertTrue(undo.waitForExistence(timeout: 10), app.debugDescription)
            scrollTo(history, in: app); history.tap()
            XCTAssertTrue(ratio.waitForExistence(timeout: 10)); XCTAssertEqual(ratio.label, "٩٠٪")
            app.buttons["تم"].tap()
            undo.tap()
            scrollTo(history, in: app); history.tap()
            XCTAssertTrue(ratio.waitForExistence(timeout: 10)); XCTAssertEqual(ratio.label, "٨٧٪")
            app.terminate(); app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            scrollTo(history, in: app); history.tap()
            XCTAssertTrue(ratio.waitForExistence(timeout: 10)); XCTAssertEqual(ratio.label, "٨٧٪")
            app.terminate()
        }
    }

    func test_M1T04_NotificationPermissionPrompt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launch(); finishOnboarding(app)
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        let request = app.buttons["prayer-notification-permission-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 10), app.debugDescription)
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
        let deniedSettings = app.buttons["prayer-notification-permission-settings"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: deniedSettings)
        waitForExpectations(timeout: 10)
        app.terminate()
    }

    func test_M1T04_RealAppNotificationSchedulingSnoozeAndCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_NOTIFICATION_TEST_FLOW"] = "1"
        app.launch()

        let authorize = app.buttons["notification-test-authorize"]
        if authorize.waitForExistence(timeout: 3) {
            authorize.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), springboard.debugDescription)
            let allow = alert.buttons.allElementsBoundByIndex.first { button in
                let label = button.label
                let normalized = label.replacingOccurrences(of: "’", with: "'")
                let positive = normalized.localizedCaseInsensitiveContains("allow") || label.contains("السماح")
                let negative = normalized.localizedCaseInsensitiveContains("don't") || label.localizedCaseInsensitiveContains("deny")
                    || label.contains("لا تسمح") || label.contains("عدم")
                return positive && !negative
            }
            XCTAssertNotNil(allow, "Notification prompt buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
            try XCTUnwrap(allow).tap()
        }

        let run = app.buttons["notification-test-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 15), app.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: run)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, app.debugDescription)
        run.tap()

        let result = app.staticTexts["notification-test-result"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "PASS"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 35), .completed, app.debugDescription)
        XCTAssertTrue(result.label.contains("Fajr"), result.label)
        XCTAssertTrue(result.label.contains("Maghrib"), result.label)
    }

    func test_M1T04_QuietHoursSettings() throws {
        continueAfterFailure = false
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); finishOnboarding(app)
            let settingsButton = app.buttons["settings-button"]
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
            app.terminate()
        }
    }

    func test_fixPrevious_M0T13_BackupCountsHonorSelectedNumerals() throws {
        continueAfterFailure = false
        for (style, expected) in [("hindi", "النسخ المحفوظة: ٠ تلقائية، ٠ يدوية."), ("western", "النسخ المحفوظة: 0 تلقائية، 0 يدوية.")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launch(); finishOnboarding(app)
            if style == "western" {
                app.buttons["settings-button"].tap()
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

    func test_M0T10_TodayPrayerTimesAtDefaultAndDark() throws {
        continueAfterFailure = false
        for (size, theme) in [("L", "light"), ("L", "dark")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launchEnvironment["MADAR_UI_THEME"] = theme
            app.launch(); finishOnboarding(app)
            let content = app.scrollViews.firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
            let names = [("fajr", "الفجر"), ("dhuhr", "الظهر"), ("asr", "العصر"), ("maghrib", "المغرب"), ("isha", "العشاء")]
            for (index, pair) in names.enumerated() {
                let row = app.descendants(matching: .any).matching(identifier: "foundation-prayer-time-\(pair.0)").firstMatch
                // Offscreen SwiftUI rows may not exist in the accessibility tree yet.
                for _ in 0..<12 {
                    if row.exists && row.isHittable { break }
                    content.swipeUp()
                }
                XCTAssertTrue(row.exists, app.debugDescription)
                XCTAssertTrue(row.isHittable, app.debugDescription)
                XCTAssertTrue(row.label.hasPrefix("\(pair.1)، "), row.label)
                XCTAssertTrue(NSPredicate(format: "SELF MATCHES %@", "[^،]+، [٠-٩]{2}:[٠-٩]{2}").evaluate(with: row.label), row.label)
                if index == 0 || index == names.count - 1 { attachScreenshot(app, named: "M0-today-times-\(pair.0)-\(theme)-\(size)") }
                XCTAssertFalse(app.buttons["foundation-prayer-time-\(pair.0)"].exists, "Foundation clocks are read-only.")
            }
            XCTAssertFalse(app.buttons["prayer-log"].exists)
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
        for size in ["L"] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launch(); openBackupSettings(app)
            let keySetup = app.staticTexts["backup-key-setup"]
            scrollBackupForm(to: keySetup, in: app)
            XCTAssertTrue(keySetup.exists, "A fresh fixture must not inherit a configured backup key.")
            let passphrase = "test-only-passphrase"
            let export = app.buttons["backup-now"]
            let password = app.secureTextFields["backup-password"]
            scrollBackupForm(to: password, in: app, towardsTop: true)
            password.tap()
            try selectEnglishKeyboard(app)
            let keyboardDone = app.buttons["backup-keyboard-done"]
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 10), app.debugDescription)
            password.typeText(passphrase)
            attachScreenshot(app, named: "M0-backup-before-confirmation-\(size)")
            XCTAssertEqual(keyboardDone.value as? String, "passphrase-count=\(passphrase.count);confirmation-count=0;matches=false;busy=false;can-export=false", "Validate first-field input before submitting or changing focus.")
            // Exercise native Next while the keyboard changes the Form's visible area,
            // instead of tapping a row whose frame may be outside that area.
            password.typeText("\n")
            let confirmation = app.secureTextFields["backup-password-confirmation"]
            let mismatch = passphrase + "!"
            try selectEnglishKeyboard(app)
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
            // The setup notice is below the fields. Materialize its section before
            // asserting absence, so an offscreen cell cannot masquerade as persistence.
            scrollBackupForm(to: app.buttons["backup-now"], in: app)
            XCTAssertFalse(keySetup.exists, "The same fixture must retain its configured key after relaunch.")
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
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch()
        finishOnboarding(app)
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["الصلاة"].exists, "The M1 prayer screen is the first built room.")
        XCTAssertFalse(app.buttons["القرآن"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "M0-iPhone17Pro-RTL-light-L"; shot.lifetime = .keepAlways; add(shot)
        settings.tap()
        XCTAssertTrue(app.buttons["reset-settings"].waitForExistence(timeout: 10), app.debugDescription)
        let settingsShot = XCTAttachment(screenshot: app.screenshot()); settingsShot.name = "M0-customize-RTL"; settingsShot.lifetime = .keepAlways; add(settingsShot)
    }

    func test_M1T01_PrayerLogPersistsChangeUndo() throws {
        continueAfterFailure = false
        let storeID = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": storeID, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)

        func openPrayer(_ target: XCUIApplication) {
            let tab = target.tabBars.buttons["الصلاة"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), target.debugDescription)
            tab.tap()
            XCTAssertTrue(target.staticTexts["الصلاة"].waitForExistence(timeout: 10), target.debugDescription)
        }
        func fajrArch(_ target: XCUIApplication) -> XCUIElement {
            target.buttons.matching(NSPredicate(format: "label CONTAINS %@", "الفجر")).firstMatch
        }
        func record(_ status: String, in target: XCUIApplication) {
            let arch = fajrArch(target)
            XCTAssertTrue(arch.waitForExistence(timeout: 10), target.debugDescription)
            arch.tap()
            let choice = target.buttons["prayer-status-\(status)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 10), target.debugDescription)
            choice.tap()
            target.buttons["prayer-save"].tap()
        }

        openPrayer(app)
        let firstScreen = XCTAttachment(screenshot: app.screenshot())
        firstScreen.name = "M1-T01-prayer-today-default-L"; firstScreen.lifetime = .keepAlways; add(firstScreen)
        record("jamaah", in: app)
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch(); finishOnboarding(app); openPrayer(app)
        XCTAssertTrue(fajrArch(app).label.contains("جماعة"), fajrArch(app).label)

        record("alone", in: app)
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["undo-button"].tap()
        let restored = fajrArch(app)
        let jamaahRestored = NSPredicate(format: "label CONTAINS %@", "جماعة")
        expectation(for: jamaahRestored, evaluatedWith: restored)
        waitForExpectations(timeout: 15)
        app.terminate(); app.launch(); finishOnboarding(app); openPrayer(app)
        XCTAssertTrue(fajrArch(app).label.contains("جماعة"), fajrArch(app).label)
        app.terminate()
    }
    func test_M1T02_MissedMakeUpUndoAndRelaunch() throws {
        continueAfterFailure = false
        let storeID = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": storeID,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-13T09:00:00+03:00"
        ]
        app.launch(); finishOnboarding(app)
        func fajrArch(_ target: XCUIApplication) -> XCUIElement {
            target.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "الفجر" )).firstMatch
        }
        let prayerTab = app.tabBars.buttons["الصلاة"]
        XCTAssertTrue(prayerTab.waitForExistence(timeout: 10), app.debugDescription)
        prayerTab.tap()
        let fajr = fajrArch(app)
        XCTAssertTrue(fajr.waitForExistence(timeout: 10), app.debugDescription)
        fajr.tap()
        app.buttons["prayer-status-missed"].tap()
        let later = app.buttons["prayer-missed-later"]
        scrollTo(later, in: app)
        XCTAssertTrue(later.waitForExistence(timeout: 10), app.debugDescription)
        later.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        attachScreenshot(app, named: "M1-T02-missed-explicit-L")

        app.terminate(); app.launch(); finishOnboarding(app)
        let reopenedTab = app.tabBars.buttons["الصلاة"]
        XCTAssertTrue(reopenedTab.waitForExistence(timeout: 10), app.debugDescription)
        reopenedTab.tap()
        let reopenedFajr = fajrArch(app)
        XCTAssertTrue(reopenedFajr.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(reopenedFajr.label.contains("فاتتني"), reopenedFajr.label)
        let makeUpButton = app.buttons["prayer-qada-makeup"]
        scrollTo(makeUpButton, in: app)
        makeUpButton.tap()
        let confirmMakeUp = app.buttons["prayer-makeup-confirm"]
        XCTAssertTrue(confirmMakeUp.waitForExistence(timeout: 10), app.debugDescription)
        confirmMakeUp.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)

        let qadaArch = fajrArch(app)
        let qadaLabel = NSPredicate(format: "label CONTAINS %@", "قُضيت")
        expectation(for: qadaLabel, evaluatedWith: qadaArch)
        waitForExpectations(timeout: 10)
        app.buttons["undo-button"].tap()
        let restored = fajrArch(app)
        let missedLabel = NSPredicate(format: "label CONTAINS %@", "فاتتني")
        expectation(for: missedLabel, evaluatedWith: restored)
        waitForExpectations(timeout: 15)
        attachScreenshot(app, named: "M1-T02-makeup-undo-restores-missed-L")

        app.terminate(); app.launch(); finishOnboarding(app)
        app.tabBars.buttons["الصلاة"].tap()
        let afterRelaunch = fajrArch(app)
        XCTAssertTrue(afterRelaunch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(afterRelaunch.label.contains("فاتتني"), afterRelaunch.label)
        app.terminate()
    }
    func test_M1T02_BulkPendingRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-13T09:00:00+03:00",
            "MADAR_UI_TRACKING_START": "2026-10-01"
        ]
        app.launch(); finishOnboarding(app)
        let prayerTab = app.tabBars.buttons["الصلاة"]
        XCTAssertTrue(prayerTab.waitForExistence(timeout: 10), app.debugDescription)
        prayerTab.tap()
        let recovery = app.buttons["prayer-recovery"]
        scrollTo(recovery, in: app)
        recovery.tap()
        let bulkUnrecorded = app.buttons["prayer-gap-unrecorded-all"]
        XCTAssertTrue(bulkUnrecorded.waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M1-T02-recovery-sheet-L")
        bulkUnrecorded.tap()
        let save = app.buttons["prayer-gap-save"]
        scrollTo(save, in: app)
        save.tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: app.buttons["prayer-recovery"])
        waitForExpectations(timeout: 15)
        app.terminate()
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
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
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
    func test_M0T17_LeanFoundationCityNumeralsResetUndoAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["MADAR_UI_SIZE"] = "L"
        app.launchEnvironment["MADAR_UI_THEME"] = "light"
        app.launch(); finishOnboarding(app)
        let settings = app.buttons["settings-button"]
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
        let cityOnHome = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "مكة المكرمة"
        )).firstMatch
        XCTAssertTrue(cityOnHome.exists, app.debugDescription)
        settings.tap()
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
        app.buttons["reset-settings"].tap()
        let reset = app.buttons["أعِد الافتراضي"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 10), app.debugDescription)
        reset.tap()
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
        let restoredCity = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "مكة المكرمة"
        )).firstMatch
        XCTAssertTrue(restoredCity.waitForExistence(timeout: 10), app.debugDescription)
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "M0-T17-foundation-makkah-western-L"; home.lifetime = .keepAlways; add(home)
        let content = app.scrollViews.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
        let prayers = [("fajr", "الفجر"), ("dhuhr", "الظهر"), ("asr", "العصر"), ("maghrib", "المغرب"), ("isha", "العشاء")]
        for (index, prayer) in prayers.enumerated() {
            let row = app.descendants(matching: .any).matching(identifier: "foundation-prayer-time-\(prayer.0)").firstMatch
            for _ in 0..<12 {
                if row.exists && row.isHittable { break }
                content.swipeUp()
            }
            XCTAssertTrue(row.exists, app.debugDescription)
            XCTAssertTrue(row.isHittable, app.debugDescription)
            XCTAssertTrue(row.label.hasPrefix("\(prayer.1)، "), row.label)
            XCTAssertTrue(NSPredicate(format: "SELF MATCHES %@", "[^،]+، [0-9]{2}:[0-9]{2}").evaluate(with: row.label), row.label)
            if index == 0 || index == prayers.count - 1 {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "M0-T17-today-\(prayer.0)-makkah-western-L"; screenshot.lifetime = .keepAlways; add(screenshot)
            }
            XCTAssertFalse(app.buttons["foundation-prayer-time-\(prayer.0)"].exists, "Foundation clocks remain read-only.")
        }
        XCTAssertFalse(app.buttons["prayer-log"].exists)
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
    private func selectEnglishKeyboard(_ app: XCUIApplication) throws {
        // XCTest secure typing uses the current keyboard's characters. Observe the
        // real layout before sending this test's Latin fixture passphrase.
        let knownKeys = app.keyboards.keys.matching(NSPredicate(format: "label IN %@", ["ت", "t"] as NSArray))
        let currentKey = try XCTUnwrap(waitForHittableElement(knownKeys, in: app), "A real Arabic or English software keyboard must be visible.")
        if currentKey.label == "t" { return }
        let switchButtons = app.buttons.matching(NSPredicate(format: "label IN %@", ["لوحة المفاتيح التالية", "Next keyboard"] as NSArray))
        let nextKeyboard = try XCTUnwrap(waitForHittableElement(switchButtons, in: app), "The observed native next-keyboard control must be hittable.")
        let nextLayout = nextKeyboard.value as? String ?? ""
        print("M0 native next keyboard: \(nextLayout)")
        // The captured Arabic keyboard announces English (UK). Make one switch;
        // never cycle through unknown layouts or assume a keyboard from locale.
        let englishSwitch = try XCTUnwrap(nextLayout.hasPrefix("English") ? nextKeyboard : nil, "The next keyboard must announce English before selecting it.")
        englishSwitch.tap()
        let englishKeys = app.keyboards.keys.matching(NSPredicate(format: "label == %@", "t"))
        _ = try XCTUnwrap(waitForHittableElement(englishKeys, in: app), "The selected English keyboard must expose a hittable t key.")
    }
    private func waitForHittableElement(_ query: XCUIElementQuery, in app: XCUIApplication) -> XCUIElement? {
        let ready = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                query.allElementsBoundByIndex.contains { self.elementIsOnscreenAndHittable($0, in: app) }
            }
        }
        let readiness = XCTNSPredicateExpectation(predicate: ready, object: nil)
        guard XCTWaiter.wait(for: [readiness], timeout: 10) == .completed else { return nil }
        return query.allElementsBoundByIndex.first { elementIsOnscreenAndHittable($0, in: app) }
    }
    private func elementIsOnscreenAndHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        return frame.width > 0 && frame.height > 0 && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
    private func openBackupSettings(_ app: XCUIApplication) {
        finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let link = app.buttons["backup-settings-link"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["النسخ والاستعادة"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["backup-schedule"].waitForExistence(timeout: 10), app.debugDescription)
        // AX3's plain-export section pushes password cells out of the Form's
        // accessibility tree. Scroll the actual Form before requiring the field.
        scrollBackupForm(to: app.secureTextFields["backup-password"], in: app)
    }
    private func scrollBackupForm(to element: XCUIElement, in app: XCUIApplication, towardsTop: Bool = false) {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<12 {
            if elementIsOnscreenAndHittable(element, in: app) { return }
            if element.exists {
                // A materialized offscreen row gives the direction; otherwise the
                // caller supplies the known section order for virtualized cells.
                if element.frame.midY < form.frame.midY { form.swipeDown() }
                else { form.swipeUp() }
            } else if towardsTop { form.swipeDown() }
            else { form.swipeUp() }
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(elementIsOnscreenAndHittable(element, in: app), app.debugDescription)
    }
    private func openPlainExportSettings(_ app: XCUIApplication) {
        finishOnboarding(app)
        app.buttons["settings-button"].tap()
        let link = app.buttons["backup-settings-link"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["النسخ والاستعادة"].waitForExistence(timeout: 10), app.debugDescription)
        // Form is a CollectionView in the captured AX3 hierarchy. Its offscreen cells
        // are virtualized, so scroll before requiring the export button to exist.
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10), app.debugDescription)
        let export = app.buttons["plain-export-now"]
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
