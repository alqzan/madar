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
            let streaks = app.buttons["prayer-streaks"]
            XCTAssertTrue(streaks.waitForExistence(timeout: 5), app.debugDescription)
            for name in ["الجماعة", "في وقتها", "إتمام الخمس"] { XCTAssertTrue(streaks.label.contains(name), streaks.label) }
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

    /// M1-V08: the same home in the dark theme, for comparison with screens/salah/08-S7-Night(-s1).jpg.
    func test_M1V08_NightHomeMatchesCanonical() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "dark"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let header = app.descendants(matching: .any).matching(identifier: "prayer-today-header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-arch-maghrib").firstMatch.exists)
        attachScreenshot(app, named: "M1-V08-night-L")
        let qiyam = app.buttons["prayer-qiyam"]; scrollTo(qiyam, in: app)
        attachScreenshot(app, named: "M1-V08-night-bottom-L")
        app.terminate()
    }

    /// M1-F01: the Friday home, for comparison with screens/salah/09-S8-Friday(-s1).jpg.
    func test_M1F01_FridayHomeMatchesCanonical() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcaseFriday", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let header = app.descendants(matching: .any).matching(identifier: "prayer-today-header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(header.label.contains("الجمعة"), header.label)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-friday-pill").firstMatch.exists)
        let noon = app.descendants(matching: .any).matching(identifier: "prayer-arch-dhuhr").firstMatch
        XCTAssertTrue(noon.label.contains("الجمعة"), noon.label)
        attachScreenshot(app, named: "M1-F01-friday-L")
        let qada = app.buttons["prayer-qada-makeup"]; scrollTo(qada, in: app)
        attachScreenshot(app, named: "M1-F01-friday-scrolled-L")
        // §7.2 «سطر الكهف» leads to the Quran: the pill opens the mushaf where Al-Kahf begins.
        let pill = app.descendants(matching: .any).matching(identifier: "prayer-friday-pill").firstMatch
        for _ in 0..<6 where !pill.isHittable { app.swipeDown() }
        pill.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "quran-mushaf-page").firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["٢٩٣"].waitForExistence(timeout: 5), app.debugDescription)
        attachScreenshot(app, named: "IMPROVE-friday-kahf-L")
        app.terminate()
    }

    /// M1-F03: the tracking start can be edited once from «خصّص الصلاة»; the second edit is not offered.
    func test_M1F03_TrackingStartEditsOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-13T09:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-10", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let open = app.buttons["prayer-customize"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        let log = app.buttons["prayer-customize-card-log"]; scrollTo(log, in: app); log.tap()
        let edit = app.buttons["prayer-tracking-edit"]; scrollTo(edit, in: app)
        attachScreenshot(app, named: "M1-F03-tracking-L")
        edit.tap()
        attachScreenshot(app, named: "M1-F03-tracking-editing-L")
        let save = app.buttons["prayer-tracking-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let confirm = app.buttons["احفظ البداية"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M1-F03-tracking-confirm-L")
        confirm.tap()
        let done = app.descendants(matching: .any).matching(identifier: "prayer-tracking-done").firstMatch
        _ = done.waitForExistence(timeout: 10)
        attachScreenshot(app, named: "M1-F03-tracking-after-L")
        XCTAssertTrue(done.exists, app.alerts.firstMatch.label + " " + app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | "))
        XCTAssertFalse(app.buttons["prayer-tracking-edit"].exists, "A second edit is not offered")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "prayer-tracking-start").firstMatch.label.contains("-"), "The start shows in words, not ISO")
        attachScreenshot(app, named: "M1-F03-tracking-done-L")
        app.terminate()
    }

    /// M1-F02: «خارج مدينتك» until the one question is answered; then the trip pill and a paired log (RP7).
    func test_M1F02_TravelQuestionPillAndPair() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_THEME": "light",
            "MADAR_UI_TRAVEL_FIX": "51.5074,-0.1278,لندن,GB,Europe/London"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let pill = app.buttons["prayer-travel-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(pill.label.contains("خارج مدينتك"), pill.label)
        attachScreenshot(app, named: "M1-F02-away-L")
        pill.tap()
        let yes = app.buttons["prayer-travel-yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M1-F02-question-L")
        yes.tap()
        let trip = app.buttons["prayer-travel-pill"]
        XCTAssertTrue(trip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'مسافر' AND label CONTAINS 'لندن'").evaluate(with: trip), trip.label)
        let fajr = app.descendants(matching: .any).matching(identifier: "prayer-arch-fajr").firstMatch
        XCTAssertTrue(fajr.waitForExistence(timeout: 8), app.debugDescription)
        let expectedClock = String(try XCTUnwrap(fajr.label.components(separatedBy: "، ").dropFirst().first))
        fajr.tap()
        let logClock = app.staticTexts["prayer-log-clock"]
        XCTAssertTrue(logClock.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M1-F02-trip-log-clock-L")
        XCTAssertEqual(logClock.label, expectedClock, "The log sheet must use the same active-trip clock as the prayer arch")
        app.buttons["prayer-status-alone"].tap()
        let dhuhr = app.descendants(matching: .any).matching(identifier: "prayer-arch-dhuhr").firstMatch
        XCTAssertTrue(dhuhr.label.contains("قصر"), dhuhr.label)
        attachScreenshot(app, named: "M1-F02-trip-L")
        dhuhr.tap()
        let taqdim = app.buttons["prayer-pair-taqdim"]
        XCTAssertTrue(taqdim.waitForExistence(timeout: 8), app.debugDescription)
        taqdim.tap()
        app.buttons["prayer-pair-save"].tap()
        let after = app.descendants(matching: .any).matching(identifier: "prayer-arch-asr").firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'جماعة'").evaluate(with: after) || after.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M1-F02-paired-L")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-arch-dhuhr").firstMatch.label.contains("جماعة"), app.debugDescription)
        app.terminate()
    }

    /// M1-V10: «خصّص الصلاة», for comparison with screens/flex/06-K-Salah(-s1).jpg; order and hide change the home.
    func test_M1V10_CustomizePrayerReordersAndHidesHomeBlocks() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let open = app.buttons["prayer-customize"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        let any = { (id: String) in app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(app.buttons["prayer-streaks"].exists, "The current Hali block is visible by default")
        open.tap()
        XCTAssertTrue(app.buttons["prayer-customize-back"].waitForExistence(timeout: 5), app.debugDescription)
        attachScreenshot(app, named: "M1-V10-customize-L")
        let up = app.buttons["prayer-block-up-qiyam"]; scrollTo(up, in: app)
        up.tap()
        let hali = app.switches["prayer-block-hali"]; scrollTo(hali, in: app)
        hali.tap()
        XCTAssertEqual(hali.value as? String, "0")
        attachScreenshot(app, named: "M1-V10-customize-scrolled-L")
        let remind = app.buttons["prayer-customize-card-remind"]; scrollTo(remind, in: app)
        remind.tap()
        attachScreenshot(app, named: "M1-V10-customize-groups-L")
        let back = app.buttons["prayer-customize-back"]
        for _ in 0..<8 where !back.isHittable { app.swipeDown() }
        back.tap()
        XCTAssertTrue(any("prayer-today-header").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["prayer-streaks"].exists, "A hidden block leaves the home")
        let qiyam = app.buttons["prayer-qiyam"], qada = app.buttons["prayer-qada-makeup"]
        XCTAssertTrue(qiyam.exists && qada.exists, app.debugDescription)
        XCTAssertLessThan(qiyam.frame.minY, qada.frame.minY, "Qiyam moved above qada")
        app.terminate()
    }

    /// M1-V02: the light log sheet, for comparison with screens/salah/02-S2-Log.jpg.
    func test_M1V02_LogSheetMatchesCanonicalAndRecordsInOneTap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let asr = app.descendants(matching: .any).matching(identifier: "prayer-arch-asr").firstMatch
        XCTAssertTrue(asr.waitForExistence(timeout: 10), app.debugDescription)
        asr.tap()
        let alone = app.buttons["prayer-status-alone"]
        XCTAssertTrue(alone.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alone.isSelected, "Asr is already logged alone")
        XCTAssertFalse(app.buttons["prayer-status-missed"].exists, "RP2: no «فاتتني» before the window ends")
        XCTAssertFalse(app.buttons["prayer-heart-present"].exists, "RP6: heart question off by default")
        attachScreenshot(app, named: "M1-V02-log-L")
        XCTAssertFalse(app.buttons["prayer-clear"].exists, "«امسح التسجيل» is not a v1 action")
        // One tap re-records; the sheet closes and the home reflects it.
        app.buttons["prayer-status-jamaah"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "جماعة"), object: asr)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed, asr.label)
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["undo-button"].tap()
        // The companion canonical shows the optional heart question. Enable it
        // through the real setting in this isolated store, preserving RP6's default.
        app.terminate(); app.launch(); finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let search = app.textFields["settings-search"]
        scrollTo(search, in: app); search.tap(); search.typeText("salah.askHeart\n")
        let toggle = app.switches["setting-salah.askHeart"]
        scrollTo(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0"); toggle.tap()
        app.swipeDown(); app.tabBars.buttons["الصلاة"].tap()
        XCTAssertTrue(asr.waitForExistence(timeout: 10), app.debugDescription)
        asr.tap()
        XCTAssertTrue(alone.waitForExistence(timeout: 10)); XCTAssertTrue(alone.isSelected)
        XCTAssertTrue(app.buttons["prayer-heart-present"].waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M1-V02-log-heart-L")
        app.terminate()
    }

    /// M1-V03: «فاتتني» opens the make-up panel and saves nothing until a choice, for screens/salah/03-S2b-Missed.jpg.
    func test_M1V03_MissedPanelOpensWithoutSaving() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-13T09:00:00+03:00"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let fajr = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "الفجر")).firstMatch
        XCTAssertTrue(fajr.waitForExistence(timeout: 10), app.debugDescription)
        fajr.tap()
        let missed = app.buttons["prayer-status-missed"]
        XCTAssertTrue(missed.waitForExistence(timeout: 10), "Fajr's window has ended, so «فاتتني» is offered (RP2)")
        missed.tap()
        XCTAssertTrue(app.buttons["prayer-makeup-now"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["prayer-missed-later"].exists)
        XCTAssertFalse(app.buttons["undo-button"].exists, "Nothing is saved until «قضيتُها الآن» or «لاحقًا»")
        attachScreenshot(app, named: "M1-V03-missed-L")
        // Companion -s1: the sheet scrolled to «قضيتُها الآن» / «لاحقًا» / «امسح التسجيل».
        app.buttons["prayer-makeup-now"].swipeUp()
        XCTAssertTrue(app.buttons["prayer-missed-later"].isHittable, app.debugDescription)
        attachScreenshot(app, named: "M1-V03-missed-L-s1")
        app.terminate()
    }

    /// M1-V04: «حالي», for comparison with screens/salah/04-S3-Hali(-s1).jpg.
    func test_M1V04_HaliMatchesCanonical() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "ratio26of30", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        openHali(app)
        XCTAssertTrue(app.staticTexts["prayer-stat-percentage"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["prayer-hali-back"].exists)
        XCTAssertTrue(app.staticTexts["حالي"].exists)
        attachScreenshot(app, named: "M1-V04-hali-L")
        let month = app.staticTexts["prayer-history-month"]
        scrollTo(month, in: app)
        app.swipeUp()
        attachScreenshot(app, named: "M1-V04-hali-scrolled-L")
        app.terminate()
    }

    /// M1-V01: «سلاسلك» opens the streak details: meaning, last seven days, and why each streak broke.
    func test_M1V01_StreakDetailsSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-08T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "streakShowcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let streaks = app.buttons["prayer-streaks"]
        scrollTo(streaks, in: app); app.swipeUp()
        // Hand-worked week (PrayerStreakTests): congregation 2, on time 3, completion 6.
        let label = streaks.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        XCTAssertTrue(label.contains("الجماعة يومان"), label)
        XCTAssertTrue(label.contains("في وقتها ٣ أيام"), label)
        XCTAssertTrue(label.contains("إتمام الخمس ٦ أيام"), label)
        attachScreenshot(app, named: "M1-V01-streaks-card-L")
        streaks.tap()
        XCTAssertTrue(app.staticTexts["prayer-streaks-title"].waitForExistence(timeout: 10), app.debugDescription)
        for level in ["congregation", "onTime", "completion"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-streak-\(level)").firstMatch.exists, level)
        }
        attachScreenshot(app, named: "M1-V01-streaks-sheet-L")
        let hali = app.buttons["prayer-history"]
        scrollTo(hali, in: app); hali.tap()
        XCTAssertTrue(app.staticTexts["prayer-stat-percentage"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
    }

    /// M1-V01: a longer week for the «سلاسلك» arch (hand-authored fixture: congregation 9, on time 16, completion 24).
    func test_M1V01_StreakArchMonth() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-08T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-09-12",
            "MADAR_UI_PRAYER_FIXTURE": "streakShowcaseMonth", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let streaks = app.buttons["prayer-streaks"]
        scrollTo(streaks, in: app); app.swipeUp()
        let label = streaks.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        XCTAssertTrue(label.contains("الجماعة ٩ أيام"), label)
        XCTAssertTrue(label.contains("في وقتها ١٦ يومًا"), label)
        XCTAssertTrue(label.contains("إتمام الخمس ٢٤ يومًا"), label)
        attachScreenshot(app, named: "M1-V01-streaks-month-L")
        app.terminate()
    }

    /// Dark mode of the prayer home (arches and «سلاسلك»), captured for a quick look.
    func test_M1V01_HomeDark() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "dark"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        XCTAssertTrue(app.buttons["prayer-streaks"].waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M1-V01-home-dark")
        let streaks = app.buttons["prayer-streaks"]; scrollTo(streaks, in: app); app.swipeUp()
        attachScreenshot(app, named: "M1-V01-streak-dark")
        app.terminate()
    }

    /// M1-V05: the past-day sheet, for comparison with screens/salah/05-S4-Day(-s1).jpg.
    func test_M1V05_DaySheetMatchesCanonical() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "ratio26of30", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        openHali(app)
        let day = app.buttons["prayer-history-day-2026-10-06"]
        scrollTo(day, in: app); day.tap()
        XCTAssertTrue(app.buttons["prayer-day-fajr-jamaah"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-day-header").firstMatch.exists)
        attachScreenshot(app, named: "M1-V05-day-L")
        app.swipeUp()
        attachScreenshot(app, named: "M1-V05-day-L-s1")
        app.terminate()
    }

    /// M1-V06: the qada sheet, for comparison with screens/salah/06-S5-Qada.jpg; also choosing a specific one (T10).
    func test_M1V06_QadaSheetChoosesSpecificPrayerAndUndoes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T20:00:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "ratio26of30", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let places = app.buttons["prayer-qada-places"]; scrollTo(places, in: app); places.tap()
        XCTAssertTrue(app.staticTexts["prayer-qada-title"].waitForExistence(timeout: 10), app.debugDescription)
        let isha = app.buttons["prayer-qada-row-2026-10-06-isha"]
        XCTAssertTrue(isha.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["prayer-qada-row-2026-10-06-maghrib"].exists)
        attachScreenshot(app, named: "M1-V06-qada-L")
        // Companion -s1: the sheet scrolled to its rows and the two actions.
        app.staticTexts["prayer-qada-title"].swipeUp()
        XCTAssertTrue(app.buttons["prayer-qada-makeup-chosen"].waitForExistence(timeout: 5), app.debugDescription)
        attachScreenshot(app, named: "M1-V06-qada-L-s1")
        isha.tap()
        XCTAssertTrue(isha.isSelected)
        app.buttons["prayer-qada-makeup-chosen"].tap()
        let confirm = app.buttons["prayer-makeup-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.tap()
        let undo = app.buttons["undo-button"]; XCTAssertTrue(undo.waitForExistence(timeout: 15), app.debugDescription)
        undo.tap()
        app.terminate()
    }

    func testPrayerSheetReadFailureRetriesIntoTheRealQiyamFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-08T02:10:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-07",
            "MADAR_UI_THEME": "light", "MADAR_UI_PRAYER_READ_FAILURE_ONCE": "1"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let qiyam = app.buttons["prayer-qiyam"]; scrollTo(qiyam, in: app); qiyam.tap()
        let retry = app.buttons["prayer-snapshot-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["prayer-snapshot-close"].exists)
        XCTAssertFalse(app.buttons["prayer-qiyam-save"].exists)
        attachScreenshot(app, named: "M1-read-failure-L")
        retry.tap()
        let plus = app.buttons["prayer-qiyam-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), app.debugDescription)
        plus.tap(); XCTAssertEqual(app.staticTexts["prayer-qiyam-count"].label, "٢")
        attachScreenshot(app, named: "M1-read-recovered-qiyam-L")
        app.buttons["prayer-qiyam-save"].tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["undo-button"].tap()
    }

    func testPrayerCaptureRequestSurvivesReadFailureAndRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01",
            "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light",
            "MADAR_UI_PRAYER_READ_FAILURE_ONCE": "1", "MADAR_UI_PRAYER_OPEN_REQUEST": "asr"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let retry = app.alerts.buttons["أعد المحاولة"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M1-request-read-failure-L")
        retry.tap()
        let alone = app.buttons["prayer-status-alone"]
        XCTAssertTrue(alone.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alone.isSelected, "Retry opens Asr's existing log, without recording a guessed status")
        attachScreenshot(app, named: "M1-request-read-recovered-L")
        app.buttons["prayer-status-jamaah"].tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["undo-button"].tap()
    }

    /// M1-V07: the qiyam sheet, for comparison with screens/salah/07-S6-Qiyam(-s1).jpg.
    func test_M1V07_QiyamSheetMatchesCanonical() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-08T02:10:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-07", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
        let qiyam = app.buttons["prayer-qiyam"]; scrollTo(qiyam, in: app); qiyam.tap()
        XCTAssertTrue(app.buttons["prayer-qiyam-plus"].waitForExistence(timeout: 10), app.debugDescription)
        let nightPicker = app.buttons["prayer-qiyam-night"]
        XCTAssertTrue(nightPicker.exists, app.debugDescription)
        XCTAssertTrue(nightPicker.label.contains("،"), nightPicker.label)
        XCTAssertTrue(nightPicker.label.contains("ربيع") && nightPicker.label.contains("أكتوبر"), nightPicker.label)
        XCTAssertFalse(nightPicker.label.contains("-"), "Night labels use words rather than ISO: \(nightPicker.label)")
        XCTAssertFalse(app.buttons["ورد القيام من محفوظك"].exists, "The Quran room is not built, so it has no entry point")
        attachScreenshot(app, named: "M1-V07-qiyam-L")
        app.terminate()
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
            let sheetTitle = app.staticTexts["prayer-qada-title"]
            sheetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
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
            app.launch(); finishOnboarding(app); app.buttons["tab-customize"].tap()
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
            app.terminate(); app.launch(); finishOnboarding(app); app.buttons["tab-customize"].tap()
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
            app.buttons["tab-customize"].tap()
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
            openHali(app)
            let day = app.buttons["prayer-history-day-2026-10-06"]
            scrollTo(day, in: app); day.tap()
            app.buttons["prayer-history-log-fajr"].tap()
            XCTAssertTrue(present.waitForExistence(timeout: 10)); XCTAssertTrue(present.isSelected)
            scrollTo(skip, in: app)
            let skipReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: skip)
            XCTAssertEqual(XCTWaiter.wait(for: [skipReady], timeout: 10), .completed)
            skip.tap()
            let skipClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
            XCTAssertEqual(XCTWaiter.wait(for: [skipClosed], timeout: 10), .completed, app.debugDescription)
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
            openHali(app)
            let ratio = app.staticTexts["prayer-stat-percentage"]
            XCTAssertTrue(ratio.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(ratio.label, "٨٧٪")
            let qada = app.staticTexts["prayer-stat-qada"]
            scrollTo(qada, in: app)
            XCTAssertEqual(qada.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }, "قُضيت ٢، عليك ٢")
            attachScreenshot(app, named: "M1-T05-hali-\(size)")
            let day = app.buttons["prayer-history-day-2026-10-06"]
            scrollTo(day, in: app); attachScreenshot(app, named: "M1-T05-history-\(size)"); day.tap()
            let alone = app.buttons["prayer-day-isha-alone"]
            XCTAssertTrue(alone.waitForExistence(timeout: 10), app.debugDescription); alone.tap()
            let undo = app.buttons["undo-button"]
            XCTAssertTrue(undo.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(alone.isSelected, "The edited prayer shows its new state in the day sheet")
            XCTAssertTrue(ratio.waitForExistence(timeout: 10)); XCTAssertEqual(ratio.label, "٩٠٪", "The figures follow the edit without reopening")
            let header = app.descendants(matching: .any).matching(identifier: "prayer-day-header").firstMatch
            let grabber = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width / 2, dy: header.frame.minY - 24))
            grabber.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width / 2, dy: app.frame.height - 10)))
            let back = app.buttons["prayer-hali-back"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            for _ in 0..<12 where !back.isHittable { app.swipeDown() }
            back.tap()
            undo.tap()
            openHali(app)
            XCTAssertTrue(ratio.waitForExistence(timeout: 10)); XCTAssertEqual(ratio.label, "٨٧٪")
            app.terminate(); app.launch(); finishOnboarding(app); app.tabBars.buttons["الصلاة"].tap()
            openHali(app)
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
        let settings = app.buttons["tab-customize"]
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

    func test_M0T10_TodayPrayerTimesAtDefaultAndDark() throws {
        continueAfterFailure = false
        for (size, theme) in [("L", "light"), ("L", "dark")] {
            let app = XCUIApplication()
            app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
            app.launchEnvironment["MADAR_UI_SIZE"] = size
            app.launchEnvironment["MADAR_UI_THEME"] = theme
            app.launchEnvironment["MADAR_UI_NOW"] = "2026-10-15T12:00:00+03:00"
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
            XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 10))
            app.buttons["tab-customize"].tap()
            let changes = app.staticTexts["customization-changes"]
            XCTAssertTrue(changes.waitForExistence(timeout: 10))
            // Ordinary UI stores explicitly set the app lock to none; that is
            // one saved change from the owner's biometric-default setting.
            XCTAssertEqual(changes.label, "تعديل واحد عن المتفق عليه")
            attachScreenshot(app, named: "M0-RU3-fixture-baseline-\(size)")
            let edits = [
                ("core.theme", "light", "تعديلان عن المتفق عليه"),
                ("core.firstCalendar", "hijri", "\u{2068}٣\u{2069} تعديلات عن المتفق عليه"),
                ("core.numerals", "western", "\u{2068}4\u{2069} تعديلات عن المتفق عليه")
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
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
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
        app.buttons["tab-customize"].tap()
        let search = app.textFields["settings-search"]
        search.tap(); search.typeText("core.faceIDLock\n")
        let wholeApp = app.buttons["option-core.faceIDLock-app"]
        XCTAssertTrue(wholeApp.waitForExistence(timeout: 10)); wholeApp.tap()
        let gate = app.descendants(matching: .any)["protected-lock-screen"]
        let cover = app.buttons["scene-lock-authenticate"]
        XCTAssertTrue(gate.waitForExistence(timeout: 10) || cover.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["tab-customize"].exists)
        app.terminate()
        // Keep the saved scope: ordinary UI launches otherwise explicitly stage none.
        app.launchEnvironment["MADAR_UI_PRESERVE_FACE_ID_DEFAULT"] = "1"
        app.launch()
        XCTAssertTrue(gate.waitForExistence(timeout: 10) || cover.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["tab-customize"].exists)
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
    func testFirstRunAndNativeRoomSectionOpensBuiltRooms() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MADAR_UI_STORE_ID"] = UUID().uuidString
        app.launch()
        finishOnboarding(app)
        let settings = app.buttons["tab-customize"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["الصلاة"].exists, "The M1 prayer screen is the first built room.")
        XCTAssertTrue(app.tabBars.buttons["القرآن"].exists, "M2 Quran home is now built.")
        let mihbara = app.tabBars.buttons["المحبرة"]
        XCTAssertTrue(mihbara.waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(app, named: "M0-native-glass-room-shortcuts-L")
        mihbara.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["reset-settings"].waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(app, named: "M0-customize-RTL")
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
        let fajr = app.buttons["prayer-gap-status-2026-10-01-fajr"]
        XCTAssertTrue(fajr.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["prayer-gap-save"].isEnabled, "Nothing chosen yet, nothing to save")
        // One tap settles the whole gap and closes the sheet (RP1: only by explicit choice).
        bulkUnrecorded.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 15), app.debugDescription)
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
                XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 15))
                let home = XCTAttachment(screenshot: app.screenshot()); home.name = "M0-home-\(theme)-\(size)"; home.lifetime = .keepAlways; add(home)
                app.buttons["tab-customize"].tap()
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
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let newSearch = app.textFields["settings-search"]
        newSearch.tap(); newSearch.typeText("core.theme\n")
        XCTAssertTrue(app.buttons["option-core.theme-dark"].isSelected)
        app.buttons["settings-clear-search"].tap()
        let resetSettings = app.buttons["reset-settings"]
        scrollTo(resetSettings, in: app); resetSettings.tap()
        app.buttons["أعِد الافتراضي"].firstMatch.tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 10))
        scrollTo(newSearch, in: app); newSearch.tap(); newSearch.typeText("core.theme\n")
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
        app.buttons["settings-clear-search"].tap()
        let resetSettings = app.buttons["reset-settings"]
        scrollTo(resetSettings, in: app); resetSettings.tap()
        let reset = app.buttons["أعِد الافتراضي"].firstMatch
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
        app.buttons["tab-customize"].tap()
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
        let form = app.scrollViews.firstMatch // The backup screen is a Madar paper scroll view, not a grouped Form.
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
        app.buttons["tab-customize"].tap()
        let link = app.buttons["backup-settings-link"]
        scrollTo(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["النسخ والاستعادة"].waitForExistence(timeout: 10), app.debugDescription)
        // Form is a CollectionView in the captured AX3 hierarchy. Its offscreen cells
        // are virtualized, so scroll before requiring the export button to exist.
        let form = app.scrollViews.firstMatch // The backup screen is a Madar paper scroll view, not a grouped Form.
        XCTAssertTrue(form.waitForExistence(timeout: 10), app.debugDescription)
        let export = app.buttons["plain-export-now"]
        for _ in 0..<12 {
            if export.exists && export.isHittable { return }
            form.swipeUp()
        }
        XCTAssertTrue(export.exists, app.debugDescription)
        XCTAssertTrue(export.isHittable, app.debugDescription)
    }
    /// Home «سلاسلك» → details sheet → «حالي».
    private func openHali(_ app: XCUIApplication) {
        let streaks = app.buttons["prayer-streaks"]
        scrollTo(streaks, in: app); streaks.tap()
        let hali = app.buttons["prayer-history"]
        XCTAssertTrue(hali.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(hali, in: app); hali.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { break }
            app.swipeUp()
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
