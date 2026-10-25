import XCTest

/// Explicit opt-in, isolated DEBUG store. The real backup and captures stay local.
@MainActor final class HabitsOwnerTrialUITests: XCTestCase {
    private func report(_ url: URL) throws -> [String: Int] {
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func open(_ app: XCUIApplication) {
        let door = app.buttons["bahw-habits-open"]
        XCTAssertTrue(door.waitForExistence(timeout: 30)); door.tap()
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10))
    }
    func testOwnerHabitsImportHistoryAndRelaunchWithoutGrowth() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP"] else { throw XCTSkip("Owner backup opt-in only") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let rows = try XCTUnwrap(root["habits"] as? [[String: Any]])
        let sourceIDs = Set(rows.compactMap { $0["id"] as? String })
        let deleted = root["deleted"] as? [String: Any] ?? [:]
        var expected = 0
        for id in sourceIDs {
            var days = Set(rows.filter { $0["id"] as? String == id }.flatMap { $0["logs"] as? [String] ?? [] })
            let prefix = "habitlog:" + id + ":"
            for key in deleted.keys where key.hasPrefix(prefix) { days.insert(String(key.dropFirst(prefix.count))) }
            expected += days.count
        }
        let stamp = "habit-ui-" + UUID().uuidString
        let output = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("habits-import-" + stamp + ".json")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_HABITS": path, "MADAR_TRIAL_RUN": stamp,
            "MADAR_UI_HABIT_FIXTURE": "empty", "MADAR_UI_NOW": "2026-10-25T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let first = try report(output)
        XCTAssertNil(first["failed"]); XCTAssertEqual(first["store.habits"], sourceIDs.count)
        XCTAssertEqual(first["store.events"], expected)
        XCTAssertEqual(first["replay.created"], 0); XCTAssertEqual(first["replay.unchanged"], 1)
        open(app); shot(app, "TRIAL-habits-import-L")
        let all = app.buttons["habits-view-all"]; XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
        let habit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit-row-")).firstMatch
        XCTAssertTrue(habit.waitForExistence(timeout: 10)); shot(app, "TRIAL-habits-all-L"); habit.tap()
        XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout: 10)); shot(app, "TRIAL-habits-history-L")
        app.terminate(); try FileManager.default.removeItem(at: output); app.launch()
        let replay = try report(output)
        XCTAssertNil(replay["failed"]); XCTAssertEqual(replay["store.events"], first["store.events"])
        XCTAssertEqual(replay["store.habits"], first["store.habits"]); XCTAssertEqual(replay["habits.created"] ?? 0, 0)
        XCTAssertEqual(replay["replay.created"], 0); XCTAssertEqual(replay["replay.unchanged"], 1)
        open(app); shot(app, "TRIAL-habits-relaunch-L")
    }
}
