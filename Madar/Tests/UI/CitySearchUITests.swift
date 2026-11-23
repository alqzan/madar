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
        // Choosing the city saves it and finishes the first run: the lobby opens at once.
        XCTAssertTrue(app.descendants(matching: .any)["bahw-greeting"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["first-run-city"].exists, app.debugDescription)
    }
}
