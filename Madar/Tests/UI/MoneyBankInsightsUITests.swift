import XCTest

/// Owner, 11 Nov 2026: «مستحقات قادمة» and the quiet balance-difference row sit on the money room's home, with no notification.
@MainActor final class MoneyBankInsightsUITests: XCTestCase {
    func testDueLineAndMismatchRowAppearAndSettleRemovesTheRow() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "bankInsights",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-money"].firstMatch
        if tab.waitForExistence(timeout: 15) { tab.tap() }
        let insights = app.descendants(matching: .any)["money-bank-insights"].firstMatch
        for _ in 0..<10 where !insights.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(insights.waitForExistence(timeout: 10), app.debugDescription)
        let dues = app.descendants(matching: .any)["money-dues"].firstMatch
        XCTAssertTrue(dues.exists, "the due announced by a message is listed")
        let settle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'money-bank-settle-'")).firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 5), "an open difference offers «سوِّ الفرق»")
        settle.tap()
        let unexplained = app.buttons["تسوية بلا تفسير"]; XCTAssertTrue(unexplained.waitForExistence(timeout: 5))
        unexplained.tap()
        XCTAssertTrue(settle.waitForNonExistence(timeout: 10), "settled: the row is gone")
    }
}
