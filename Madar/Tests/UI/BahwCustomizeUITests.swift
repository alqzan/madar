import XCTest

/// M4-V04 · bahw/05-W4-Takhsis: customise shows the live lobby model, sizes and hides blocks through `bahw.layout`, and reset restores it.
@MainActor final class BahwCustomizeUITests: XCTestCase {
    func testBlocksSizeHideAndReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00",
                                 "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(app.buttons["tab-customize"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["tab-customize"].tap()
        XCTAssertTrue(element("bahw-custom-blocks").waitForExistence(timeout: 10), app.debugDescription)
        for block in ["habits", "salah", "quran", "mal", "year", "upcoming", "notes", "mihbara"] {
            XCTAssertTrue(element("bahw-custom-block-" + block).exists, block)
        }
        capture(app, "M4-V04-customize-L")
        app.swipeUp(); capture(app, "M4-V04-customize-s1-L"); app.swipeUp(); capture(app, "M4-V04-customize-s2-L")
        app.swipeDown(); app.swipeDown()
        // Keep taps clear of the tab bar.
        func reveal(_ e: XCUIElement) { var n = 0; while n < 6 && (!e.isHittable || e.frame.maxY > app.frame.maxY - 150) { app.swipeUp(velocity: .slow); n += 1 } }
        func revealUp(_ e: XCUIElement) { var n = 0; while n < 6 && (!e.isHittable || e.frame.minY < 80) { app.swipeDown(velocity: .slow); n += 1 } }

        let wide = app.buttons["bahw-custom-size-quran-wide"]; XCTAssertTrue(wide.waitForExistence(timeout: 5)); reveal(wide); wide.tap()
        XCTAssertTrue(wide.isSelected)
        let visible = app.switches["bahw-custom-visible-year"]; reveal(visible); visible.tap()
        XCTAssertEqual(visible.value as? String, "0")
        revealUp(element("bahw-custom-open-lobby")); element("bahw-custom-open-lobby").tap()
        XCTAssertTrue(element("bahw-block-quran").waitForExistence(timeout: 8))
        XCTAssertFalse(element("bahw-block-year").exists)

        let customizeTab = app.buttons["tab-customize"]
        if customizeTab.exists { customizeTab.tap() } else {
            let shortcut = app.buttons["tab-customize"]; XCTAssertTrue(shortcut.waitForExistence(timeout: 8)); shortcut.tap()
        }
        let reset = app.buttons["reset-settings"]; XCTAssertTrue(reset.waitForExistence(timeout: 8)); reset.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "أعِد الافتراضي", "reset-settings")).firstMatch; XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["bahw-custom-size-quran-small"].waitForExistence(timeout: 5)); reveal(app.buttons["bahw-custom-size-quran-small"])
        XCTAssertTrue(app.buttons["bahw-custom-size-quran-small"].isSelected)
        XCTAssertEqual(app.switches["bahw-custom-visible-year"].value as? String, "1")
    }

    func testHabitReminderDefaultUndoAndNewHabit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        func openReminderSettings() {
            let customize = app.buttons["tab-customize"]
            XCTAssertTrue(customize.waitForExistence(timeout: 15), app.debugDescription); customize.tap()
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("bahw.reminder\n")
        }
        func waitSelected(_ element: XCUIElement) {
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, app.debugDescription)
        }
        openReminderSettings()
        let dot = app.buttons["option-bahw.reminder-dot"], push = app.buttons["option-bahw.reminder-push"]
        XCTAssertTrue(dot.waitForExistence(timeout: 10), app.debugDescription); XCTAssertTrue(dot.isSelected)
        push.tap(); waitSelected(push)
        let undo = app.buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10)); undo.tap(); waitSelected(dot)
        push.tap(); waitSelected(push)
        capture(app, "OR-03-habit-reminder-settings-L")
        app.terminate(); app.launch(); finishOnboarding(app); openReminderSettings(); waitSelected(push)

        app.tabBars.buttons["البهو"].tap()
        let openHabits = app.buttons["bahw-habits-open"]
        XCTAssertTrue(openHabits.waitForExistence(timeout: 10)); openHabits.tap()
        let first = app.buttons["habit-first"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("عادة جديدة")
        let reminder = app.descendants(matching: .any)["habit-reminder"]
        for _ in 0..<6 where !reminder.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reminder.isHittable, app.debugDescription)
        XCTAssertTrue(reminder.label.contains("إشعار لطيف"), app.debugDescription)
        XCTAssertTrue(app.staticTexts["حدّد وقت العادة واسمح بالإشعارات ليصل التذكير."].exists)
        capture(app, "OR-03-new-habit-reminder-L")

        // Linked habits are read from their owning room; the scheduler does not send this custom-habit alert for them.
        let source = app.buttons["habit-source"]
        for _ in 0..<6 where !source.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(source.isHittable, app.debugDescription); source.tap()
        app.buttons["الجماعة من الصلاة"].tap()
        for _ in 0..<6 where !reminder.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reminder.isHittable, app.debugDescription)
        XCTAssertTrue(reminder.label.contains("نقطة في البهو"), app.debugDescription)
        reminder.tap()
        XCTAssertFalse(app.buttons["إشعار لطيف"].exists, app.debugDescription)
        app.buttons["نقطة في البهو"].tap()
        for _ in 0..<6 where !source.isHittable { app.swipeDown(velocity: .slow) }
        source.tap(); app.buttons["أسجّلها هنا"].tap()
        for _ in 0..<6 where !reminder.isHittable { app.swipeUp(velocity: .slow) }
        reminder.tap(); app.buttons["إشعار لطيف"].tap()
        app.buttons["habit-save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "عادة جديدة،")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription); row.tap()
        let edit = app.buttons["habit-edit"]
        for _ in 0..<6 where !edit.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(edit.isHittable, app.debugDescription); edit.tap()
        for _ in 0..<6 where !reminder.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reminder.isHittable, app.debugDescription)
        XCTAssertTrue(reminder.label.contains("إشعار لطيف"), app.debugDescription)
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
