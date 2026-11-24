import XCTest

@MainActor final class CustomizeSearchUITests: XCTestCase {
    func testClearRestoresSettingsInOneTap() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المظهر")
        let clear = app.buttons["settings-clear-search"]; XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Improve-search-after-L"; attachment.lifetime = .keepAlways; add(attachment)
        clear.tap(); XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(search.value as? String, "المظهر")
        // The settings home (not the old flat list) returns after clearing; its first door is «أقسامك والبهو».
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "أقسامك والبهو")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testLobbyResultDoesNotShowEmptyState() {
        continueAfterFailure = false
        let (app, search) = openSearch()
        search.tap(); search.typeText("البهو\n")
        XCTAssertTrue(app.buttons["bahw-custom-blocks"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(emptyResult(in: app).exists, app.debugDescription)
    }

    func testDeferredSyncSearchShowsEmptyState() {
        continueAfterFailure = false
        let (app, search) = openSearch()
        search.tap(); search.typeText("المزامنة\n")
        XCTAssertTrue(emptyResult(in: app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["sync-settings-link"].exists)
    }

    func testPrivacyPageContainsTheBookIndexSetting() {
        continueAfterFailure = false
        let (app, _) = openSearch()
        let privacy = app.buttons["settings-link-الخصوصية والبحث"]
        for _ in 0..<8 where !privacy.isHittable || privacy.frame.midY > app.frame.maxY - 90 {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(privacy.isHittable, app.debugDescription)
        privacy.tap()
        XCTAssertTrue(app.switches["setting-core.spotlightIndex"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testAdvancedCalendarAndTimesAreAvailableWithoutSearch() {
        continueAfterFailure = false
        let (app, _) = openSearch()
        let advanced = app.descendants(matching: .any)["settings-advanced"].firstMatch
        for _ in 0..<9 where !advanced.isHittable || advanced.frame.midY > app.frame.maxY - 90 {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(advanced.isHittable, app.debugDescription)
        advanced.tap()
        let calendar = app.buttons["settings-link-ضبط التقويم والمواقيت"]
        for _ in 0..<4 where !calendar.isHittable || calendar.frame.midY > app.frame.maxY - 90 {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(calendar.isHittable, app.debugDescription)
        calendar.tap()
        XCTAssertTrue(app.buttons["option-core.hijriSource-ummAlQura"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["قاعدة خطوط العرض العالية"].exists, app.debugDescription)
        XCTAssertFalse(app.switches["setting-core.spotlightIndex"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-advanced-calendar-phone"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuranSearchOpensTheSettingAndReturnsToResults() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_QURAN_FIXTURE": "home",
                                 "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("دورة المراجعة\n")
        let result = app.buttons["room-setting-quran.reviewSchedule"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        result.tap()
        let setting = app.buttons["quran-plan-quran.reviewSchedule"]
        XCTAssertTrue(setting.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(setting.isHittable, app.debugDescription)
        setting.tap()
        let weekly = app.buttons["المنازل الأسبوعية"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 5), app.debugDescription)
        weekly.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "المنازل الأسبوعية"), object: setting)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed)
        let back = app.buttons["quran-screen-close"]
        for _ in 0..<3 where !back.isHittable { app.swipeDown(velocity: .slow) }
        back.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(search.value as? String, "دورة المراجعة")
    }

    func testDiarySearchExpandsAndReachesTheRequestedSetting() {
        continueAfterFailure = false
        let (app, search) = openSearch()
        search.tap()
        search.typeText("محتوى المذكرات\n")
        let result = app.buttons["room-setting-notes.widgetContent"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        result.tap()
        let setting = app.switches["setting-notes.widgetContent"]
        XCTAssertTrue(setting.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(setting.isHittable, app.debugDescription)
        XCTAssertEqual(app.buttons["diary-customize-section-outside"].value as? String, "مفتوح")
    }

    func testHiddenMoneyRoomHasNoSearchResults() {
        continueAfterFailure = false
        let (app, search) = openSearch()
        search.tap(); search.typeText("البهو\n")
        let moneyRoom = app.switches["bahw-custom-visible-mal"]
        XCTAssertTrue(moneyRoom.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !moneyRoom.isHittable || moneyRoom.frame.maxY > app.frame.maxY - 130 {
            app.swipeUp(velocity: .slow)
        }
        moneyRoom.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: moneyRoom)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, app.debugDescription)

        let clear = app.buttons["settings-clear-search"]
        for _ in 0..<8 where !clear.isHittable { app.swipeDown(velocity: .slow) }
        clear.tap()
        search.tap(); search.typeText("يوم الراتب\n")
        XCTAssertTrue(emptyResult(in: app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["room-setting-mal.salaryDay"].exists)
        clear.tap()
        search.tap(); search.typeText("المال\n")
        XCTAssertFalse(app.buttons["money-open"].exists)
    }

    private func openSearch() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "empty", "MADAR_UI_THEME": "light"]
        app.launch()
        let tab = app.buttons["tab-customize"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), app.debugDescription)
        tab.tap()
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        return (app, search)
    }

    private func emptyResult(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings-search-empty"].firstMatch
    }
}
