import XCTest

@MainActor final class MoneyAccountsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func open(_ fixture: String, unknownBalance: Bool = false, wrappedNames: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": fixture, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        if unknownBalance { app.launchEnvironment["MADAR_UI_UNKNOWN_BALANCE"] = "1" }
        if wrappedNames { app.launchEnvironment["MADAR_UI_WRAPPED_ACCOUNTS"] = "1" }
        app.launch(); let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        let door = app.buttons["money-accounts-open"]; XCTAssertTrue(door.waitForExistence(timeout: 10)); for _ in 0..<8 where !door.isHittable { app.swipeUp(velocity: .slow) }; door.tap()
        XCTAssertTrue(app.staticTexts["money-accounts-net"].waitForExistence(timeout: 10)); return app
    }
    func testTreeSourcesProtectedCheckpointAndAddNotMineWithUndo() {
        continueAfterFailure = false
        let app = open("accounts"), net = app.staticTexts["money-accounts-net"]
        let before = net.label; XCTAssertFalse(before.contains("•••")); shot(app, "M5-V19-accounts-L")
        app.buttons["money-account-الحساب الجاري"].tap()
        let name = app.textFields["money-account-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["money-account-owned"].isEnabled)
        XCTAssertFalse(app.textFields["money-account-opening"].isEnabled)
        XCTAssertFalse(app.buttons["money-account-remove"].exists, "Movements refer to it: it cannot be removed")
        shot(app, "M5-V19-checkpoint-L")
        app.buttons["money-account-editor-close"].tap()
        app.buttons["money-account-source-الحساب الجاري"].tap()
        XCTAssertTrue(app.staticTexts["رصيد بداية أدخلته"].waitForExistence(timeout: 5)); shot(app, "M5-V19-source-L")
        app.swipeDown(velocity: .fast)
        app.buttons["money-accounts-add"].tap()
        let field = app.textFields["money-account-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("حساب الأسرة")
        let bank = app.textFields["money-account-bank"]; bank.tap(); bank.typeText("مصرف الاختبار")
        app.buttons["money-account-keyboard-done"].tap()
        app.switches["money-account-owned"].tap()
        let opening = app.textFields["money-account-opening"]; opening.tap(); opening.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "1000")
        app.buttons["money-account-keyboard-done"].tap()
        let save = app.buttons["money-account-save"]; for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }; shot(app, "M5-V19-add-L"); save.tap()
        XCTAssertTrue(app.buttons["money-account-حساب الأسرة"].waitForExistence(timeout: 10)); XCTAssertEqual(net.label, before)
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertFalse(app.buttons["money-account-حساب الأسرة"].exists); XCTAssertEqual(net.label, before)
    }
    /// Item 34: an account added by mistake is removed from its sheet after a confirmation, and the toast brings it back.
    func testUnusedAccountRemovesWithConfirmationAndUndo() {
        continueAfterFailure = false
        let app = open("accounts")
        app.buttons["money-accounts-add"].tap()
        let field = app.textFields["money-account-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("حساب زائد")
        let bank = app.textFields["money-account-bank"]; bank.tap(); bank.typeText("مصرف الاختبار")
        app.buttons["money-account-keyboard-done"].tap()
        let save = app.buttons["money-account-save"]; for _ in 0..<5 where !save.isHittable { app.swipeUp(velocity: .slow) }; save.tap()
        let row = app.buttons["money-account-حساب زائد"]; XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<6 where !row.isHittable { app.swipeUp(velocity: .slow) }
        row.tap()
        let remove = app.buttons["money-account-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<5 where !remove.isHittable { app.swipeUp(velocity: .slow) }
        shot(app, "M5-V19-remove-L"); remove.tap()
        let confirm = app.buttons.matching(identifier: "money-account-remove-confirm"); XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "M5-V19-remove-confirm-L"); confirm.firstMatch.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["حُذف الحساب"].waitForExistence(timeout: 5), app.debugDescription)
        let undo = app.buttons["تراجع"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
    }
    func testWrappedAccountNamesAndScrolledRoots() {
        continueAfterFailure = false
        let app = open("accounts", wrappedNames: true)
        shot(app, "M5-V19-wrapped-accounts-L")
        let last = app.buttons["money-account-حساب آخر"]
        for _ in 0..<8 where !last.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(last.isHittable)
        shot(app, "M5-V19-wrapped-accounts-s1-L")
        last.tap()
        XCTAssertTrue(app.textFields["money-account-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["money-account-name"].value as? String, "حساب آخر")
    }
    func testHiddenAndEmpty() {
        continueAfterFailure = false
        let hidden = open("hidden"); XCTAssertTrue(hidden.staticTexts["money-accounts-net"].label.contains("•••")); shot(hidden, "M5-V19-hidden-L")
        hidden.buttons["money-accounts-reveal"].tap(); XCTAssertFalse(hidden.staticTexts["money-accounts-net"].label.contains("•••")); hidden.terminate()
        let empty = open("empty"); XCTAssertTrue(empty.staticTexts["money-accounts-empty"].exists); XCTAssertTrue(empty.buttons["money-accounts-empty-add"].exists); shot(empty, "M5-V19-empty-L")
    }
    func testHiddenOpeningBalanceRequiresExplicitRevealInAccountSheet() {
        continueAfterFailure = false
        let app = open("hidden")
        let account = app.buttons["money-account-الحساب الجاري"]
        for _ in 0..<8 where !account.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(account.isHittable, app.debugDescription)
        account.tap()
        XCTAssertTrue(app.staticTexts["رصيد البداية محفوظ ومخفي حتى تُظهر الأرقام."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.textFields["money-account-opening"].exists, app.debugDescription)
        shot(app, "M5-V19-account-editor-redacted-L")
        app.buttons["money-account-reveal-opening"].tap()
        let balance = app.textFields["money-account-opening"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(balance.value as? String, "128500.00")
        XCTAssertFalse(balance.isEnabled, "A revealed fixed checkpoint stays protected from editing.")
        shot(app, "M5-V19-account-editor-revealed-L")
    }
    func testUnknownBalanceOffersExplicitBankCheckpoint() {
        continueAfterFailure = false
        let app = open("accounts", unknownBalance: true)
        XCTAssertTrue(app.staticTexts["لم يُعرف رصيدها بعد"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "M5-18-unknown-account-L")
        let reconcile = app.buttons["money-accounts-unknown-reconcile"]
        for _ in 0..<8 where !reconcile.isHittable { app.swipeUp(velocity: .slow) }
        reconcile.tap()
        let unknown = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "money-reconcile-unknown-")).firstMatch
        XCTAssertTrue(unknown.waitForExistence(timeout: 10)); unknown.tap()
        let field = app.textFields["money-account-opening"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); XCTAssertTrue(field.isEnabled)
        XCTAssertFalse(app.buttons["money-account-save"].isEnabled, "An unknown balance must not silently become zero")
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "900")
        app.buttons["money-account-keyboard-done"].tap()
        let save = app.buttons["money-account-save"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp(velocity: .slow) }
        save.tap()
        XCTAssertTrue(app.staticTexts["money-reconcile-expected"].waitForExistence(timeout: 10))
        XCTAssertFalse(unknown.exists)
        shot(app, "M5-18-established-balance-L")
    }
}
