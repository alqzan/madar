import XCTest

@MainActor final class WidgetMakerUITests: XCTestCase {
    private func reach(_ app: XCUIApplication, _ item: XCUIElement) {
        for _ in 0..<10 {
            if item.isHittable && item.frame.maxY < app.frame.maxY - 140 { return }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func open(_ app: XCUIApplication) {
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        if app.buttons["settings-clear-search"].exists { app.buttons["settings-clear-search"].tap() }
        search.tap(); search.typeText("اصنع ودجة\n")
        let maker = app.buttons["widget-maker-open"]; XCTAssertTrue(maker.waitForExistence(timeout: 10)); maker.tap()
        XCTAssertTrue(app.staticTexts["widget-maker-title"].waitForExistence(timeout: 10))
    }
    func testNamedWidgetContentStyleRelaunchDeleteAndUndo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "showcase",
                                 "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_MIHBARA_FIXTURE": "home",
                                 "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); open(app)
        XCTAssertFalse(app.buttons["widget-maker-save"].isEnabled)
        capture(app, "OR-03-X3-empty-L")
        for id in ["prayerNext", "habitsToday", "moneyNow"] { let item = app.buttons["widget-item-" + id]; reach(app, item); item.tap() }
        for _ in 0..<8 { if app.staticTexts["widget-maker-title"].isHittable { break }; app.swipeDown(velocity: .slow) }
        capture(app, "OR-03-X3-manuscript-L")
        let ink = app.segmentedControls.buttons["حبر"]; reach(app, ink); ink.tap()
        let green = app.buttons["widget-color-green"]; reach(app, green); green.tap()
        let field = app.textFields["widget-maker-name"]; field.tap(); field.typeText("ميزان يومي\n")
        let save = app.buttons["widget-maker-save"]; XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["widget-maker-status"].waitForExistence(timeout: 15))
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "widget-saved-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); reach(app, saved); capture(app, "OR-03-X3-saved-L")
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15)); reach(app, saved); saved.tap()
        XCTAssertEqual(app.textFields["widget-maker-name"].value as? String, "ميزان يومي")
        reach(app, green); XCTAssertTrue(green.isSelected)
        XCTAssertTrue(ink.isSelected)
        capture(app, "OR-03-X3-style-reopened-L")
        for _ in 0..<8 { if app.staticTexts["widget-maker-title"].isHittable { break }; app.swipeDown(velocity: .slow) }
        XCTAssertTrue(app.staticTexts["widget-maker-title"].isHittable)
        capture(app, "OR-03-X3-preview-L")
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "widget-delete-")).firstMatch
        reach(app, delete); delete.tap()
        let confirm = app.buttons["احذفها"]; XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 10))
        let undo = app.buttons["widget-maker-undo"]; reach(app, undo); undo.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        reach(app, saved); capture(app, "OR-03-X3-restored-L")
    }
    func testSavedLobbyPresetKeepsItsSizeAndOpensHabits() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "showcase",
                                 "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); open(app)
        let surface = app.segmentedControls.buttons["البهو"]; reach(app, surface); surface.tap()
        let small = app.segmentedControls.buttons["صغيرة"]; reach(app, small); small.tap()
        let habits = app.buttons["widget-item-habitsToday"]; reach(app, habits); habits.tap()
        let name = app.textFields["widget-maker-name"]; name.tap(); name.typeText("عادات البهو\n")
        app.buttons["widget-maker-save"].tap()
        XCTAssertTrue(app.staticTexts["widget-maker-status"].waitForExistence(timeout: 15))
        app.buttons["widget-maker-close"].tap()
        app.tabBars.buttons["البهو"].tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "maker-lobby-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription); reach(app, card)
        XCTAssertLessThan(card.frame.width, app.frame.width * 0.6)
        XCTAssertEqual(card.frame.width / card.frame.height, 1, accuracy: 0.1)
        capture(app, "OR-03-X3-lobby-small-L")
        app.terminate(); app.launch(); app.tabBars.buttons["البهو"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15)); reach(app, card)
        XCTAssertLessThan(card.frame.width, app.frame.width * 0.6)
        let link = card.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "عادات اليوم")).firstMatch
        XCTAssertTrue(link.exists); link.tap()
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 15), app.debugDescription)
    }

}
