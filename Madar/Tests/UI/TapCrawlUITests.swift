import XCTest

/// AU-95 (owner, 29 Oct: «اتوقع فيه مشاكل بالتطبيق بالضغط والازرار»): taps every reachable button on each room's
/// home, scrolling down page by page, and reports a crash or a button that changes nothing on screen.
/// The report lines start with `CRAWL|`; a silent button is a lead to check by hand, not proof of a defect.
@MainActor final class TapCrawlUITests: XCTestCase {
    private struct Finding { let room: String; let kind: String; let key: String }
    private var findings: [Finding] = []

    func testCrawlPrayer() { crawl("prayer", ["MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01"]) }
    func testCrawlQuran() { crawl("quran", ["MADAR_UI_QURAN_FIXTURE": "home"]) }
    func testCrawlMoney() { crawl("money", ["MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]) }
    func testCrawlDiary() { crawl("notes", ["MADAR_UI_DIARY_FIXTURE": "home"]) }
    func testCrawlMihbara() { crawl("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home"]) }
    func testCrawlLobby() { crawl("foundation", ["MADAR_UI_HABIT_FIXTURE": "showcase"]) }
    func testCrawlCustomize() { crawl("customize", [:]) }

    /// A tap on the empty end of a wide button, away from its text, must still press it.
    func testEdgeTapPressesWideButtons() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        app.buttons["money-open"].tap()
        let envelopes = app.buttons["money-envelopes-open"]; XCTAssertTrue(envelopes.waitForExistence(timeout: 10)); envelopes.tap()
        let add = app.buttons["money-envelopes-new-goal"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<8 where !(add.isHittable && add.frame.maxY < app.frame.maxY - 140) { app.swipeUp(velocity: .slow) }
        shot(app, "AU-95-edge-before-L")
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        let opened = app.buttons["money-goal-edit"].waitForExistence(timeout: 6)
        shot(app, "AU-95-edge-after-L")
        print("CRAWL|edge|money-envelopes-new-goal|\(opened ? "PRESSED" : "DEAD")")
        XCTAssertTrue(opened, "A tap on the empty end of «جهّز لشيء قادم» did nothing")
        app.terminate()
    }

    private func crawl(_ tab: String, _ extra: [String: String]) {
        // About forty minutes for all rooms: run on purpose with TEST_RUNNER_MADAR_UI_CRAWL=1, never in a full suite.
        guard ProcessInfo.processInfo.environment["MADAR_UI_CRAWL"] == "1" else { return }
        continueAfterFailure = true
        var env = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        env.merge(extra) { $1 }
        let app = XCUIApplication()
        app.launchEnvironment = env
        guard open(app, tab: tab, page: 0) else {
            print("CRAWL|\(tab)|INCOMPLETE|NO-TAB")
            print(app.debugDescription)
            app.terminate()
            return
        }
        var tested = Set<String>()
        var page = 0
        while page < 10 {
            while let (button, key) = nextCandidate(app, tested: tested) {
                tested.insert(key)
                let before = signature(app)
                button.tap()
                Thread.sleep(forTimeInterval: 1.2)
                if app.state != .runningForeground {
                    report(tab, "CRASH", key)
                    guard open(app, tab: tab, page: page) else {
                        print("CRAWL|\(tab)|INCOMPLETE|NO-TAB")
                        app.terminate()
                        return
                    }
                    continue
                }
                if signature(app) == before {
                    report(tab, "SILENT", key)
                    shot(app, "silent-\(tab)-\(key)")
                    continue
                }
                if !restore(app, to: before) {
                    app.terminate()
                    guard open(app, tab: tab, page: page) else {
                        print("CRAWL|\(tab)|INCOMPLETE|NO-TAB")
                        app.terminate()
                        return
                    }
                }
            }
            let before = signature(app)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
            if signature(app) == before { break }
            page += 1
        }
        print("CRAWL|\(tab)|DONE|tested \(tested.count) buttons, \(findings.filter { $0.room == tab }.count) leads")
        app.terminate()
    }

    private func open(_ app: XCUIApplication, tab: String, page: Int) -> Bool {
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 3) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        for _ in 0..<4 where start.waitForExistence(timeout: 2) && start.isHittable { start.tap(); Thread.sleep(forTimeInterval: 0.8) }
        let rootIdentifier = tab == "customize" ? "settings-tab" : "\(tab)-tab"
        if app.descendants(matching: .any).matching(identifier: rootIdentifier).firstMatch.waitForExistence(timeout: 5) {
            return true
        }
        let tabTitles = ["foundation": "البهو", "prayer": "الصلاة", "quran": "القرآن", "money": "المال", "mihbara": "المحبرة", "notes": "المذكرات", "customize": "خصّص"]
        let nativeTab = tabTitles[tab].map { app.tabBars.buttons[$0].firstMatch }
        let shortcut = app.buttons["tab-\(tab)"].firstMatch
        if let nativeTab, nativeTab.waitForExistence(timeout: 10) {
            nativeTab.tap()
        } else if shortcut.waitForExistence(timeout: 10) {
            shortcut.tap()
        } else {
            return false
        }
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<page { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
        return true
    }

    /// The first hittable button above the floating accessory that has not been tapped yet.
    private func nextCandidate(_ app: XCUIApplication, tested: Set<String>) -> (XCUIElement, String)? {
        let floor = app.frame.height - 130
        for button in app.buttons.allElementsBoundByIndex {
            guard button.exists else { continue }
            let id = button.identifier
            if id.hasPrefix("tab-") { continue }
            let key = id.isEmpty ? "label:" + button.label : id
            if key == "label:" || tested.contains(key) { continue }
            let frame = button.frame
            guard frame.minY > 50, frame.maxY < floor, frame.width > 1, button.isHittable else { continue }
            return (button, key)
        }
        return nil
    }

    /// The screen without numbers, pointers or frames, so a ticking clock does not count as a change.
    private func signature(_ app: XCUIApplication) -> String {
        let text = app.debugDescription
        return text.replacingOccurrences(of: "0x[0-9a-f]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[0-9٠-٩.,:{}\\- ]", with: "", options: .regularExpression)
    }

    private func restore(_ app: XCUIApplication, to before: String) -> Bool {
        let cancelWords = ["إلغاء", "أبقها", "تابع", "أكمل الكتابة", "أكمل التعديل", "لا", "Cancel", "إغلاق", "تم"]
        for _ in 0..<4 {
            if signature(app) == before { return true }
            if app.alerts.count > 0 || app.sheets.count > 0 {
                let box = app.alerts.count > 0 ? app.alerts.firstMatch : app.sheets.firstMatch
                let cancel = cancelWords.lazy.map { box.buttons[$0] }.first { $0.exists }
                (cancel ?? box.buttons.element(boundBy: box.buttons.count - 1)).tap()
            } else if let close = closeButton(app) {
                close.tap()
            } else if app.navigationBars.buttons.count > 0, app.navigationBars.buttons.firstMatch.isHittable {
                app.navigationBars.buttons.firstMatch.tap()
            } else {
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return signature(app) == before
    }

    private func closeButton(_ app: XCUIApplication) -> XCUIElement? {
        let ids = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'close' OR identifier CONTAINS[c] 'dismiss' OR identifier CONTAINS[c] 'cancel' OR identifier CONTAINS[c] 'back'"))
        if ids.count > 0, ids.firstMatch.isHittable { return ids.firstMatch }
        for word in ["إغلاق", "إلغاء", "تم", "رجوع", "Close", "Done"] where app.buttons[word].exists && app.buttons[word].isHittable {
            return app.buttons[word]
        }
        return nil
    }

    private func report(_ room: String, _ kind: String, _ key: String) {
        findings.append(Finding(room: room, kind: kind, key: key))
        print("CRAWL|\(room)|\(kind)|\(key)")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
