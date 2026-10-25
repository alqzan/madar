import XCTest

/// Owner real-data trial, item 19 (24 Oct 2026). Runs only when TEST_RUNNER_MADAR_TRIAL_BACKUP names the old backup and
/// TEST_RUNNER_MADAR_TRIAL_ZIP its diary as a Day One ZIP on this Mac: money, Quran, prayer and diary go into ONE fresh
/// UI-test store, then the money room, the diary and the Mihbara are walked with all of it present.
@MainActor final class OwnerAllDataTrialUITests: XCTestCase {
    /// Records and dismisses any app alert so the walk continues; the alert text is a finding.
    private func clearAlert(_ app: XCUIApplication, _ where_: String) {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        shot(app, "TRIAL-alert-\(where_)-L"); add(XCTAttachment(string: "ALERT at \(where_): " + text)); XCTFail("App alert at \(where_): " + text)
        alert.buttons.firstMatch.tap()
    }
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.8); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func report(_ url: URL, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 2) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], "No trial report \(url.lastPathComponent)")
    }
    /// Opens a money sheet by its `-open` id, captures it and its scrolled state, then closes it by its `-close` id.
    private func visit(_ app: XCUIApplication, _ base: String) {
        let open = app.buttons["money-\(base)-open"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        guard open.exists, open.isHittable else { XCTFail("Required money page is unreachable: \(base)"); return }
        open.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-money-\(base)-L")
        app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-\(base)-s1-L")
        let close = app.buttons["money-\(base)-close"]
        for _ in 0..<5 where !(close.exists && close.isHittable) { app.swipeDown(velocity: .slow) }
        let back = app.buttons["money-\(base)-back"]
        if close.exists && close.isHittable { close.tap() }
        else if back.exists && back.isHittable { back.tap() }
        else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        else { app.swipeDown(velocity: .fast) }
        _ = app.buttons["money-expense-open"].waitForExistence(timeout: 5)
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
    }
    private func reach(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let element = app.buttons.matching(identifier: id).firstMatch
        for _ in 0..<10 where !element.isHittable { app.swipeUp(velocity: .slow) }
        // isHittable is true under the floating tab bar too, so keep the target in the upper part of the screen.
        let bottom = app.windows.firstMatch.frame.maxY * 0.7
        for _ in 0..<4 where element.exists && element.frame.maxY > bottom { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing required route: " + id)
        XCTAssertTrue(element.isHittable, "Offscreen required route: " + id)
        return element
    }
    private func close(_ app: XCUIApplication, _ id: String) {
        let element = app.buttons.matching(identifier: id).firstMatch
        for _ in 0..<12 where !element.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(element.waitForExistence(timeout: 10)); XCTAssertTrue(element.isHittable)
        if element.exists && element.isHittable { element.tap() }
    }
    private func homeTop(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 15))
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
    }
    private func visitNestedMoneyPages(_ app: XCUIApplication) {
        homeTop(app)
        reach(app, "money-basis-open").tap()
        let cash = app.buttons["money-cash-open"]
        guard cash.waitForExistence(timeout: 15) else { XCTFail("Basis sheet did not open"); shot(app, "TRIAL-money-basis-missing-L"); return }
        XCTAssertTrue(cash.label.contains("—"), "Actual source has no confirmed bank checkpoint")
        shot(app, "TRIAL-money-basis-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-basis-s1-L")
        for _ in 0..<6 where !cash.isHittable { app.swipeDown(velocity: .fast) }
        cash.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "money-cash").firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["money-cash-total"].label, "—"); XCTAssertEqual(app.staticTexts["money-cash-net"].label, "—")
        shot(app, "TRIAL-money-cash-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-cash-s1-L")
        close(app, "money-page-close") // Cash -> basis, then dismiss the basis sheet.
        XCTAssertTrue(cash.waitForExistence(timeout: 10)); close(app, "money-page-close")
        homeTop(app)
        reach(app, "money-pending").tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 15))
        reach(app, "money-budget-open").tap()
        XCTAssertTrue(app.staticTexts["money-budget-excluded-total"].waitForExistence(timeout: 15))
        shot(app, "TRIAL-money-budget-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-budget-s1-L")
        close(app, "money-budget-close"); XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        close(app, "money-messages-close")
        homeTop(app)
        reach(app, "money-log-open").tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "money-log-arcade").firstMatch.waitForExistence(timeout: 15))
        shot(app, "TRIAL-money-log-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-log-s1-L")
        for _ in 0..<8 where !app.buttons["money-log-search-open"].isHittable { app.swipeDown(velocity: .fast) }
        app.buttons["money-log-search-open"].tap()
        let field = app.textFields["money-log-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("غيرموجود\n")
        XCTAssertTrue(app.staticTexts["money-log-empty"].waitForExistence(timeout: 10)); shot(app, "TRIAL-money-log-search-L")
        app.buttons["مسح البحث"].tap(); close(app, "money-log-close"); homeTop(app)
    }
    /// A tab tap can leave the lobby in front, so trust only the money-home marker and fall back to the
    /// customise search route that MoneyHomeUITests uses.
    private func openMoney(_ app: XCUIApplication) {
        let mal = app.tabBars.buttons["المال"].firstMatch
        if mal.waitForExistence(timeout: 20) { mal.tap() }
        if !app.buttons["money-expense-open"].waitForExistence(timeout: 10) {
            let more = app.buttons["tab-customize"]; XCTAssertTrue(more.waitForExistence(timeout: 60), app.debugDescription); more.tap()
            let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("المال")
            let open = app.buttons["money-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        }
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 30), app.debugDescription)
    }
    /// Strict walk r3/r4: with the owner's money (accounts, no cycle) «على أي أساس» did not open. Money only, straight to it.
    func testOwnerMoneyBasisOpens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let backup = env["MADAR_TRIAL_BACKUP"] else { throw XCTSkip("Owner data trial only") }
        let stamp = "basis-" + String(Int(Date().timeIntervalSince1970))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_RUN": stamp,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        _ = try report(URL(fileURLWithPath: backup).deletingLastPathComponent().appendingPathComponent("money-import-\(stamp).json"), timeout: 600)
        clearAlert(app, "basis-import")
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 5) { for _ in 0..<4 where start.exists && start.isHittable { start.tap(); Thread.sleep(forTimeInterval: 1) } }
        openMoney(app)
        let basis = reach(app, "money-basis-open"); shot(app, "BASIS-before-L"); basis.tap()
        let opened = app.buttons["money-page-close"].waitForExistence(timeout: 10)
        shot(app, "BASIS-after-L")
        XCTAssertTrue(opened, app.debugDescription)
    }
    func testOwnerAllDataTrial() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let backup = env["MADAR_TRIAL_BACKUP"], let zip = env["MADAR_TRIAL_ZIP"] else { throw XCTSkip("Owner data trial only") }
        let folder = URL(fileURLWithPath: backup).deletingLastPathComponent()
        let stamp = "all-" + String(Int(Date().timeIntervalSince1970))
        let diaryReport = folder.appendingPathComponent("diary-import-\(stamp).json")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_QURAN": backup, "MADAR_TRIAL_PRAYER": backup, "MADAR_TRIAL_HABITS": backup, "MADAR_TRIAL_PERSONAL": backup,
                                 "MADAR_UI_LEGACY_DIARY_ZIP": zip, "MADAR_UI_LEGACY_REPORT": diaryReport.path, "MADAR_TRIAL_RUN": stamp,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        for room in ["money", "quran", "prayer", "habits", "personal"] {
            let r = try report(folder.appendingPathComponent("\(room)-import-\(stamp).json"), timeout: 1200)
            XCTAssertNil(r["failed"], "\(room): \(r)")
            if room == "habits" || room == "personal" {
                XCTAssertEqual(r["replay.created"] as? Int, 0)
                XCTAssertEqual(r["replay.unchanged"] as? Int, 1)
            }
            add(XCTAttachment(string: "\(room): \(r.filter { $0.key.hasPrefix("store.") })"))
        }
        let diary = try report(diaryReport, timeout: 900)
        XCTAssertNil(diary["error"], "diary: \(diary)")
        add(XCTAttachment(string: "diary: \(diary["store"] ?? "-")"))

        clearAlert(app, "after-import")
        // Money room.
        openMoney(app)
        clearAlert(app, "money"); shot(app, "TRIAL-money-home-L")
        for i in 1...5 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s\(i)-L") }
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        for base in ["accounts", "categories", "envelopes", "obligations", "cards", "analysis", "reconcile", "cashback", "goal", "zakat", "settings"] { visit(app, base) }
        visitNestedMoneyPages(app)

        // Diary.
        clearAlert(app, "diary")
        // The diary opens from the notebook in the floating bar of a room home, so return to the money home first.
        for _ in 0..<3 where !app.buttons["money-expense-open"].exists { if let back = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '-back'")).allElementsBoundByIndex.first(where: \.isHittable) { back.tap() } else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() } else { app.swipeRight() } ; Thread.sleep(forTimeInterval: 1) }
        let notes = app.buttons["tab-notes"]; XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        let next = app.buttons["diary-welcome-next"]
        if next.waitForExistence(timeout: 5) { for _ in 0..<6 where next.exists { next.tap(); _ = app.buttons["diary-days"].waitForExistence(timeout: 2) } }
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 30), app.debugDescription); shot(app, "TRIAL-diary-home-L")
        for i in 1...3 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-diary-home-s\(i)-L") }
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        app.buttons["diary-days"].tap()
        if app.buttons["diary-calendar-scale-year"].waitForExistence(timeout: 30) {
            shot(app, "TRIAL-diary-hub-L")
            for tab in ["diary-hub-timeline", "diary-hub-photos", "diary-hub-letters"] where app.buttons[tab].exists { app.buttons[tab].tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-" + tab + "-L") }
            if app.buttons["diary-hub-close"].exists { app.buttons["diary-hub-close"].tap() } else { app.swipeDown(velocity: .fast) }
        }
        let search = app.buttons["diary-search"]
        if search.waitForExistence(timeout: 5) {
            search.tap(); let field = app.textFields["diary-search-query"]
            if field.waitForExistence(timeout: 5) { field.tap(); field.typeText("الصلاة"); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-diary-search-L") }
            if app.buttons["diary-search-close"].exists { app.buttons["diary-search-close"].tap() }
        }

        // Mihbara (the old backup holds no books, reading logs or benefits).
        let mihbara = app.tabBars.buttons["المحبرة"].firstMatch
        XCTAssertTrue(mihbara.waitForExistence(timeout: 20)); mihbara.tap(); Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 20), "The Mihbara home must actually open")
        shot(app, "TRIAL-mihbara-home-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-mihbara-home-s1-L")

        // The lobby with every room's data.
        let bahwTab = app.tabBars.buttons["البهو"].firstMatch, bahw = bahwTab.waitForExistence(timeout: 5) ? bahwTab : app.buttons["البهو"].firstMatch
        XCTAssertTrue(bahw.waitForExistence(timeout: 10), "The lobby is a required room")
        if bahw.exists { bahw.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-bahw-L"); for i in 1...3 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-bahw-s\(i)-L") } }
        // Prayer and Quran homes, then the habits room from the lobby (Claude, 24 Oct tour).
        for (tab, name) in [("الصلاة", "prayer"), ("القرآن", "quran")] {
            let button = app.tabBars.buttons[tab].firstMatch
            guard button.waitForExistence(timeout: 10) else { XCTFail("Required room tab missing: " + tab); continue }
            button.tap(); Thread.sleep(forTimeInterval: 2); clearAlert(app, name)
            let marker = app.descendants(matching: .any).matching(identifier: name == "prayer" ? "prayer-today-header" : "quran-coverage-title").firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 20), "The " + name + " home must actually open; a tab tap alone is not proof")
            shot(app, "TRIAL-\(name)-home-L")
            for i in 1...4 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-\(name)-home-s\(i)-L") }
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }
        if bahwTab.exists { bahwTab.tap(); Thread.sleep(forTimeInterval: 1) }
        let habits = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        for _ in 0..<6 where !(habits.exists && habits.isHittable) { app.swipeDown(velocity: .fast) }
        if habits.waitForExistence(timeout: 10) {
            let header = app.buttons["bahw-habits-open"]; if header.exists { header.tap() } else { habits.tap() }
            XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10), "The habits room must actually open")
            if app.staticTexts["habits-title"].exists { shot(app, "TRIAL-habits-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-habits-s1-L") }
        } else { XCTFail("Required habits block is missing") }
    }
}
