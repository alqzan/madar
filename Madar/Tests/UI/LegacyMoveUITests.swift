import XCTest

/// Item 24 «من مدار القديم» on the owner's real backup, in an isolated UI-test store only: settings → preview per room →
/// «انقل» → result → the same file again adds nothing → undo → the file moves again in full. Runs only when
/// TEST_RUNNER_MADAR_TRIAL_BACKUP names the old backup on this Mac.
@MainActor final class LegacyMoveUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.8); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 15) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing " + id)
        for _ in 0..<8 where !element.isHittable || element.frame.maxY > app.windows.firstMatch.frame.maxY * 0.8 { app.swipeUp(velocity: .slow) }
        element.tap()
    }
    private func move(_ app: XCUIApplication) -> String {
        tap(app, "legacy-move-commit")
        let result = app.staticTexts["legacy-move-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 1500), "The move did not finish")
        return result.label
    }

    func testOwnerBackupMovesOnceUndoesAndMovesAgain() throws {
        continueAfterFailure = false
        guard let backup = ProcessInfo.processInfo.environment["MADAR_TRIAL_BACKUP"] else { throw XCTSkip("Owner data trial only") }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_LEGACY_BACKUP": backup,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 5) { for _ in 0..<4 where start.exists && start.isHittable { start.tap(); Thread.sleep(forTimeInterval: 1) } }
        tap(app, "tab-customize", timeout: 20)
        let link = app.buttons["legacy-move-link"]
        for _ in 0..<14 where !link.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(link.isHittable, "No «انقل من مدار القديم» in settings"); link.tap()
        shot(app, "L01-move-start-L")

        tap(app, "legacy-move-choose")
        let prayer = app.descendants(matching: .any)["legacy-move-room-prayer"]
        XCTAssertTrue(prayer.waitForExistence(timeout: 30)); XCTAssertTrue(prayer.label.contains("مسجّل"), prayer.label)
        XCTAssertTrue(app.descendants(matching: .any)["legacy-move-room-money"].label.contains("حرك"))
        shot(app, "L01-move-preview-L"); app.swipeUp(velocity: .slow); shot(app, "L01-move-preview-s1-L")

        let first = move(app)
        XCTAssertEqual(first, "انتقلت غرفك إلى مدار.")
        let prayerOutcome = app.descendants(matching: .any)["legacy-move-outcome-prayer"]
        XCTAssertTrue(prayerOutcome.label.contains("وصل"), prayerOutcome.label)
        shot(app, "L01-move-result-L"); app.swipeUp(velocity: .slow); shot(app, "L01-move-result-s1-L")

        tap(app, "legacy-move-again"); tap(app, "legacy-move-choose")
        XCTAssertEqual(move(app), "كل ما في الملف عندك من قبل؛ لم يتكرر شيء.", "A second move of the same file must add nothing")
        shot(app, "L01-move-replay-L")

        tap(app, "legacy-move-undo")
        let confirm = app.buttons.matching(identifier: "legacy-move-undo-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["legacy-move-undone"].waitForExistence(timeout: 600))
        shot(app, "L01-move-undone-L")

        tap(app, "legacy-move-restart"); tap(app, "legacy-move-choose")
        XCTAssertEqual(move(app), "انتقلت غرفك إلى مدار.", "After undo the same file must move again")
        XCTAssertTrue(app.descendants(matching: .any)["legacy-move-outcome-prayer"].label.contains("وصل"))
    }
}
