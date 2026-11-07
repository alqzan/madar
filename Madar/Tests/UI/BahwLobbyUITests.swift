import XCTest

/// M4-V01 · bahw/02-W1-Bahw: the lobby shows built rooms only, arranges through settings, and opens a room directly.
@MainActor final class BahwLobbyUITests: XCTestCase {
    func testLobbyBuiltBlocksArrangeAndOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_NOW": "2026-10-09T16:20:00+03:00",
                                 "MADAR_UI_TRACKING_START": "2026-10-01", "MADAR_UI_PRAYER_FIXTURE": "homeShowcaseFriday",
                                 "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_DIARY_FIXTURE": "home", "MADAR_UI_HABIT_FIXTURE": "showcase",
                                 "MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_THEME": "light"]
        app.launch(); finishOnboarding(app)
        app.buttons["tab-foundation"].tap()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(element("bahw-greeting").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(element("bahw-greeting").label, "مساء الخير")
        XCTAssertFalse(element("bahw-date").label.contains("·"))
        for block in ["habits", "salah", "quran", "mal", "year", "upcoming"] { XCTAssertTrue(element("bahw-block-" + block).exists, block) }
        // Every shipped room, including Mihbara from M6, has a lobby destination.
        let nextPrayer = element("bahw-salah-next")
        XCTAssertTrue(nextPrayer.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(nextPrayer.label.contains("المغرب"), nextPrayer.label)
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

        element("bahw-block-salah").press(forDuration: 0.7)
        let hide = app.buttons["bahw-hide-year"]; XCTAssertTrue(hide.waitForExistence(timeout: 5)); hide.tap()
        XCTAssertTrue(element("bahw-block-year").waitForNonExistence(timeout: 5))
        app.swipeUp(); app.buttons["bahw-drawer"].tap()
        let show = app.buttons["bahw-show-year"]; XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        XCTAssertTrue(element("bahw-block-year").waitForExistence(timeout: 5))
        app.swipeDown(); app.buttons["bahw-arrange"].tap()

        element("bahw-block-salah").tap()
        XCTAssertTrue(element("prayer-today-header").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["bahw-open-prayer"].exists)
        capture(app, "UX-02-direct-prayer-L")
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
    func testNextFajrAfterIsha() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T22:00:00+03:00"]
        app.launch(); finishOnboarding(app)
        let next = app.descendants(matching: .any).matching(identifier: "bahw-salah-next").firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(next.label.contains("الفجر"), next.label)
        XCTAssertTrue(next.label.contains("بعد"), next.label)
        capture(app, "UX-03-next-fajr-L")
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
        let prayer = app.descendants(matching: .any).matching(identifier: "bahw-block-salah").firstMatch
        prayer.press(forDuration: 0.7)
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
        app.buttons["diary-editor-cancel"].tap()
        app.buttons["diary-write"].tap()
        XCTAssertTrue(writer.waitForExistence(timeout: 5))
        XCTAssertEqual(writer.value as? String, "بداية هادئة من البهو")
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
        XCTAssertTrue(app.buttons["diary-write"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["tab-foundation"].tap()
        XCTAssertTrue(app.staticTexts["bahw-greeting"].waitForExistence(timeout: 10))
        capture(app, "UX-10-glass-shortcuts-expanded-L")
        // Owner, 3 Nov 2026: one fixed bar with every enabled room, no «المزيد» and no accessory; «خصّص» opens from the lobby.
        // Since FB-43 the bar is the system's own tab bar, so each room is checked by its tab identifier below.
        for room in ["foundation", "prayer", "quran", "notes", "money", "mihbara"] {
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
        for room in ["prayer", "quran", "notes", "money", "mihbara"] {
            let shortcut = app.buttons["tab-\(room)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "Missing one-tap room shortcut: \(room)\n\(app.debugDescription)")
            XCTAssertTrue(shortcut.isHittable, "Room shortcut is not tappable: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44, "Room target is too narrow: \(room)")
            XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44, "Room target is too short: \(room)")
        }
        for (room, destination) in [
            ("quran", "quran-coverage-title"),
            ("prayer", "prayer-today-header"),
            ("notes", "diary-home-title"),
            ("money", "money-home"),
            ("mihbara", "mihbara-add-paper"),
            ("foundation", "bahw-block-salah")
        ] {
            let shortcut = app.buttons["tab-\(room)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "Missing one-tap room shortcut: \(room)")
            shortcut.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: destination).firstMatch.waitForExistence(timeout: 10), room + app.debugDescription)
        }
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
        let later = app.buttons["first-run-continue"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription); later.tap()
        XCTAssertTrue(later.waitForNonExistence(timeout: 5), app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot(), a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        // xcodebuild can hang after the run and lose attachments; a shot folder keeps them on disk.
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")) }
    }
}
