import XCTest

/// Owner real-data trial, item 19 (24 Oct 2026). Runs only when TEST_RUNNER_MADAR_TRIAL_BACKUP names the old backup and
/// TEST_RUNNER_MADAR_TRIAL_ZIP its diary as a Day One ZIP on this Mac: money, Quran, prayer and diary go into ONE fresh
/// UI-test store, then the money room, the diary and the Mihbara are walked with all of it present.
@MainActor final class OwnerAllDataTrialUITests: XCTestCase {
    /// Records and dismisses any app alert so the walk continues; the alert text is a finding.
    private func clearAlert(_ app: XCUIApplication, _ where_: String) {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        shot(app, "TRIAL-alert-\(where_)-L"); add(XCTAttachment(string: "ALERT at \(where_): " + text)); XCTFail("App alert at \(where_): " + text)
        alert.buttons.firstMatch.tap()
    }
    private func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.8); let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func report(_ url: URL, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 2) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], "No trial report \(url.lastPathComponent)")
    }
    /// Opens a money sheet by its `-open` id, captures it and its scrolled state, then closes it by its `-close` id.
    private func visit(_ app: XCUIApplication, _ base: String) {
        let open = app.buttons["money-\(base)-open"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp(velocity: .slow) }
        guard open.exists, open.isHittable else { XCTFail("Required money page is unreachable: \(base)"); return }
        open.tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-money-\(base)-L")
        app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-\(base)-s1-L")
        let close = app.buttons["money-\(base)-close"]
        for _ in 0..<5 where !(close.exists && close.isHittable) { app.swipeDown(velocity: .slow) }
        let back = app.buttons["money-\(base)-back"]
        if close.exists && close.isHittable { close.tap() }
        else if back.exists && back.isHittable { back.tap() }
        else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        else { app.swipeDown(velocity: .fast) }
        _ = app.buttons["money-expense-open"].waitForExistence(timeout: 5)
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
    }
    private func reach(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let element = app.buttons.matching(identifier: id).firstMatch
        for _ in 0..<10 where !element.isHittable { app.swipeUp(velocity: .slow) }
        // isHittable is true under the floating tab bar too, so keep the target in the upper part of the screen.
        let bottom = app.windows.firstMatch.frame.maxY * 0.7
        for _ in 0..<4 where element.exists && element.frame.maxY > bottom { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing required route: " + id)
        XCTAssertTrue(element.isHittable, "Offscreen required route: " + id)
        return element
    }
    private func close(_ app: XCUIApplication, _ id: String) {
        let element = app.buttons.matching(identifier: id).firstMatch
        for _ in 0..<12 where !element.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(element.waitForExistence(timeout: 10)); XCTAssertTrue(element.isHittable)
        if element.exists && element.isHittable { element.tap() }
    }
    private func homeTop(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 15))
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
    }
    private func visitNestedMoneyPages(_ app: XCUIApplication) {
        homeTop(app)
        reach(app, "money-basis-open").tap()
        let cash = app.buttons["money-cash-open"]
        guard cash.waitForExistence(timeout: 15) else { XCTFail("Basis sheet did not open"); shot(app, "TRIAL-money-basis-missing-L"); return }
        XCTAssertTrue(cash.label.contains("—"), "Actual source has no confirmed bank checkpoint")
        shot(app, "TRIAL-money-basis-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-basis-s1-L")
        for _ in 0..<6 where !cash.isHittable { app.swipeDown(velocity: .fast) }
        cash.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "money-cash").firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["money-cash-total"].label, "—"); XCTAssertEqual(app.staticTexts["money-cash-net"].label, "—")
        shot(app, "TRIAL-money-cash-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-cash-s1-L")
        close(app, "money-page-close") // Cash -> basis, then dismiss the basis sheet.
        XCTAssertTrue(cash.waitForExistence(timeout: 10)); close(app, "money-page-close")
        homeTop(app)
        reach(app, "money-pending").tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 15))
        reach(app, "money-budget-open").tap()
        XCTAssertTrue(app.staticTexts["money-budget-excluded-total"].waitForExistence(timeout: 15))
        shot(app, "TRIAL-money-budget-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-budget-s1-L")
        close(app, "money-budget-close"); XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        close(app, "money-messages-close")
        homeTop(app)
        reach(app, "money-log-open").tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "money-log-arcade").firstMatch.waitForExistence(timeout: 15))
        shot(app, "TRIAL-money-log-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-log-s1-L")
        for _ in 0..<8 where !app.buttons["money-log-search-open"].isHittable { app.swipeDown(velocity: .fast) }
        app.buttons["money-log-search-open"].tap()
        let field = app.textFields["money-log-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("غيرموجود\n")
        XCTAssertTrue(app.staticTexts["money-log-search-empty"].waitForExistence(timeout: 10)); shot(app, "TRIAL-money-log-search-L")
        app.buttons["مسح البحث"].tap(); close(app, "money-log-close"); homeTop(app)
    }
    /// A tab tap can leave the lobby in front, so trust only the money-home marker and fall back to the
    /// customise search route that MoneyHomeUITests uses.
    private func openMoney(_ app: XCUIApplication) {
        let mal = app.tabBars.buttons["المال"].firstMatch
        if mal.waitForExistence(timeout: 20) { mal.tap() }
        if !app.buttons["money-expense-open"].waitForExistence(timeout: 10) {
            let more = app.buttons["tab-customize"]; XCTAssertTrue(more.waitForExistence(timeout: 60), app.debugDescription); more.tap()
            let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("المال")
            let open = app.buttons["money-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        }
        XCTAssertTrue(app.buttons["money-expense-open"].waitForExistence(timeout: 30), app.debugDescription)
    }
    /// Strict walk r3/r4: with the owner's money (accounts, no cycle) «على أي أساس» did not open. Money only, straight to it.
    func testOwnerMoneyBasisOpens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let backup = env["MADAR_TRIAL_BACKUP"] else { throw XCTSkip("Owner data trial only") }
        let stamp = "basis-" + String(Int(Date().timeIntervalSince1970))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_RUN": stamp,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        _ = try report(URL(fileURLWithPath: backup).deletingLastPathComponent().appendingPathComponent("money-import-\(stamp).json"), timeout: 600)
        clearAlert(app, "basis-import")
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 5) { for _ in 0..<4 where start.exists && start.isHittable { start.tap(); Thread.sleep(forTimeInterval: 1) } }
        openMoney(app)
        let basis = reach(app, "money-basis-open"); shot(app, "BASIS-before-L"); basis.tap()
        let opened = app.buttons["money-page-close"].waitForExistence(timeout: 10)
        shot(app, "BASIS-after-L")
        XCTAssertTrue(opened, app.debugDescription)
    }
    func testOwnerAllDataTrial() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let backup = env["MADAR_TRIAL_BACKUP"], let zip = env["MADAR_TRIAL_ZIP"] else { throw XCTSkip("Owner data trial only") }
        let folder = URL(fileURLWithPath: backup).deletingLastPathComponent()
        let stamp = "all-" + String(Int(Date().timeIntervalSince1970))
        let diaryReport = folder.appendingPathComponent("diary-import-\(stamp).json")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_TRIAL_MONEY": backup, "MADAR_TRIAL_QURAN": backup, "MADAR_TRIAL_PRAYER": backup, "MADAR_TRIAL_HABITS": backup, "MADAR_TRIAL_PERSONAL": backup,
                                 "MADAR_UI_LEGACY_DIARY_ZIP": zip, "MADAR_UI_LEGACY_REPORT": diaryReport.path, "MADAR_TRIAL_RUN": stamp,
                                 "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        for room in ["money", "quran", "prayer", "habits", "personal"] {
            let r = try report(folder.appendingPathComponent("\(room)-import-\(stamp).json"), timeout: 1200)
            XCTAssertNil(r["failed"], "\(room): \(r)")
            if room == "habits" || room == "personal" {
                XCTAssertEqual(r["replay.created"] as? Int, 0)
                XCTAssertEqual(r["replay.unchanged"] as? Int, 1)
            }
            add(XCTAttachment(string: "\(room): \(r.filter { $0.key.hasPrefix("store.") })"))
        }
        let diary = try report(diaryReport, timeout: 900)
        XCTAssertNil(diary["error"], "diary: \(diary)")
        add(XCTAttachment(string: "diary: \(diary["store"] ?? "-")"))

        clearAlert(app, "after-import")
        // Money room.
        openMoney(app)
        clearAlert(app, "money"); shot(app, "TRIAL-money-home-L")
        for i in 1...5 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-money-home-s\(i)-L") }
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        for base in ["accounts", "categories", "envelopes", "obligations", "cards", "analysis", "reconcile", "cashback", "goal", "zakat", "settings"] { visit(app, base) }
        visitNestedMoneyPages(app)

        // Diary.
        clearAlert(app, "diary")
        // The diary opens from the notebook in the floating bar of a room home, so return to the money home first.
        for _ in 0..<3 where !app.buttons["money-expense-open"].exists { if let back = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '-back'")).allElementsBoundByIndex.first(where: \.isHittable) { back.tap() } else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() } else { app.swipeRight() } ; Thread.sleep(forTimeInterval: 1) }
        let notes = app.buttons["tab-notes"]; XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        let next = app.buttons["diary-welcome-next"]
        if next.waitForExistence(timeout: 5) { for _ in 0..<6 where next.exists { next.tap(); _ = app.buttons["diary-days"].waitForExistence(timeout: 2) } }
        XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout: 30), app.debugDescription); shot(app, "TRIAL-diary-home-L")
        for i in 1...3 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-diary-home-s\(i)-L") }
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        app.buttons["diary-days"].tap()
        if app.buttons["diary-calendar-scale-year"].waitForExistence(timeout: 30) {
            shot(app, "TRIAL-diary-hub-L")
            for tab in ["diary-hub-timeline", "diary-hub-photos", "diary-hub-letters"] where app.buttons[tab].exists { app.buttons[tab].tap(); Thread.sleep(forTimeInterval: 1.5); shot(app, "TRIAL-" + tab + "-L") }
            if app.buttons["diary-hub-close"].exists { app.buttons["diary-hub-close"].tap() } else { app.swipeDown(velocity: .fast) }
        }
        let search = app.buttons["diary-search"]
        if search.waitForExistence(timeout: 5) {
            search.tap(); let field = app.textFields["diary-search-query"]
            if field.waitForExistence(timeout: 5) { field.tap(); field.typeText("الصلاة"); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-diary-search-L") }
            if app.buttons["diary-search-close"].exists { app.buttons["diary-search-close"].tap() }
        }

        // Mihbara (the old backup holds no books, reading logs or benefits).
        let mihbara = app.tabBars.buttons["المحبرة"].firstMatch
        XCTAssertTrue(mihbara.waitForExistence(timeout: 20)); mihbara.tap(); Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 20), "The Mihbara home must actually open")
        shot(app, "TRIAL-mihbara-home-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-mihbara-home-s1-L")

        // The lobby with every room's data.
        let bahwTab = app.tabBars.buttons["البهو"].firstMatch, bahw = bahwTab.waitForExistence(timeout: 5) ? bahwTab : app.buttons["البهو"].firstMatch
        XCTAssertTrue(bahw.waitForExistence(timeout: 10), "The lobby is a required room")
        if bahw.exists { bahw.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "TRIAL-bahw-L"); for i in 1...3 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-bahw-s\(i)-L") } }
        // Prayer and Quran homes, then the habits room from the lobby (Claude, 24 Oct tour).
        for (tab, name) in [("الصلاة", "prayer"), ("القرآن", "quran")] {
            let button = app.tabBars.buttons[tab].firstMatch
            guard button.waitForExistence(timeout: 10) else { XCTFail("Required room tab missing: " + tab); continue }
            button.tap(); Thread.sleep(forTimeInterval: 2); clearAlert(app, name)
            let marker = app.descendants(matching: .any).matching(identifier: name == "prayer" ? "prayer-today-header" : "quran-coverage-title").firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 20), "The " + name + " home must actually open; a tab tap alone is not proof")
            shot(app, "TRIAL-\(name)-home-L")
            for i in 1...4 { app.swipeUp(velocity: .slow); shot(app, "TRIAL-\(name)-home-s\(i)-L") }
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }
        // After a long scroll the tab bar can collapse to icons, so the labelled tab is gone; scroll back and use the
        // dock's lobby button when the labelled tab is missing.
        for _ in 0..<4 where !bahwTab.exists { app.swipeDown(velocity: .fast) }
        if bahwTab.exists { bahwTab.tap() } else if bahw.exists { bahw.tap() }
        Thread.sleep(forTimeInterval: 1)
        let habits = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        for _ in 0..<6 where !(habits.exists && habits.isHittable) { app.swipeDown(velocity: .fast) }
        if habits.waitForExistence(timeout: 10) {
            let header = app.buttons["bahw-habits-open"]; if header.exists { header.tap() } else { habits.tap() }
            XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10), "The habits room must actually open")
            if app.staticTexts["habits-title"].exists { shot(app, "TRIAL-habits-L"); app.swipeUp(velocity: .slow); shot(app, "TRIAL-habits-s1-L") }
        } else { XCTFail("Required habits block is missing") }
    }

    /// Owner's real book (25 Oct, «أربعون»): import through the scan, then read. Private; skipped without the file.
    func testOwnerBookImportAndRead() throws {
        guard let book = ProcessInfo.processInfo.environment["MADAR_TRIAL_BOOK"] else { throw XCTSkip("Owner book trial only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-25T20:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_EPUB_PATH": book]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 240), app.debugDescription)
        _ = app.descendants(matching: .any)["mihbara-epub-scan-text"].waitForExistence(timeout: 120)
        shot(app, "BOOK-scan-L")
        for i in 1...4 { app.swipeUp(velocity: .slow); shot(app, "BOOK-scan-s\(i)-L") }
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 120), app.debugDescription)
        shot(app, "BOOK-shelf-L"); wantShelf.tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "أربعون")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 15), app.debugDescription)
        shot(app, "BOOK-want-L"); imported.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 60), app.debugDescription)
        Thread.sleep(forTimeInterval: 4); shot(app, "BOOK-reader-0-L")
        // Record what the page really holds after each turn, so a blank capture is told apart from a slow draw.
        func page(_ name: String) {
            Thread.sleep(forTimeInterval: 3); shot(app, name)
            let texts = app.webViews.firstMatch.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: " | ")
            let images = app.webViews.firstMatch.images.count
            let a = XCTAttachment(string: "texts: " + texts + "\nimages: \(images)"); a.name = name + "-text"; a.lifetime = .keepAlways; self.add(a)
        }
        for i in 1...5 { app.swipeRight(); page("BOOK-reader-next\(i)-L") }
        app.swipeLeft(); page("BOOK-reader-back-L")
        let contents = app.buttons["mihbara-reader-contents"]
        if !contents.exists { app.tap() }
        if contents.waitForExistence(timeout: 5) {
            contents.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "BOOK-contents-L")
            let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "مع قرآني")).firstMatch
            if chapter.waitForExistence(timeout: 5) { chapter.tap(); Thread.sleep(forTimeInterval: 3); shot(app, "BOOK-chapter1-L") }
            else { app.swipeUp(velocity: .slow); shot(app, "BOOK-contents-s1-L") }
        } else { shot(app, "BOOK-no-contents-L") }
    }

    /// Owner's scanned PDF (25 Oct, «مشروع العمر», 163 image-only pages): import, convert on the device through
    /// Offer → convert in the background → «افتحه» → read; the index comes from the printed contents. Private; skipped without the file.
    func testOwnerPDFConvertsAndReads() throws {
        guard let book = ProcessInfo.processInfo.environment["MADAR_TRIAL_PDF"] else { throw XCTSkip("Owner PDF trial only") }
        continueAfterFailure = false
        let title = "مشروع العمر"
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-25T20:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_PATH": book, "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": title]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 120), app.debugDescription)
        shot(app, "PDF-preview-L"); app.swipeUp(velocity: .slow); shot(app, "PDF-preview-s1-L")
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        // Owner, 25 Oct 2026: adding the PDF offers the conversion, which runs while the app stays usable.
        let convert = app.alerts.buttons["حوّله"].firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 60), app.debugDescription)
        shot(app, "PDF-flow-offer-L"); convert.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-flow-progress"].waitForExistence(timeout: 30), app.debugDescription)
        Thread.sleep(forTimeInterval: 20); shot(app, "PDF-flow-progress-L")
        let started = Date()
        let open = app.buttons["mihbara-pdf-flow-open"]
        let ready = open.waitForExistence(timeout: 1800)
        let seconds = Int(Date().timeIntervalSince(started)) + 20
        let timing = XCTAttachment(string: "conversion seconds: \(seconds)"); timing.name = "PDF-flow-seconds"; timing.lifetime = .keepAlways; self.add(timing)
        XCTAssertTrue(ready, app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "١٦٣")).firstMatch.exists, "All 163 pages must be counted")
        shot(app, "PDF-flow-ready-L"); open.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 30), app.debugDescription)
        Thread.sleep(forTimeInterval: 3); shot(app, "PDF-epub-0-L")
        func page(_ name: String) {
            Thread.sleep(forTimeInterval: 3); shot(app, name)
            let texts = app.webViews.firstMatch.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: " | ")
            let a = XCTAttachment(string: "texts: " + texts); a.name = name + "-text"; a.lifetime = .keepAlways; self.add(a)
        }
        for i in 1...3 { app.swipeRight(); page("PDF-epub-next\(i)-L") }
        let contents = app.buttons["mihbara-reader-contents"]
        if !contents.exists { app.tap() }
        XCTAssertTrue(contents.waitForExistence(timeout: 5), app.debugDescription)
        contents.tap(); Thread.sleep(forTimeInterval: 2); shot(app, "PDF-contents-L")
        // «سحب الفهرس خطأ مع انه موجود واضح»: the index comes from the book's printed contents (22 chapters and their topics).
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-reader-toc-"))
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertGreaterThanOrEqual(entries.count, 22, app.debugDescription)
        let names = XCTAttachment(string: entries.allElementsBoundByIndex.map(\.label).joined(separator: "\n")); names.name = "PDF-contents"; names.lifetime = .keepAlways; self.add(names)
        // Each printed chapter keeps its own title (an id from the link alone repeated one title for a shared page).
        let labels = entries.allElementsBoundByIndex.map(\.label)
        for chapter in ["لحظةُ البدايةِ", "ما الفرقُ بينَ العملِ", "هل يمكنُ أنْ يحوّلَ", "أصحابُ المشاريعِ"] {
            XCTAssertTrue(labels.contains { $0.contains(chapter) }, chapter + ": " + labels.joined(separator: " | "))
        }
        XCTAssertEqual(labels.filter { $0.hasPrefix("مشروع إغاثة الفقراء") }.count, 1, labels.joined(separator: " | "))
        let intro = entries.matching(NSPredicate(format: "label BEGINSWITH %@", "المقدمة")).firstMatch
        XCTAssertTrue(intro.exists, app.debugDescription); intro.tap()
        let introPage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["mihbara-reader-print-page"].label.contains("٨ ")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [introPage], timeout: 15), .completed, "The introduction starts on file page 8; page 9 continues it")
        let body = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.webViews.staticTexts.allElementsBoundByIndex.contains { $0.label.precomposedStringWithCompatibilityMapping.contains("فأحببتُ أوَّلاً أن يكون") }
        }, object: nil)
        let found = XCTWaiter.wait(for: [body], timeout: 20)
        page("PDF-epub-intro-L")
        XCTAssertEqual(found, .completed, "Source page 9, in «المقدمة», prints «فأحببتُ أوَّلاً أن يكون»")
        XCTAssertFalse(app.webViews.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("صفحة ٥: لم يُستخرج") }, "The basmala page is a picture")
        // The printed contents page inside the book is the parsed contents: its chapter links open the chapter.
        if !app.buttons["mihbara-reader-contents"].exists { app.tap() }
        app.buttons["mihbara-reader-contents"].tap()
        let lastEntry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-reader-toc-")).allElementsBoundByIndex.last
        XCTAssertNotNil(lastEntry, app.debugDescription); lastEntry?.tap()
        let chapterLink = app.webViews.links.matching(NSPredicate(format: "label CONTAINS %@", "لحظةُ البدايةِ")).firstMatch
        for _ in 0..<24 where !chapterLink.isHittable { app.swipeRight(); Thread.sleep(forTimeInterval: 1.5) }
        page("PDF-epub-printed-contents-L")
        XCTAssertTrue(chapterLink.isHittable, "The printed contents page must show chapter ١ as a tappable link")
        chapterLink.tap()
        let chapterOne = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            String(app.staticTexts["mihbara-reader-print-page"].label.unicodeScalars.filter { !"\u{2066}\u{2067}\u{2068}\u{2069}".unicodeScalars.contains($0) }).contains("١٢")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [chapterOne], timeout: 10), .completed, "Chapter ١ starts on file page ١٢")
        page("PDF-epub-chapter1-from-contents-L")
        // Browse the reported area against the scan: chapter 14 starts on file page 92.
        func footerPage() -> Int? {
            let text = app.staticTexts["mihbara-reader-print-page"].label
            let token = text.components(separatedBy: .whitespaces).first { $0.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } } ?? ""
            return Int(token.compactMap { $0.wholeNumberValue }.map(String.init).joined())
        }
        if !contents.exists { app.tap() }
        contents.tap()
        let projectChapter = entries.matching(NSPredicate(format: "label BEGINSWITH %@", "١٤ -")).firstMatch
        XCTAssertTrue(projectChapter.exists, "The index includes chapter 14, «كيف تتعرف على مشروعك»")
        for _ in 0..<12 where !projectChapter.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(projectChapter.isHittable); projectChapter.tap()
        let chapter14 = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in footerPage() == 92 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [chapter14], timeout: 15), .completed, "Chapter 14 starts on file page 92 in the source scan")
        page("PDF-browse-chapter14-L")
        for turn in 1...24 {
            if footerPage() == 94 { break }
            app.swipeRight(); Thread.sleep(forTimeInterval: 1)
            if turn % 4 == 0 { page("PDF-browse-near94-turn\(turn)-L") }
        }
        XCTAssertEqual(footerPage(), 94, "Forward reading must reach the source's page 94 without a false jump")
        page("PDF-browse-page94-L")
        // Owner: «خل دائما فيه خيار لعرضه PDF» — the original opens at the same page.
        // The page on screen, from the footer («ص ٢ بحسب الملف»), must be the page the original opens on.
        let isolates = CharacterSet(charactersIn: "\u{2066}\u{2067}\u{2068}\u{2069}")
        let plain = { (text: String) in String(text.unicodeScalars.filter { !isolates.contains($0) }) }
        let footer = plain(app.staticTexts["mihbara-reader-print-page"].label)
        let shownPage = footer.components(separatedBy: " ").dropFirst().first ?? ""
        XCTAssertFalse(shownPage.isEmpty, footer)
        let original = app.buttons["mihbara-reader-original-pdf"]
        XCTAssertTrue(original.waitForExistence(timeout: 5), app.debugDescription); original.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-close"].waitForExistence(timeout: 20), app.debugDescription)
        let samePage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts.allElementsBoundByIndex.contains { plain($0.label).contains("صفحة الملف \(shownPage) من ١٦٣") }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [samePage], timeout: 10), .completed, "Original must open on page \(shownPage)")
        shot(app, "PDF-original-L")
        app.buttons["mihbara-pdf-close"].tap()
        // «الأصل» replaces the EPUB route; closing it returns to the shelf.
        let wantShelf = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 10)); wantShelf.tap()
        let savedBook = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(savedBook.waitForExistence(timeout: 10)); savedBook.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20))
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in footerPage() == 94 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 15), .completed, "Reopening preserves page 94 reached by reading")
        page("PDF-browse-resumed94-L")
        app.swipeLeft(); page("PDF-browse-back-from94-L")
    }
}
