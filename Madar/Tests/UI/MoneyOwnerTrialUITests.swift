import XCTest

/// Owner money trial, item 17 (23 Oct 2026). Runs only when TEST_RUNNER_MADAR_TRIAL_MONEY names the old backup on this
/// Mac: imports it into a fresh UI-test store twice (the second run must add nothing) and captures the money room.
@MainActor final class MoneyOwnerTrialUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.8); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func report(_ backup: String, _ run: String) throws -> [String: Int] {
        let url = URL(fileURLWithPath: backup).deletingLastPathComponent().appendingPathComponent("money-import-\(run).json")
        let deadline = Date().addingTimeInterval(600)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 2) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Int], "No trial report")
    }
    func testOwnerLegacyMoneyTrial() throws {
        continueAfterFailure = false
        guard let backup = ProcessInfo.processInfo.environment["MADAR_TRIAL_MONEY"] else { throw XCTSkip("Owner data trial only") }
        let store = UUID().uuidString, stamp = String(Int(Date().timeIntervalSince1970))
        for run in ["first", "second"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: backup).deletingLastPathComponent().appendingPathComponent("money-import-\(stamp)-\(run).json")) }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_RUN": stamp + "-first",
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let first = try report(backup, stamp + "-first")
        XCTAssertNil(first["failed"]); XCTAssertGreaterThan(first["store.transactions"] ?? 0, 0)
        XCTAssertEqual(first["store.unconfirmed", default: 0], first["store.possibleDuplicates", default: 0], "Only real possible duplicates may wait")
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 60) {
            let skip = app.buttons["first-run-skip"]
            if skip.exists { skip.tap() }
            let cityStart = app.buttons.matching(identifier: "first-run-continue").matching(NSPredicate(format: "label == %@", "ابدأ يومك")).firstMatch
            XCTAssertTrue(cityStart.waitForExistence(timeout: 10)); cityStart.tap()
            // The tab bar exists behind the cover. Wait for the onboarding write and actual dismissal,
            // rather than tapping an underlying tab while a large imported store is still saving.
            XCTAssertTrue(start.waitForNonExistence(timeout: 120), "Onboarding must close before room navigation")
        }
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 60), app.debugDescription); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription); search.tap(); search.typeText("المال"); app.buttons["money-open"].tap()
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 20), app.debugDescription)
        shot(app, "TRIAL-money-home-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s1-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s2-L")
        app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s3-L")
        app.terminate()
        app.launchEnvironment["MADAR_TRIAL_RUN"] = stamp + "-second"; app.launch()
        let second = try report(backup, stamp + "-second")
        XCTAssertEqual(second["store.transactions"], first["store.transactions"], "A second import must add nothing")
        XCTAssertEqual(second["store.categories"], first["store.categories"])
        XCTAssertEqual(second["store.unconfirmed"], first["store.unconfirmed"])
        XCTAssertEqual(second["balance.known"], first["balance.known"])
        XCTAssertEqual(second["balance.unknown"], first["balance.unknown"])
        XCTAssertEqual(second["earlier.cardLinked", default: 0], 0, "Replay must not rewrite the old rows' card links or edit dates")
    }
}
