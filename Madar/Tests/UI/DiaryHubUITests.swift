import XCTest
@MainActor final class DiaryHubUITests: XCTestCase {
    func testYearMonthDayTimelinePhotosAndCalendarPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        showDayView("calendar", app)
        let yearScale = app.buttons["diary-calendar-scale-year"]
        let monthScale = app.buttons["diary-calendar-scale"]
        XCTAssertTrue(yearScale.waitForExistence(timeout: 10)); XCTAssertTrue(yearScale.isSelected); XCTAssertFalse(monthScale.isSelected)
        XCTAssertTrue(app.buttons["diary-month-10"].waitForExistence(timeout: 10)); capture(app,"M3-V07-hub-L")
        monthScale.tap(); XCTAssertTrue(monthScale.isSelected); XCTAssertFalse(yearScale.isSelected)
        yearScale.tap(); XCTAssertTrue(yearScale.isSelected); XCTAssertFalse(monthScale.isSelected)
        let october = app.buttons["diary-month-10"]
        for _ in 0..<4 where !october.isHittable { app.swipeUp(velocity: .slow) }
        app.swipeUp(velocity: .slow)
        capture(app, "M3-V07-year-october-L")
        october.tap(); let day = app.buttons["diary-calendar-day-2026-10-15"]; XCTAssertTrue(day.waitForExistence(timeout: 5)); capture(app,"M3-V07-month-L"); day.tap()
        XCTAssertTrue(app.buttons["diary-day-write"].waitForExistence(timeout: 10)); app.closeDiaryDay()
        showDayView("timeline", app); XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'diary-hub-day-'")).firstMatch.waitForExistence(timeout: 10), "«الأيام» lists the past days: \(app.debugDescription)"); XCTAssertFalse(app.buttons["diary-hub-day-2026-10-15"].exists, "Today is not a past day"); capture(app,"M3-V07-timeline-L")
        showDayView("photos", app); XCTAssertTrue(app.images.count > 0); capture(app,"M3-V07-photos-L")
        showDayView("calendar", app); yearScale.tap()
        let hijri = app.buttons["diary-calendar-hijri"]; for _ in 0..<4 where !hijri.isHittable { app.swipeUp() }; hijri.tap()
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["diary-hub-year"].label,"١٤٤٨")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        showDayView("calendar", app)
        XCTAssertTrue(app.staticTexts["diary-hub-year"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["diary-hub-year"].label,"١٤٤٨")
    }
    func testIndexYearsShowBothCalendars() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "editor", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25)); app.buttons["diary-days"].tap()
        XCTAssertTrue(app.buttons["diary-hub-view-menu"].waitForExistence(timeout: 10)); capture(app, "M3-V07-index-calendar-L")
        selectHubTab("index", app)
        let gregorianYear = app.descendants(matching: .any)["diary-hub-index-year-2026"]
        XCTAssertTrue(gregorianYear.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(gregorianYear.label.contains(" م") && gregorianYear.label.contains(" هـ"), gregorianYear.label)
        capture(app, "M3-V07-index-gregorian-L")

        selectHubTab("timeline", app); showDayView("calendar", app)
        let hijri = app.buttons["diary-calendar-hijri"]
        for _ in 0..<5 where !hijri.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(hijri.isHittable, app.debugDescription); hijri.tap()
        selectHubTab("index", app)
        let hijriYear = app.descendants(matching: .any)["diary-hub-index-year-1448"]
        XCTAssertTrue(hijriYear.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(hijriYear.label.contains(" هـ") && hijriYear.label.contains(" م"), hijriYear.label)
        capture(app, "M3-V07-index-hijri-L")
    }

    func testAudioOnlyDayAppearsInYearsAndCalendar() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "audioOnlyYear",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch()
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["diary-days"].tap()
        selectHubTab("index", app)

        let year = app.buttons["diary-hub-index-year-2025"]
        XCTAssertTrue(year.waitForExistence(timeout: 10), "An audio-only day must still create a year card: \(app.debugDescription)")
        XCTAssertTrue(year.label.contains("تسجيل صوتي محفوظ من هذا اليوم"), year.label)
        capture(app, "OWNER-diary-audio-only-year-L")
        year.tap()

        let monthScale = app.buttons["diary-calendar-scale"]
        XCTAssertTrue(monthScale.waitForExistence(timeout: 10), app.debugDescription)
        monthScale.tap()
        let audioDay = app.buttons["diary-calendar-day-2025-06-15"]
        XCTAssertTrue(audioDay.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(audioDay.value as? String, "فيه ذكرى محفوظة")
        capture(app, "OWNER-diary-audio-only-calendar-L")
    }

    /// Owner trial, 22 Oct 2026. Runs only when TEST_RUNNER_MADAR_TRIAL_ZIP names the converted old-Madar diary; it
    /// imports into a fresh UI-test store through the shipped Day One importer and captures the rooms at real volume.
    func testOwnerLegacyDiaryTrial() throws {
        let env = ProcessInfo.processInfo.environment
        guard let zip = env["MADAR_TRIAL_ZIP"] else { throw XCTSkip("Owner data trial only") }
        let report = zip + ".report.json"; try? FileManager.default.removeItem(atPath: report)
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_LEGACY_DIARY_ZIP": zip, "MADAR_UI_LEGACY_REPORT": report,
            "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let deadline = Date().addingTimeInterval(600)
        while !FileManager.default.fileExists(atPath: report) && Date() < deadline { _ = app.wait(for: .runningForeground, timeout: 2); Thread.sleep(forTimeInterval: 2) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: report), "No trial report")
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: report))) as? [String: Any])
        XCTAssertNil(result["error"], "The local trial reported an error; inspect its private report on this Mac")
        let store = try XCTUnwrap(result["store"] as? [String: Int])
        XCTAssertGreaterThan(store["entries"] ?? 0, 0)
        XCTAssertEqual(store["legacyPolicy"], store["entries"], "Every imported entry retains its stored legacy day")
        let exported = try XCTUnwrap(result["export"] as? [String: Any])
        XCTAssertEqual(exported["days"] as? Int, store["days"], "The whole imported diary must be exportable")
        let notes = app.buttons["tab-notes"]; XCTAssertTrue(notes.waitForExistence(timeout: 20), app.debugDescription); notes.tap()
        let next = app.buttons["diary-welcome-next"]
        if next.waitForExistence(timeout: 5) { capture(app, "TRIAL-diary-welcome-L"); for _ in 0..<6 where next.exists { next.tap(); _ = app.buttons["diary-days"].waitForExistence(timeout: 2) } }
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 20), app.debugDescription); capture(app, "TRIAL-diary-home-L")
        app.swipeUp(velocity: .slow); capture(app, "TRIAL-diary-home-s1-L"); app.swipeDown(velocity: .slow); app.swipeDown(velocity: .slow)
        let opened = Date(); app.buttons["diary-days"].tap()
        XCTAssertTrue(app.buttons["diary-hub-view-menu"].waitForExistence(timeout: 30)); capture(app, "TRIAL-diary-hub-L")
        add(XCTAttachment(string: "hub opened in \(Date().timeIntervalSince(opened)) s"))
        capture(app, "TRIAL-diary-timeline-L")
        showDayView("photos", app); capture(app, "TRIAL-diary-photos-L")
    }
    private func capture(_ app: XCUIApplication,_ name:String) { let shot = XCTAttachment(screenshot:app.screenshot()); shot.name=name; shot.lifetime = .keepAlways; add(shot) }
    /// Since 14 Nov the archive opens on «الأيام»; the calendar and photos are views chosen from «طريقة العرض».
    private func showDayView(_ id: String, _ app: XCUIApplication) {
        let menu = app.buttons["diary-hub-view-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription); menu.tap()
        let option = app.buttons["diary-hub-view-" + id]
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription); option.tap()
    }
    private func selectHubTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.buttons["diary-hub-" + name]
        for _ in 0..<6 where !tab.isHittable { app.swipeLeft() }
        for _ in 0..<6 where !tab.isHittable { app.swipeRight() }
        XCTAssertTrue(tab.isHittable, app.debugDescription); tab.tap()
    }
}
