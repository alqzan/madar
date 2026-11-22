import XCTest

/// Review T14 item 18: every room opens at the largest accessibility text size (AX5) and stays usable:
/// the app is alive, the room draws at least one reachable control. (Custom drawings switch to lists from AX1.)
@MainActor final class AccessibilitySizeUITests: XCTestCase {
    private func open(_ tab: String, _ extra: [String: String], contentIdentifier: String? = nil) {
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
        if let contentIdentifier {
            XCTAssertTrue(app.descendants(matching: .any)[contentIdentifier].waitForExistence(timeout: 10),
                          "\(tab) at AX5 must expose its actual room content: " + app.debugDescription)
        }
        XCTAssertEqual(app.state, .runningForeground)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "ax5-\(tab)"; shot.lifetime = .keepAlways; add(shot)
    }
    func testQuranAX5() { open("quran", ["MADAR_UI_QURAN_FIXTURE": "home"], contentIdentifier: "quran-home") }
    func testMoneyAX5() { open("money", ["MADAR_UI_MONEY_FIXTURE": "showcase"], contentIdentifier: "money-title") }
    func testDiaryAX5() { open("notes", ["MADAR_UI_DIARY_FIXTURE": "entryRoute", "MADAR_UI_DIARY_ROOT": "1"], contentIdentifier: "diary-day-more") }
    func testMihbaraAX5() { open("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home"], contentIdentifier: "mihbara-library") }
    func testLobbyAX5() { open("foundation", ["MADAR_UI_HABIT_FIXTURE": "showcase"], contentIdentifier: "bahw-habits-open") }
    func testCustomizeAX5() { open("customize", [:]) }
}
