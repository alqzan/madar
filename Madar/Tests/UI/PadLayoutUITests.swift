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
    }
}
