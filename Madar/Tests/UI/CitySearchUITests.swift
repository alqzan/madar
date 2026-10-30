import XCTest

/// Owner, 30 Oct: a new reader finds a city by typing its name instead of entering coordinates.
@MainActor final class CitySearchUITests: XCTestCase {
    func testFirstRunFindsACityByName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let start = app.buttons["first-run-continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
        start.tap()
        let choose = app.buttons["first-run-city"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        choose.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["city-locate"].exists)
        field.tap(); field.typeText("ابها")
        let hit = app.buttons["city-hit-أبها"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription)
        hit.tap()
        // The city is saved at once and the first-run card names it.
        XCTAssertTrue(app.staticTexts["أبها"].waitForExistence(timeout: 8), app.debugDescription)
    }
}
