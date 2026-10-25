import XCTest

@MainActor final class PersonalOwnerTrialUITests: XCTestCase {
    private func report(_ url: URL) throws -> [String: Int] {
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testOwnerSealedMailboxAndOrdinaryDayImportWithoutGrowth() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP"] else { throw XCTSkip("Owner backup opt-in only") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let letters = root["futureLetters"] as? [[String: Any]] ?? []
        let days = root["countdownEvents"] as? [[String: Any]] ?? []
        let ordinary = days.filter { $0["countUpAfter"] as? Bool != true }
        let stamp = "personal-ui-" + UUID().uuidString
        let output = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("personal-import-" + stamp + ".json")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_PERSONAL": path, "MADAR_TRIAL_RUN": stamp,
            "MADAR_UI_DIARY_FIXTURE": "empty", "MADAR_UI_NOW": "2026-10-25T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let first = try report(output)
        XCTAssertNil(first["failed"]); XCTAssertEqual(first["store.letters"], letters.count)
        XCTAssertEqual(first["store.days"], ordinary.count)
        XCTAssertEqual(first["archived.countUpAfter"] ?? 0, days.count - ordinary.count)
        XCTAssertEqual(first["replay.created"], 0); XCTAssertEqual(first["replay.unchanged"], 1)
        let diary = app.buttons["diary-days"]; XCTAssertTrue(diary.waitForExistence(timeout: 30)); diary.tap()
        app.buttons["diary-hub-letters"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "diary-letter-sealed").firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["diary-letter-text"].exists)
        shot(app, "TRIAL-personal-sealed-mailbox-L")
        app.buttons["diary-hub-close"].tap()
        let bahw = app.tabBars.buttons["البهو"].firstMatch; XCTAssertTrue(bahw.waitForExistence(timeout: 10)); bahw.tap()
        let year = app.descendants(matching: .any)["bahw-block-year"]
        for _ in 0..<8 where !year.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(year.isHittable); year.tap()
        let mine = app.buttons["أيامي"]; XCTAssertTrue(mine.waitForExistence(timeout: 10)); mine.tap()
        for source in ordinary {
            guard let title = source["title"] as? String else { continue }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-matter-" + title).firstMatch.waitForExistence(timeout: 10))
        }
        shot(app, "TRIAL-personal-day-L")
        app.terminate(); try FileManager.default.removeItem(at: output); app.launch()
        let replay = try report(output)
        XCTAssertNil(replay["failed"]); XCTAssertEqual(replay["store.days"], first["store.days"])
        XCTAssertEqual(replay["store.letters"], first["store.letters"])
        XCTAssertEqual(replay["letters.created"] ?? 0, 0); XCTAssertEqual(replay["days.created"] ?? 0, 0)
        XCTAssertEqual(replay["replay.created"], 0); XCTAssertEqual(replay["replay.unchanged"], 1)
    }
}
