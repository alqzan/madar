import XCTest

@MainActor final class MoneyEnvelopeDetailUITests: XCTestCase {
    func testDebtPreviewUsesExactAmountsAndDoesNotChangeBalance() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let rent = app.buttons["money-envelope-الإيجار"]
        for _ in 0..<5 { if rent.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(rent.isHittable); rent.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelope-detail"].waitForExistence(timeout: 10))
        let shortfall = app.descendants(matching: .any)["money-detail-shortfall"]
        XCTAssertTrue(shortfall.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(shortfall.label.contains("نوفمبر"), shortfall.label)
        shot(app, "M5-V04-detail-L")
        app.buttons["money-repay-open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-repayment-preview"].waitForExistence(timeout: 5))
        // The fixture is due before the second salary, so the sheet suggests one salary.
        XCTAssertEqual(clean(app.staticTexts["money-repay-per-salary"].label), "٩٠٠")
        app.buttons["money-repay-count-3"].tap(); XCTAssertEqual(clean(app.staticTexts["money-repay-per-salary"].label), "٣٠٠")
        XCTAssertTrue(app.staticTexts["money-repay-daily-after"].label.contains("٣٩٠"))
        shot(app, "M5-V04-repay-L")
        app.buttons["money-repay-count-2"].tap(); XCTAssertEqual(clean(app.staticTexts["money-repay-per-salary"].label), "٤٥٠")
        app.buttons["money-repay-count-6"].tap(); XCTAssertEqual(clean(app.staticTexts["money-repay-per-salary"].label), "١٥٠")
        app.buttons["إغلاق"].firstMatch.tap()
        XCTAssertTrue(app.buttons["money-repay-open"].waitForExistence(timeout: 5)); app.buttons["money-repay-open"].tap()
        XCTAssertEqual(clean(app.staticTexts["money-repay-per-salary"].label), "٩٠٠", "Preview choice does not persist or move money")
        app.buttons["money-repay-count-3"].tap()
        app.buttons["money-repay-adopt"].tap()
        let debt = app.descendants(matching: .any)["money-detail-debt"]
        XCTAssertTrue(debt.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "من الراتب القادم")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["money-detail-balance"].label.contains("٩٠٠"), "Adopting a plan moves no money now")
        shot(app, "M5-V04-adopted-L")
        let undoPlan = app.buttons["تراجع"]; XCTAssertTrue(undoPlan.waitForExistence(timeout: 5)); undoPlan.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "بلا خطة سداد")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["money-repay-open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-repayment-preview"].waitForExistence(timeout: 5))
        app.buttons["money-repay-from-surplus"].tap()
        XCTAssertTrue(app.staticTexts["money-detail-balance"].waitForExistence(timeout: 10))
        XCTAssertEqual(clean(app.staticTexts["money-detail-balance"].label), "٠")
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["money-repay-open"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["money-detail-balance"].label.contains("٩٠٠"))
    }
    private func clean(_ label: String) -> String { label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "") }
    private func shot(_ app: XCUIApplication, _ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
}
