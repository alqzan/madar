import XCTest

/// iPad layout captures: each wide room in landscape, saved under MADAR_PAD_SHOTS (host path) for review.
/// Skips on iPhone and when no output folder is given, so the regular suite is unaffected.
final class PadLayoutUITests: XCTestCase {
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
        XCTAssertFalse(app.buttons["الصلاة"].exists)
        sleep(1)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out).appending(path: "pad-sidebar-folded.png"))
        show.tap()
        XCTAssertTrue(app.buttons["الصلاة"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testWideRoomsInLandscape() throws {
        let out = ProcessInfo.processInfo.environment["MADAR_PAD_SHOTS"] ?? ""
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad || out.isEmpty)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rooms: [(String, [String: String])] = [
            ("prayer", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_NOW": "2026-10-08T16:20:00+03:00"]),
            ("notes", ["MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
            ("foundation", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
            ("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
            ("customize", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
            ("money", ["MADAR_UI_MONEY_FIXTURE": "expense", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
            ("quran", ["MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_NOW": "2026-10-17T12:00:00+03:00"]),
        ]
        for (tab, env) in rooms {
            let app = XCUIApplication()
            app.launchEnvironment = env.merging(["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_START_TAB": tab]) { $1 }
            app.launch()
            sleep(5)
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
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10), "Today's page stands beside the sidebar")
        XCTAssertTrue(app.textFields["diary-inline-field"].exists)
        let side = app.descendants(matching: .any)["diary-pad-sidebar"].frame, field = app.textFields["diary-inline-field"].frame
        XCTAssertLessThan(side.width, 420, "The sidebar stays a column, not the whole screen")
        XCTAssertGreaterThan(field.width, 300, "The page keeps real width")
        XCTAssertLessThan(side.midX, field.midX, "Right to left: the page holds the start edge, the sidebar stands at its left")
        // A rotation must not rebuild the page or replay a request: today's line is still there and no keyboard jumped up.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["السطر الثاني في اليوم نفسه"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "No focus replayed after the rotation")
        XCUIDevice.shared.orientation = .landscapeLeft
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "pad-diary-root"; shot.lifetime = .keepAlways; add(shot)
    }
}
