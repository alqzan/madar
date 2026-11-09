import XCTest

/// iPad layout captures: each wide room in landscape, saved under MADAR_PAD_SHOTS (host path) for review.
/// Skips on iPhone and when no output folder is given, so the regular suite is unaffected.
final class PadLayoutUITests: XCTestCase {
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
}
