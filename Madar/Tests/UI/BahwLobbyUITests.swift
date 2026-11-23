import XCTest

/// M4-V01 · bahw/02-W1-Bahw: the lobby shows built rooms only, arranges through settings, and opens a room directly.
@MainActor final class BahwLobbyUITests: XCTestCase {
    func testLobbyBuiltBlocksArrangeAndOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00",
                                 "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_HABIT_FIXTURE": "showcase",
                                 "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        app.buttons["tab-foundation"].tap()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(element("bahw-greeting").label, "مساء الخير")
        XCTAssertFalse(element("bahw-date").label.contains("·"))
        for block in ["habits", "quran", "mal", "year", "upcoming"] { XCTAssertTrue(element("bahw-block-" + block).exists, block) }
        // Owner 17 Nov 2026: the prayer room is gone, so the lobby has no prayer block.
        XCTAssertFalse(element("bahw-block-salah").exists)
        capture(app, "M4-V01-lobby-L")
        app.buttons["bahw-arrange-start"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["bahw-arrange"].tap()
        // The arrange bar animates away over the header; tap customize only once it is gone.
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5), app.debugDescription)
        let customize = app.buttons["bahw-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5) && customize.isHittable, app.debugDescription); customize.tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 10), app.debugDescription)
        app.swipeUp(); XCTAssertTrue(element("bahw-block-notes").waitForExistence(timeout: 5)); XCTAssertTrue(element("bahw-block-mihbara").exists); capture(app, "M4-V01-lobby-s1-L")
        app.swipeDown()

        element("bahw-block-habits").press(forDuration: 0.7)
        let hide = app.buttons["bahw-hide-year"]; XCTAssertTrue(hide.waitForExistence(timeout: 5)); hide.tap()
        XCTAssertTrue(element("bahw-block-year").waitForNonExistence(timeout: 5))
        app.swipeUp(); app.buttons["bahw-drawer"].tap()
        let show = app.buttons["bahw-show-year"]; XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        XCTAssertTrue(element("bahw-block-year").waitForExistence(timeout: 5))
        app.swipeDown(); app.buttons["bahw-arrange"].tap()

        // The habits block's rings log on tap (testHabitIconFitsAndOpensItsRoom covers opening it); Quran opens directly.
        element("bahw-block-quran").tap()
        XCTAssertTrue(element("quran-coverage-title").waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "UX-02-direct-quran-L")
    }

    func testThreeDayReturnPlanPersistsLocallyAndOpensItsRooms() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": "bahw-return-\(UUID().uuidString)",
            "MADAR_UI_RETURN_PLAN": "1",
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_NOW": "2026-10-26T15:00:00+03:00",
            "MADAR_UI_THEME": "light"
        ]
        app.launch()
        finishOnboarding(app)
        app.buttons["tab-foundation"].tap()

        let card = app.descendants(matching: .any)["bahw-return-plan"]
        let day = app.staticTexts["bahw-return-day"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(day.label, "اليوم \u{2068}١\u{2069} من \u{2068}٣\u{2069}")
        XCTAssertEqual(app.staticTexts["bahw-return-plan-copy"].label, "نصف وردك، وعادة واحدة تكفي اليوم.")
        capture(app, "M4-V01-return-day1-L")

        app.buttons["bahw-return-quran"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["bahw-return-habits"].tap()
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10), app.debugDescription)

        app.terminate()
        app.launch()
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(day.label, "اليوم \u{2068}١\u{2069} من \u{2068}٣\u{2069}")
        capture(app, "M4-V01-return-day1-reopened-L")
    }

    func testMihbaraLobbyBlockOpensItsRoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_MIHBARA_FIXTURE": "empty", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let lobby = app.buttons["tab-foundation"]
        XCTAssertTrue(lobby.waitForExistence(timeout: 15), app.debugDescription); lobby.tap()
        let mihbara = app.descendants(matching: .any).matching(identifier: "bahw-block-mihbara").firstMatch
        var attempts = 0
        while attempts < 5 && !mihbara.exists { app.swipeUp(velocity: .slow); attempts += 1 }
        XCTAssertTrue(mihbara.waitForExistence(timeout: 8), app.debugDescription)
        mihbara.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testMoneySuggestionOpensBankMessages() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        app.buttons["tab-customize"].tap()
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        search.tap(); search.typeText("bahw.smartPresence\n")
        let present = app.buttons["option-bahw.smartPresence-present"]
        XCTAssertTrue(present.waitForExistence(timeout: 10), app.debugDescription); present.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: present)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, app.debugDescription)
        app.buttons["tab-foundation"].tap()
        // Owner, 4 Nov 2026: unsorted bank messages also raise «شيء ينتظرك» on open; «لاحقًا» leaves them to the lobby suggestion.
        let later = app.buttons["bahw-attention-primary"]
        if later.waitForExistence(timeout: 4) { later.tap(); XCTAssertTrue(later.waitForNonExistence(timeout: 5), app.debugDescription) }
        let suggestion = app.buttons["bahw-suggestion-money"]
        for _ in 0..<8 where !suggestion.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(suggestion.isHittable, app.debugDescription); suggestion.tap()
        // The suggestion raises «شيء ينتظرك», where «افرزها» opens the bank messages.
        let sort = app.buttons["bahw-attention-money"]
        XCTAssertTrue(sort.waitForExistence(timeout: 8), app.debugDescription); sort.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 15), app.debugDescription)
    }
    func testHabitWideAndSmallBlocksShowAtRisk() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "atRisk", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let habits = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        XCTAssertTrue(habits.waitForExistence(timeout: 15))
        habits.press(forDuration: 0.7)
        app.buttons["bahw-size-habits"].tap(); app.buttons["كبيرة"].tap(); app.buttons["bahw-arrange"].tap()
        // The large block names the next habit under its grid, with the wide block's wording.
        let largeNext = app.buttons["bahw-habits-next"]
        XCTAssertTrue(largeNext.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(largeNext.label.contains("التالي: الماء"), largeNext.label)
        let dailyRings = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bahw-habit-ring-"))
        XCTAssertEqual(dailyRings.count, 3, app.debugDescription)
        let waterRing = dailyRings.matching(NSPredicate(format: "label CONTAINS %@", "الماء")).firstMatch
        XCTAssertTrue(waterRing.exists, app.debugDescription)
        XCTAssertTrue(waterRing.label.contains("أكواب"), waterRing.label)
        capture(app, "M4-V01-habit-large-rings-L")
        // The period rings choose which habits the grid shows; one opens selected.
        let rings = ["daily", "weekly", "monthly", "yearly"].map { app.buttons["bahw-habits-period-" + $0] }
        XCTAssertEqual(rings.filter(\.isSelected).count, 1, app.debugDescription)
        if let other = rings.first(where: { $0.isEnabled && !$0.isSelected }) {
            other.tap()
            let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: other)
            XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 5), .completed, app.debugDescription)
            let weeklyRings = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bahw-habit-ring-"))
            XCTAssertEqual(weeklyRings.count, 2, app.debugDescription)
            capture(app, "M4-V01-habit-large-period-rings-L")
        }
        habits.press(forDuration: 0.7)
        let size = app.buttons["bahw-size-habits"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.tap()
        let wide = app.buttons["عريضة"]
        XCTAssertTrue(wide.waitForExistence(timeout: 5))
        wide.tap()
        app.buttons["bahw-arrange"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        let next = app.staticTexts["bahw-habits-wide-step"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(next.label.contains("الماء"), next.label)
        // The same habit is named once (tour 25 Oct): its miss joins its step.
        XCTAssertTrue(next.label.contains("فاتك يوم، "), next.label); XCTAssertFalse(next.label.contains("في الماء"), next.label)
        capture(app, "M4-V01-habit-wide-after-L")

        habits.press(forDuration: 0.7)
        size.tap()
        let small = app.buttons["صغيرة"]
        XCTAssertTrue(small.waitForExistence(timeout: 5))
        small.tap()
        app.buttons["bahw-arrange"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        let risk = app.staticTexts["bahw-habits-at-risk"]
        XCTAssertTrue(risk.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(risk.label, "فاتك يوم")
        capture(app, "M4-V01-habit-small-after-L")
    }

    func testHabitIconFitsAndOpensItsRoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_HABIT_FIXTURE": "atRisk", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let block = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 15))
        block.press(forDuration: 0.7)
        let size = app.buttons["bahw-size-habits"]
        XCTAssertTrue(size.waitForExistence(timeout: 5)); size.tap()
        let icon = app.buttons["أيقونة"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5)); icon.tap()
        app.buttons["bahw-arrange"].tap()
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        capture(app, "DA-05-habits-icon-L")
        XCTAssertEqual(block.frame.height, block.frame.width, accuracy: 1, "The icon must stay inside its square grid cell")
        let title = block.staticTexts["عاداتك"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThanOrEqual(title.frame.minY, block.frame.minY)
        XCTAssertLessThanOrEqual(title.frame.maxY, block.frame.maxY)
        let count = block.staticTexts["bahw-habits-icon-count"]
        XCTAssertTrue(count.exists)
        XCTAssertEqual(count.label, "٠ من ٣ اليوم")
        XCTAssertGreaterThanOrEqual(count.frame.minY, block.frame.minY)
        XCTAssertLessThanOrEqual(count.frame.maxY, block.frame.maxY)
        block.tap()
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10))
    }

    func testSixHabitRingsStayTappableAndPeriodChoiceKeepsProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_HABIT_FIXTURE": "lobbySix", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let block = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 15))
        // The owner chose W1's wide default; customized sizes must survive relaunch.
        XCTAssertGreaterThan(block.frame.width / block.frame.height, 1.8)
        let rings = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bahw-habit-ring-"))
        XCTAssertTrue(rings.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(rings.count, 6, app.debugDescription)
        let frames = rings.allElementsBoundByIndex.map(\.frame)
        XCTAssertLessThan((frames.map(\.midY).max() ?? 0) - (frames.map(\.midY).min() ?? 0), 2)
        for ring in rings.allElementsBoundByIndex {
            XCTAssertTrue(ring.isHittable, ring.label)
            XCTAssertGreaterThanOrEqual(ring.frame.width, 44, ring.label)
            XCTAssertGreaterThanOrEqual(ring.frame.height, 44, ring.label)
        }
        capture(app, "OR-01-six-habits-L")

        let water = rings.matching(NSPredicate(format: "label CONTAINS %@", "الماء")).firstMatch
        water.tap()
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "١"), object: water)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 10), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["habits-title"].exists, "A habit tap must record in the lobby.")
        block.press(forDuration: 0.7)
        let sizeButton = app.buttons["bahw-size-habits"]; XCTAssertTrue(sizeButton.waitForExistence(timeout: 5)); sizeButton.tap()
        let large = app.buttons["كبيرة"]
        if !large.waitForExistence(timeout: 3) { sizeButton.tap() }
        XCTAssertTrue(large.waitForExistence(timeout: 5), app.debugDescription); large.tap(); app.buttons["bahw-arrange"].tap()
        // Period choices stay disabled while arranging: tap only once arrange mode has really ended (checklist row 20).
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForNonExistence(timeout: 5))
        let yearly = app.buttons["bahw-habits-period-yearly"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND hittable == true"), object: yearly)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        // The period change animates: wait for the ring count instead of reading it mid-transition.
        func waitForRings(_ count: Int) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: rings)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, "rings \(rings.count) ≠ \(count)\n\(app.debugDescription)")
        }
        app.buttons["bahw-habits-period-yearly"].tap()
        waitForRings(1)
        app.buttons["bahw-habits-period-daily"].tap()
        waitForRings(6)
        XCTAssertTrue(water.label.contains("١"), water.label)
        // Let the selected-period transition settle before the visual evidence is captured.
        Thread.sleep(forTimeInterval: 0.7)
        capture(app, "OR-01-six-habits-recorded-L")
        app.terminate(); app.launch()
        XCTAssertTrue(block.waitForExistence(timeout: 15))
        XCTAssertLessThan(block.frame.width / block.frame.height, 1.2, "Keep the owner's saved large size.")
    }
    func testYearSummaryAvoidsDuplicateSeasonsAndDate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let year = app.descendants(matching: .any).matching(identifier: "bahw-block-year").firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 15))
        let text = year.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        for duplicate in ["رمضان", "العيد", "عرفة", "أكتوبر", "ربيع"] { XCTAssertFalse(text.contains(duplicate), text) }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-hijri").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bahw-year-gregorian").firstMatch.exists)
        capture(app, "UX-04-year-strips-L")
    }
    func testGreetingScrollsAndEditingControlsStayContextual() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let greeting = app.staticTexts["bahw-greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["bahw-arrange-start"].isHittable)
        XCTAssertTrue(app.buttons["bahw-customize"].isHittable)
        capture(app, "UX-14-lobby-L")
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
        XCTAssertFalse(greeting.isHittable)
        capture(app, "UX-14-lobby-s1-L")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        let habits = app.descendants(matching: .any).matching(identifier: "bahw-block-habits").firstMatch
        habits.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["bahw-arrange"].waitForExistence(timeout: 5))
        app.buttons["bahw-arrange"].tap()
        XCTAssertFalse(app.buttons["bahw-arrange"].exists)
        app.buttons["tab-customize"].tap()
        XCTAssertTrue(app.textFields["settings-search"].waitForExistence(timeout: 10))
    }
    func testUpcomingShowsGregorianDatesAndComparableRings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00"]
        app.launch(); finishOnboarding(app)
        let upcoming = app.descendants(matching: .any).matching(identifier: "bahw-block-upcoming").firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 15))
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(upcoming.isHittable)
        let dates = upcoming.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(dates.contains("فبراير"), dates)
        // Both dates always (owner, 15 Oct): the Hijri date sits beside the Gregorian one.
        capture(app, "UX-06-upcoming-L")
    }
    /// FB-45 (§7.1 automatic sources): the salary from Money and the season of the white days sit among the rings.
    func testUpcomingReadsSalaryAndWhiteDays() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
                                 "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch(); finishOnboarding(app)
        app.buttons["tab-foundation"].tap()
        let upcoming = app.descendants(matching: .any).matching(identifier: "bahw-block-upcoming").firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 15))
        app.swipeUp(velocity: .slow)
        let items = app.descendants(matching: .any).matching(identifier: "bahw-upcoming-item").allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(items.contains { $0.hasPrefix("الراتب") }, items.joined(separator: " | "))
        XCTAssertTrue(items.contains { $0.hasPrefix("الأيام البيض") }, items.joined(separator: " | "))
        capture(app, "FB45-upcoming-after-L")
    }
    func testEmptyDiaryOpensWriterAndKeepsDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let notes = app.descendants(matching: .any).matching(identifier: "bahw-block-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["bahw-notes-count"].label.contains("اكتب سطر اليوم"))
        capture(app, "UX-07-invitation-L")
        notes.tap()
        let writer = app.textViews["diary-editor-text"]
        XCTAssertTrue(writer.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        writer.typeText("بداية هادئة من البهو")
        capture(app, "UX-07-writer-L")
        // 14 Nov owner (T10): no cancel for new words; «تمّ» makes the draft today's line.
        XCTAssertFalse(app.buttons["diary-editor-cancel"].exists)
        app.buttons["diary-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["بداية هادئة من البهو"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testNativeMinimizedBarAndVisibleTabsSwitchOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_DIARY_FIXTURE": "empty",
            "MADAR_UI_TRAVEL_FIX": "24.7136,46.6753,الرياض,SA,Asia/Riyadh",
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light"
        ]
        app.launch()
        XCTAssertTrue(app.diaryOpener.waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(app.staticTexts["bahw-greeting"].waitForExistence(timeout: 10))
        capture(app, "UX-10-glass-shortcuts-expanded-L")
        // Owner, 3 Nov 2026: one fixed bar with every enabled room, no «المزيد» and no accessory; «خصّص» opens from the lobby.
        // Since FB-43 the bar is the system's own tab bar, so each room is checked by its tab identifier below.
        for room in ["foundation", "quran", "notes", "money", "mihbara"] {
            let shortcut = app.buttons["tab-\(room)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "Missing room tab: \(room)\n\(app.debugDescription)")
            XCTAssertTrue(shortcut.isHittable, "Room tab is not tappable: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44, "Room tab is too narrow: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44, "Room tab is too short: \(room)")
        }
        app.buttons["tab-notes"].tap()
        XCTAssertTrue(app.staticTexts["diary-home-title"].waitForExistence(timeout: 10))
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(app.staticTexts["bahw-greeting"].waitForExistence(timeout: 10))
        app.swipeUp(velocity: .slow)
        capture(app, "UX-10-glass-shortcuts-inline-L")
        for room in ["quran", "notes", "money", "mihbara"] {
            let shortcut = app.buttons["tab-\(room)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "Missing one-tap room shortcut: \(room)\n\(app.debugDescription)")
            XCTAssertTrue(shortcut.isHittable, "Room shortcut is not tappable: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44, "Room target is too narrow: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44, "Room target is too short: \(room)")
        }
        for (room, destination) in [
            ("quran", "quran-coverage-title"),
            ("notes", "diary-home-title"),
            ("money", "money-home"),
            ("mihbara", "mihbara-add-paper"),
            ("foundation", "bahw-greeting")
        ] {
            let shortcut = app.buttons["tab-\(room)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "Missing one-tap room shortcut: \(room)")
            shortcut.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: destination).firstMatch.waitForExistence(timeout: 10), room + app.debugDescription)
        }
    }
    /// Owner 22 Nov 2026 («ابحث في مدار», approved): one search from the lobby finds a habit by name and opens it in its room;
    /// one letter asks for more, and a word that matches nothing says so.
    func testLobbySearchFindsAHabitAndOpensIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_HABIT_FIXTURE": "lobbySix", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        let search = app.buttons["bahw-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertGreaterThanOrEqual(search.frame.width, 44)
        search.tap()
        let field = app.textFields["madar-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        field.tap(); field.typeText("زززز")
        XCTAssertTrue(app.descendants(matching: .any)["madar-search-empty"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["امسح البحث"].tap()
        field.tap(); field.typeText("الماء")
        let hit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "madar-search-hit-habit-")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(hit.label.contains("الماء"), hit.label)
        hit.tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.isHittable, "The search sheet leaves when a result opens.")
        // The habit's own page opens in the habits room (its progress line is unique to that page).
        XCTAssertTrue(app.descendants(matching: .any)["habit-progress"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// Travel stays after the prayer room left (17 Nov plan): away from home the lobby asks once, starts and ends the trip.
    func testTravelQuestionStartsAndEndsATripFromTheLobby() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_HABIT_FIXTURE": "lobbySix", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light",
                                 "MADAR_UI_TRAVEL_FIX": "21.4858,39.1925,جدة,SA,Asia/Riyadh"]
        app.launch(); finishOnboarding(app)
        let pill = app.buttons["bahw-travel-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(pill.label.contains("خارج مدينتك"), pill.label)
        // The store has loaded (the lobby counts the fixture's six habits) before the first sheet is asked for.
        let loaded = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-habits-open", "٦")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 15), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: pill)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        pill.tap()
        let yes = app.buttons["bahw-travel-yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "أنت الآن في جدة")).firstMatch.exists, app.debugDescription)
        capture(app, "OWNER-22nov-travel-question-L")
        yes.tap()
        XCTAssertTrue(yes.waitForNonExistence(timeout: 10), app.debugDescription)
        let onTrip = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-travel-pill", "مسافر في جدة")).firstMatch
        XCTAssertTrue(onTrip.waitForExistence(timeout: 10), app.debugDescription)
        onTrip.tap()
        let end = app.buttons["bahw-trip-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 8), app.debugDescription)
        capture(app, "OWNER-22nov-trip-sheet-L")
        end.tap()
        XCTAssertTrue(end.waitForNonExistence(timeout: 10), app.debugDescription)
        // Ending the trip while still far away counts as «مقيم هنا» for this place: no pill, no repeated question.
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    func testTravelQuestionAnsweredResidentStaysQuietAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L",
                                 "MADAR_UI_HABIT_FIXTURE": "lobbySix", "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_THEME": "light",
                                 "MADAR_UI_TRAVEL_FIX": "21.4858,39.1925,جدة,SA,Asia/Riyadh"]
        app.launch(); finishOnboarding(app)
        let pill = app.buttons["bahw-travel-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), app.debugDescription)
        // The store has loaded (the lobby counts the fixture's six habits) before the first sheet is asked for.
        let loaded = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-habits-open", "٦")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 15), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: pill)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        pill.tap()
        let no = app.buttons["bahw-travel-no"]
        XCTAssertTrue(no.waitForExistence(timeout: 8), app.debugDescription); no.tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["bahw-greeting"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(pill.waitForExistence(timeout: 3), "«لا، أنا مقيم هنا» is remembered for this place.")
    }

    func testTravelContinuesToSameNamedCityInAnotherCountry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "lobbySix", "MADAR_UI_THEME": "light"]
        func launch(fix: String, now: String) {
            app.launchEnvironment = base.merging(["MADAR_UI_TRAVEL_FIX": fix, "MADAR_UI_NOW": now]) { _, value in value }
            app.launch()
        }
        func pill(containing label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-travel-pill", label)).firstMatch
        }
        func open(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(button.waitForExistence(timeout: 20), app.debugDescription, file: file, line: line)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, app.debugDescription, file: file, line: line)
            button.tap()
        }

        launch(fix: "51.5074,-0.1278,لندن,GB,Europe/London", now: "2026-10-15T20:00:00+03:00")
        let loaded = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-habits-open", "٦")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 20), app.debugDescription)
        open(pill(containing: "خارج مدينتك"))
        open(app.buttons["bahw-travel-yes"])
        XCTAssertTrue(pill(containing: "مسافر في لندن").waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()

        launch(fix: "42.9849,-81.2453,لندن,CA,America/Toronto", now: "2026-10-16T20:00:00+03:00")
        let arabic = Locale(identifier: "ar")
        let canada = arabic.localizedString(forRegionCode: "CA") ?? "CA"
        let unitedKingdom = arabic.localizedString(forRegionCode: "GB") ?? "GB"
        let firstStop = "لندن، " + unitedKingdom
        let secondStop = "لندن، " + canada
        open(pill(containing: "وصلت إلى " + secondStop))
        let add = app.buttons["bahw-trip-continue"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(add.label.contains(secondStop), add.label)
        let itinerary = firstStop + " ← " + secondStop
        add.tap()
        open(pill(containing: itinerary))
        let legs = app.staticTexts["bahw-trip-legs"]
        XCTAssertTrue(legs.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(legs.label, itinerary)
        XCTAssertFalse(add.exists, "The new stop is already the active leg.")
    }

    func testManualTravelStartsContinuesAndEndsWithoutUsingTheLocationFix() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_HABIT_FIXTURE": "lobbySix",
            "MADAR_UI_NOW": "2026-10-15T20:00:00+03:00", "MADAR_UI_TRAVEL_FIX": "21.4858,39.1925,جدة,SA,Asia/Riyadh",
        ]
        func pill(containing label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bahw-travel-pill", label)).firstMatch
        }
        func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(element.waitForExistence(timeout: 20), app.debugDescription, file: file, line: line)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, app.debugDescription, file: file, line: line)
            element.tap()
        }
        func selectCity(_ name: String, country: String) {
            let search = app.textFields["bahw-travel-city-search"]
            tap(search)
            search.typeText(name)
            tap(app.buttons["bahw-travel-city-" + name + country])
            XCTAssertEqual(app.staticTexts["bahw-travel-selected-city"].label, name)
        }

        app.launch()
        XCTAssertTrue(pill(containing: "خارج مدينتك").waitForExistence(timeout: 20), app.debugDescription)
        tap(app.buttons["tab-customize"])
        let settingsSearch = app.textFields["settings-search"]
        tap(settingsSearch)
        settingsSearch.typeText("وضع السفر\n")
        let manual = app.buttons["option-core.travelMode-manual"]
        tap(manual)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: manual)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, app.debugDescription)
        tap(app.buttons["tab-foundation"])

        tap(pill(containing: "ابدأ رحلة"))
        capture(app, "BAHW-manual-travel-search-L", window: true)
        selectCity("دبي", country: "AE")
        XCTAssertFalse(app.buttons["bahw-travel-yes"].exists, "Manual travel confirms the selected city instead of asking about the location fix.")
        capture(app, "BAHW-manual-travel-confirm-L", window: true)
        tap(app.buttons["bahw-travel-city-confirm"])
        XCTAssertTrue(pill(containing: "مسافر في دبي").waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()

        app.launchEnvironment["MADAR_UI_NOW"] = "2026-10-16T20:00:00+03:00"
        app.launch()
        tap(pill(containing: "مسافر في دبي"))
        XCTAssertFalse(app.buttons["bahw-trip-continue"].exists, "The conflicting Jeddah fix must not be offered in manual mode.")
        tap(app.buttons["bahw-trip-add-city"])
        selectCity("القاهرة", country: "EG")
        tap(app.buttons["bahw-travel-city-confirm"])
        tap(pill(containing: "دبي ← القاهرة"))
        XCTAssertEqual(app.staticTexts["bahw-trip-legs"].label, "دبي ← القاهرة")
        tap(app.buttons["bahw-trip-end"])
        XCTAssertTrue(pill(containing: "ابدأ رحلة").waitForExistence(timeout: 15), app.debugDescription)
    }

    private func finishOnboarding(_ app: XCUIApplication) {
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        // A store without a fixture reaches the location step: choose a city by hand, then «ليس الآن» for photos.
        let city = app.buttons["first-run-city"]
        guard city.waitForExistence(timeout: 2) else { return }
        city.tap()
        let field = app.textFields["city-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription); field.tap(); field.typeText("الرياض")
        let hit = app.buttons["city-hit-الرياض"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription); hit.tap()
        if field.waitForExistence(timeout: 2) { app.navigationBars.buttons.firstMatch.tap() }
        // Choosing the city finishes first run; there is no photos step any more (B2-12).
        XCTAssertTrue(app.buttons["first-run-city"].waitForNonExistence(timeout: 8), app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String, window: Bool = false) {
        let s = window ? app.windows.firstMatch.screenshot() : app.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        // xcodebuild can hang after the run and lose attachments; a shot folder keeps them on disk.
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")) }
    }
}
