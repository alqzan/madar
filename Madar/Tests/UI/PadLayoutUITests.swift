import XCTest

/// iPad layout captures: each wide room in landscape, saved under MADAR_PAD_SHOTS (host path) for review.
/// Skips on iPhone and when no output folder is given, so the regular suite is unaffected.
@MainActor final class PadLayoutUITests: XCTestCase {
    private func waitForWindow(_ app: XCUIApplication, landscape: Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let frame = app.windows.firstMatch.frame
            if landscape ? frame.width > frame.height : frame.height > frame.width { return true }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return false
    }
    /// B2-19: the sidebar folds away and comes back; the choice is kept on the device.
    func testSidebarFoldsAndReturns() throws {
        let out = ProcessInfo.processInfo.environment["MADAR_PAD_SHOTS"] ?? ""
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad || out.isEmpty)
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00", "MADAR_UI_START_TAB": "foundation"]
        app.launch()
        let hide = app.buttons["أخفِ القائمة"]
        XCTAssertTrue(hide.waitForExistence(timeout: 20), app.debugDescription)
        sleep(2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-sidebar-open.png"))
        hide.tap()
        let show = app.buttons["أظهر القائمة"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["القرآن"].exists)
        sleep(1)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-sidebar-folded.png"))
        show.tap()
        XCTAssertTrue(app.buttons["القرآن"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testSidebarRoomChangesKeepAnUnsavedExpenseOpen() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_MONEY_FIXTURE": "expense",
            "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00",
            "MADAR_UI_START_TAB": "money",
            "MADAR_UI_PAD_SIZE_CHANGE": "1",
        ]
        app.launch()

        let show = app.buttons["pad-sidebar-show"]
        let hide = app.buttons["pad-sidebar-hide"]
        XCTAssertTrue(app.staticTexts["money-reserve"].waitForExistence(timeout: 25), app.debugDescription)
        if show.exists { show.tap() }
        XCTAssertTrue(hide.waitForExistence(timeout: 10), app.debugDescription)
        let open = app.buttons["money-expense-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 25), app.debugDescription)
        let amount = app.staticTexts["money-expense-amount"]
        open.tap()
        if !amount.waitForExistence(timeout: 3), open.isHittable { open.tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["money-expense-key-4"].tap()
        app.buttons["money-expense-key-2"].tap()
        XCTAssertTrue(amount.label.contains("٤٢"), amount.label)

        for room in ["quran", "notes", "mihbara"] {
            let destination = app.buttons["tab-" + room]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing iPad room destination: \(room)")
            destination.tap()
        }
        app.buttons["tab-money"].tap()

        XCTAssertTrue(app.buttons["money-expense-close"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(amount.label.contains("٤٢"), "Room retention must preserve the unsaved amount: \(amount.label)")
        XCTAssertTrue(app.buttons["money-expense-save"].isEnabled)

        let sizeClass = app.buttons["pad-size-class-test-toggle"]
        sizeClass.tap()
        XCTAssertTrue(hide.waitForNonExistence(timeout: 10), "Compact iPad windows fold the sidebar")
        XCTAssertTrue(amount.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(amount.label.contains("٤٢"), "The editor must survive the narrower size class")
        XCTAssertFalse(app.buttons["tab-foundation"].exists, "The expense editor conceals the compact navigation bar")

        sizeClass.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        XCTAssertTrue(amount.label.contains("٤٢"), "Returning to the sidebar must preserve the same draft")
    }

    func testFoldedSidebarLeavesLobbyActionsReachable() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_MONEY_FIXTURE": "expense",
            "MADAR_UI_START_TAB": "foundation",
        ]
        app.launch()

        let hide = app.buttons["pad-sidebar-hide"]
        let show = app.buttons["pad-sidebar-show"]
        if show.exists { show.tap() }
        XCTAssertTrue(hide.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(waitForWindow(app, landscape: false))
        hide.tap()
        defer { if show.isHittable { show.tap() } }
        XCTAssertTrue(show.waitForExistence(timeout: 10))

        let customize = app.buttons["bahw-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        XCTAssertFalse(show.frame.intersects(customize.frame), "Restoring the sidebar must leave the lobby controls clear")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "pad-folded-sidebar-lobby-portrait"
        shot.lifetime = .keepAlways
        add(shot)
        customize.tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10), app.debugDescription)
        show.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
    }

    func testWideRoomsInLandscape() throws {
        let out = ProcessInfo.processInfo.environment["MADAR_PAD_SHOTS"] ?? ""
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad || out.isEmpty)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rooms: [(String, [String: String], String)] = [
            ("notes", ["MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "diary-day-more"),
            ("foundation", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "bahw-habits-open"),
            ("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "mihbara-library"),
            ("customize", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "settings-search"),
            ("money", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "money-title"),
            ("quran", ["MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"], "quran-home"),
        ]
        for (tab, env, contentIdentifier) in rooms {
            let app = XCUIApplication()
            app.launchEnvironment = env.merging(["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_START_TAB": tab]) { $1 }
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)[contentIdentifier].waitForExistence(timeout: 30),
                          "The iPad \(tab) room must show room content: " + app.debugDescription)
            sleep(1)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-\(tab).png"))
            app.terminate()
        }
        // The mushaf opens as two facing pages in landscape.
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]
        app.launch()
        let mushaf = app.buttons["quran-tool-mushaf"]
        for _ in 0..<4 where !mushaf.isHittable { app.swipeUp() }
        mushaf.tap()
        sleep(4)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-mushaf.png"))
        app.terminate()
        // A memorisation session.
        app.launch()
        let begin = app.buttons["quran-begin"].firstMatch
        if begin.waitForExistence(timeout: 10) { begin.tap() }
        sleep(12)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-session.png"))
        app.terminate()
        // A PDF book opens as two facing pages, right to left.
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 600)).pdfData { context in
            for page in 1...4 {
                context.beginPage()
                ("صفحة \(page)" as NSString).draw(at: CGPoint(x: 140, y: 270), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48)])
            }
        }
        // The diary's day page.
        let diary = XCUIApplication()
        diary.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "today", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00", "MADAR_UI_START_TAB": "notes"]
        diary.launch()
        let today = diary.buttons["diary-today"].firstMatch
        if today.waitForExistence(timeout: 10) { today.tap() }
        sleep(3)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-diary-day.png"))
        diary.terminate()
        let reader = XCUIApplication()
        reader.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "missingFile", "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString(),
                                    "MADAR_UI_MIHBARA_PDF_READY": "1", "MADAR_UI_MIHBARA_ROUTE": "madar://mihbara/continue", "MADAR_UI_START_TAB": "mihbara"]
        reader.launch()
        _ = reader.buttons["mihbara-pdf-ink"].waitForExistence(timeout: 20)
        sleep(2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-pdf.png"))
    }
    /// 14 Nov owner (iPad): the diary opens on today's page, with the years and recent days in a column beside it; real assertions.
    func testDiaryRootOnPadHasASidebarBesideTodaysPage() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1",
                                 "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_START_TAB": "notes"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["diary-pad-sidebar"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["diary-year-strip"].exists, "The inline year strip must not flash into the measured iPad landscape root")
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10), "Today's page stands beside the sidebar")
        XCTAssertTrue(app.textFields["diary-inline-field"].exists)
        let dayTitle = app.staticTexts["diary-day-title"]
        let secondaryDate = app.staticTexts["diary-day-secondary-date"]
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(secondaryDate.exists, app.debugDescription)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, app.debugDescription)
        let side = app.descendants(matching: .any)["diary-pad-sidebar"].frame, field = app.textFields["diary-inline-field"].frame
        XCTAssertLessThan(side.width, 420, "The sidebar stays a column, not the whole screen")
        XCTAssertGreaterThan(field.width, 300, "The page keeps real width")
        XCTAssertLessThan(side.midX, field.midX, "Right to left: the page holds the start edge, the sidebar stands at its left")
        // A rotation must not rebuild the page or replay a request: today's line is still there and an unfocused field stays keyboard-free.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForWindow(app, landscape: false), "Wait for the iPad to finish laying out in portrait")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "No focus replayed after the rotation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForWindow(app, landscape: true), "Wait for the iPad to finish laying out in landscape")
        XCTAssertTrue(app.descendants(matching: .any)["diary-pad-sidebar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let bounds = window.frame
        for (name, element) in [("day title", dayTitle), ("secondary date", secondaryDate), ("writing field", app.textFields["diary-inline-field"])] {
            let frame = element.frame
            XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }, "The \(name) must have finite geometry")
            XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX - 1, "The \(name) must remain inside the app window")
            XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY - 1, "The \(name) must remain inside the app window")
            XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX + 1, "The \(name) must remain inside the app window")
            XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY + 1, "The \(name) must remain inside the app window")
        }
        let shot = XCTAttachment(screenshot: window.screenshot()); shot.name = "pad-diary-root-window"; shot.lifetime = .keepAlways; add(shot)
    }
}
