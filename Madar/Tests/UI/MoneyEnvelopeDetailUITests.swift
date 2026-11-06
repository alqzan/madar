import XCTest

@MainActor final class MoneyEnvelopeDetailUITests: XCTestCase {
    func testRepaymentSheetStaysOpenWhileSaving() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00", "MADAR_UI_MONEY_WRITE_HOLD_MS": "3000"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let rent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-envelope-الإيجار-")).firstMatch
        for _ in 0..<5 { if rent.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(rent.isHittable); rent.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelope-detail"].waitForExistence(timeout: 10))
        app.buttons["money-repay-open"].tap()
        let preview = app.descendants(matching: .any)["money-repayment-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let close = app.buttons["money-repay-close"]
        XCTAssertTrue(close.exists); XCTAssertTrue(close.isEnabled)
        let adopt = app.buttons["money-repay-adopt"]
        XCTAssertTrue(adopt.isHittable); adopt.tap()
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(close.exists); XCTAssertFalse(close.isEnabled)
        XCTAssertTrue(adopt.exists); XCTAssertFalse(adopt.isEnabled)
        shot(app, "M5-V26-repayment-saving-L")
        XCTAssertTrue(preview.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "من الراتب القادم")).firstMatch.waitForExistence(timeout: 10))
    }

    /// FB-39 (owner, 6 Nov): «هدية» holds 460.00; moving 100.00 to «الطوارئ» leaves 360.00 and names the move in the history.
    func testEnvelopeMoveToAnotherEnvelope() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let gift = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-envelope-هدية-")).firstMatch
        for _ in 0..<6 { if gift.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(gift.isHittable, app.debugDescription); gift.tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-envelope-detail"].waitForExistence(timeout: 10))
        // The detail can still be settling when it first draws; wait for the button, then tap its centre.
        let move = app.buttons["money-envelope-move"]; XCTAssertTrue(move.waitForExistence(timeout: 10), app.debugDescription)
        move.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let side = app.buttons["money-move-side-الطوارئ"]; XCTAssertTrue(side.waitForExistence(timeout: 5), app.debugDescription); side.tap()
        let amount = app.textFields["money-move-amount"]; amount.tap(); amount.typeText("100")
        let preview = app.staticTexts["money-move-preview"]; XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(preview.label.contains("٣٦٠"), preview.label); XCTAssertTrue(preview.label.contains("١٬٣٠٠") || preview.label.contains("١٣٠٠"), preview.label)
        shot(app, "FB39-money-envelope-move-L")
        app.buttons["money-move-save"].tap(); XCTAssertTrue(amount.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "نُقل إلى الطوارئ")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }
    /// FB-45: an envelope's name and a bill's name and amount can be corrected after saving.
    func testRenameEnvelopeAndEditBill() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let gift = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-envelope-هدية-")).firstMatch
        for _ in 0..<6 { if gift.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(gift.isHittable, app.debugDescription); gift.tap()
        let rename = app.buttons["money-envelope-rename"]; XCTAssertTrue(rename.waitForExistence(timeout: 10), app.debugDescription)
        rename.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let name = app.textFields["money-edit-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" العيد")
        shot(app, "FB45-money-envelope-rename-L")
        // Return on the keyboard saves (the save button can sit under the keyboard in a medium sheet).
        name.typeText("\n"); _ = name.waitForNonExistence(timeout: 10)
        let error = app.staticTexts["money-edit-error"]
        XCTAssertFalse(error.exists, error.exists ? error.label : "")
        XCTAssertFalse(name.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["هدية العيد"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate(); app.launch()
        let tab2 = app.buttons["tab-customize"]; XCTAssertTrue(tab2.waitForExistence(timeout: 20)); tab2.tap()
        let search2 = app.textFields["settings-search"]; XCTAssertTrue(search2.waitForExistence(timeout: 10)); search2.tap(); search2.typeText("المال"); app.buttons["money-open"].tap()
        let obligations = app.buttons["money-obligations-open"]; for _ in 0..<6 { if obligations.exists && obligations.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(obligations.waitForExistence(timeout: 10), app.debugDescription); obligations.tap()
        let bill = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "الكهرباء")).firstMatch
        XCTAssertTrue(bill.waitForExistence(timeout: 10), app.debugDescription); bill.tap()
        let edit = app.buttons["money-obligation-edit"]; XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription); edit.tap()
        let billName = app.textFields["money-edit-name"]; XCTAssertTrue(billName.waitForExistence(timeout: 5)); billName.tap(); billName.typeText(" والماء")
        XCTAssertTrue(app.textFields["money-edit-amount"].exists, "A bill's amount can change")
        shot(app, "FB45-money-bill-edit-L")
        billName.tap(); billName.typeText("\n"); XCTAssertTrue(billName.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "الكهرباء والماء")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }
    func testDebtPreviewUsesExactAmountsAndDoesNotChangeBalance() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let rent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-envelope-الإيجار-")).firstMatch
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
