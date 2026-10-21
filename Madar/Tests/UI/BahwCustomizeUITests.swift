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
    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
