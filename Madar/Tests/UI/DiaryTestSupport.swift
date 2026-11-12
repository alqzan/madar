import XCTest

extension XCUIApplication {
    /// The home's write control: the capsule in today's card (`diary-write`) or the card itself / the bottom bar (`diary-today`); both open today's page.
    var diaryOpener: XCUIElement { buttons.matching(NSPredicate(format: "identifier IN %@", ["diary-write", "diary-today"])).firstMatch }
    /// The day page closes with its own button when it is presented alone, and with the navigation back button when the diary home embeds it.
    func closeDiaryDay() {
        let close = buttons["diary-day-close"]
        if close.waitForExistence(timeout: 2) { close.tap() } else { navigationBars.buttons.firstMatch.tap() }
    }
    /// The home's write button opens today's page with its one field focused; the full page (formatting, camera, files, voice bar) is its expand button.
    func openDiaryEditorFromHome() {
        diaryOpener.tap()
        // With words already in the field (a restored draft) the same button is named for what it does with them.
        let expand = buttons.matching(NSPredicate(format: "identifier IN %@", ["diary-day-write", "diary-inline-expand"])).firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 20), "Today's page must offer the full writing page")
        expand.tap()
    }
}
