import XCTest

/// Review T14 item 18: every room opens at the largest accessibility text size (AX5) and stays usable:
/// the app is alive, the room draws at least one reachable control. (Custom drawings switch to lists from AX1.)
@MainActor final class AccessibilitySizeUITests: XCTestCase {
    private func open(_ tab: String, _ extra: [String: String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "AX5", "MADAR_UI_THEME": "light",
                                 "MADAR_UI_START_TAB": tab, "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"].merging(extra) { $1 }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25))
        let controls = app.buttons
        XCTAssertTrue(controls.firstMatch.waitForExistence(timeout: 25), "\(tab) draws no control at AX5: " + app.debugDescription)
        let usable = controls.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.count
        XCTAssertGreaterThanOrEqual(usable, 1, "\(tab) at AX5 shows no usable control")
        XCTAssertEqual(app.state, .runningForeground)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "ax5-\(tab)"; shot.lifetime = .keepAlways; add(shot)
    }
    func testPrayerAX5() { open("prayer", ["MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_TRACKING_START": "2026-10-01"]) }
    func testQuranAX5() { open("quran", ["MADAR_UI_QURAN_FIXTURE": "home"]) }
    func testMoneyAX5() { open("money", ["MADAR_UI_MONEY_FIXTURE": "showcase"]) }
    func testDiaryAX5() { open("notes", ["MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1"]) }
    func testMihbaraAX5() { open("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home"]) }
    func testLobbyAX5() { open("foundation", ["MADAR_UI_HABIT_FIXTURE": "showcase"]) }
    func testCustomizeAX5() { open("customize", [:]) }
}
