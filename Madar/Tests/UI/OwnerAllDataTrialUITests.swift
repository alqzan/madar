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
        guard open.exists, open.isHittable else { add(XCTAttachment(string: "not reachable: \(base)")); return }
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
    func testOwnerAllDataTrial() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let backup = env["MADAR_TRIAL_BACKUP"], let zip = env["MADAR_TRIAL_ZIP"] else { throw XCTSkip("Owner data trial only") }
        let folder = URL(fileURLWithPath: backup).deletingLastPathComponent()
        let stamp = "all-" + String(Int(Date().timeIntervalSince1970))
        let diaryReport = folder.appendingPathComponent("diary-import-\(stamp).json")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_QURAN": backup, "MADAR_TRIAL_PRAYER": backup,
                                 "MADAR_UI_LEGACY_DIARY_ZIP": zip, "MADAR_UI_LEGACY_REPORT": diaryReport.path, "MADAR_TRIAL_RUN": stamp,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        for room in ["money", "quran", "prayer"] {
            let r = try report(folder.appendingPathComponent("\(room)-import-\(stamp).json"), timeout: 1200)
            XCTAssertNil(r["failed"], "\(room): \(r)")
            add(XCTAttachment(string: "\(room): \(r.filter { $0.key.hasPrefix("store.") })"))
        }
        let diary = try report(diaryReport, timeout: 900)
        XCTAssertNil(diary["error"], "diary: \(diary)")
        add(XCTAttachment(string: "diary: \(diary["store"] ?? "-")"))

        clearAlert(app, "after-import")
        // Money room.
        let mal = app.tabBars.buttons["المال"].firstMatch
        if mal.waitForExistence(timeout: 20) { mal.tap() } else {
            let more = app.buttons["tab-customize"]; XCTAssertTrue(more.waitForExistence(timeout: 60), app.debugDescription); more.tap()
            let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        }
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 30), app.debugDescription)
        clearAlert(app, "money"); shot(app, "TRIAL-money-home-L")
        for i in 1...5 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s\(i)-L") }
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        for base in ["accounts", "cash", "budget", "categories", "envelopes", "obligations", "log-search", "basis"] { visit(app, base) }

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
            for tab in ["diary-hub-timeline", "diary-hub-photos"] where app.buttons[tab].exists { app.buttons[tab].tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-" + tab + "-L") }
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
        shot(app, "TRIAL-mihbara-home-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-mihbara-home-s1-L")

        // The lobby with every room's data.
        let bahwTab = app.tabBars.buttons["البهو"].firstMatch, bahw = bahwTab.waitForExistence(timeout: 5) ? bahwTab : app.buttons["البهو"].firstMatch
        if bahw.waitForExistence(timeout: 10) { bahw.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-bahw-L"); for i in 1...3 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-bahw-s\(i)-L") } } else { add(XCTAttachment(string: "lobby tab not found: " + app.tabBars.buttons.allElementsBoundByIndex.map(\.label).joined(separator: "|"))) }
    }
}
