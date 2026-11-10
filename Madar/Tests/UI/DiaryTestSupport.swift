import XCTest

extension XCUIApplication {
    /// The day page closes with its own button when it is presented alone, and with the navigation back button when the diary home embeds it.
    func closeDiaryDay() {
        let close = buttons["diary-day-close"]
        if close.waitForExistence(timeout: 2) { close.tap() } else { navigationBars.buttons.firstMatch.tap() }
    }
}
