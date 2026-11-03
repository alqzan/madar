import XCTest

/// Owner Quran trial, item 19 (24 Oct 2026). Runs only when TEST_RUNNER_MADAR_TRIAL_QURAN names the old backup on this
/// Mac: imports it into a fresh UI-test store twice (the second run must add nothing) and walks the Quran room.
@MainActor final class QuranOwnerTrialUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.8); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func report(_ backup: String, _ run: String) throws -> [String: Int] {
        let url = URL(fileURLWithPath: backup).deletingLastPathComponent().appendingPathComponent("quran-import-\(run).json")
        let deadline = Date().addingTimeInterval(300)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Int], "No trial report")
    }
    private func openQuran(_ app: XCUIApplication) {
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 12) {
            let skip = app.buttons["first-run-skip"]
            if skip.exists { skip.tap() }
            let cityStart = app.buttons.matching(identifier: "first-run-continue").matching(NSPredicate(format: "label == %@", "ابدأ يومك")).firstMatch
            XCTAssertTrue(cityStart.waitForExistence(timeout: 10)); cityStart.tap()
            XCTAssertTrue(start.waitForNonExistence(timeout: 60), "Onboarding must close before room navigation")
        }
        let tab = app.buttons["tab-quran"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30), app.debugDescription); tab.tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 30), app.debugDescription)
    }
    private func close(_ app: XCUIApplication) {
        for id in ["quran-screen-close", "quran-week-close", "quran-drill-close"] where app.buttons[id].exists { app.buttons[id].tap(); return }
        app.swipeDown(velocity: .fast)
    }
    func testOwnerLegacyQuranTrial() throws {
        continueAfterFailure = true
        guard let backup = ProcessInfo.processInfo.environment["MADAR_TRIAL_QURAN"] else { throw XCTSkip("Owner data trial only") }
        let store = UUID().uuidString, stamp = String(Int(Date().timeIntervalSince1970))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_TRIAL_QURAN": backup, "MADAR_TRIAL_RUN": stamp + "-first",
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        if let money = ProcessInfo.processInfo.environment["MADAR_TRIAL_MONEY"] { app.launchEnvironment["MADAR_TRIAL_MONEY"] = money }
        let prayer = ProcessInfo.processInfo.environment["MADAR_TRIAL_PRAYER"]
        if let prayer { app.launchEnvironment["MADAR_TRIAL_PRAYER"] = prayer }
        app.launch()
        let first = try report(backup, stamp + "-first")
        XCTAssertNil(first["failed"], first.description)
        XCTAssertEqual(first["store.plans"], 1)
        XCTAssertEqual(first["derived.maxCoveredAyah"], 128, "Legacy frontierId 128 is the last memorised ayah")
        XCTAssertEqual(first["derived.coveredAyahs"], 128)
        XCTAssertEqual(first["store.sessions"], (first["hifz.imported"] ?? 0) + (first["review.imported"] ?? 0) + (first["hifz.frontierGap"] ?? 0))
        XCTAssertEqual(first["store.spots"], (first["mistake.open"] ?? 0) + (first["mistake.closed"] ?? 0))
        openQuran(app)
        shot(app, "TRIAL-quran-home-L")
        for i in 1...4 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-quran-home-s\(i)-L") }
        for tool in ["strength", "index", "free", "mushaf", "qiyam"] {
            let button = app.buttons["quran-tool-" + tool]
            for _ in 0..<3 where !button.isHittable { app.swipeUp(velocity: .slow) }
            guard button.exists else { continue }
            button.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-quran-\(tool)-L")
            app.swipeUp(velocity: .slow); shot(app, "TRIAL-quran-\(tool)-s1-L")
            // A fresh launch returns to the room home; replaying the import adds nothing.
            app.terminate(); app.launch(); openQuran(app)
        }
        let week = app.buttons["quran-week-open"]
        for _ in 0..<5 where !week.isHittable { app.swipeUp(velocity: .slow) }
        if week.exists {
            week.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-quran-week-L")
            for tab in ["year", "all", "sessions"] {
                let b = app.buttons["quran-log-" + tab]
                if b.exists { b.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-quran-log-\(tab)-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-quran-log-\(tab)-s1-L"); app.swipeDown(velocity: .slow) }
            }
            close(app)
        }
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        let streak = app.buttons["quran-streak"]
        if streak.waitForExistence(timeout: 3) { streak.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-quran-plan-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-quran-plan-s1-L"); close(app) }
        let begin = app.buttons["quran-begin"]
        if begin.waitForExistence(timeout: 3) { begin.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-quran-session-L") }
        if let prayer {
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: prayer).deletingLastPathComponent().appendingPathComponent("prayer-import-\(stamp)-first.json"))) as? [String: Int])
            XCTAssertNil(report["failed"], report.description)
            app.terminate(); app.launch()
            let tab = app.buttons["tab-prayer"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 30)); tab.tap(); Thread.sleep(forTimeInterval: 2)
            shot(app, "TRIAL-prayer-home-L")
            for i in 1...5 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-prayer-home-s\(i)-L") }
        }
        app.terminate()
        app.launchEnvironment["MADAR_TRIAL_RUN"] = stamp + "-second"; app.launchEnvironment["MADAR_TRIAL_MONEY"] = nil; app.launch()
        if let prayer {
            let url = URL(fileURLWithPath: prayer).deletingLastPathComponent().appendingPathComponent("prayer-import-\(stamp)-second.json")
            let deadline = Date().addingTimeInterval(120); while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
            let again = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Int])
            XCTAssertNil(again["logs.created"]); XCTAssertNil(again["qada.created"])
        }
        let second = try report(backup, stamp + "-second")
        XCTAssertNil(second["failed"], second.description)
        for key in ["store.sessions", "store.grades", "store.spots", "store.importLinks", "store.plans", "derived.coveredAyahs", "derived.completedPages"] {
            XCTAssertEqual(second[key], first[key], "A second import must add nothing: \(key)")
        }
        XCTAssertEqual(second["links.created", default: 0], 0)
    }
}
