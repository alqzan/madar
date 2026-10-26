import XCTest

@MainActor final class HabitsUITests:XCTestCase {
    private func app(_ fixture:String)->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_HABIT_FIXTURE":fixture,"MADAR_UI_NOW":"2026-10-15T20:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"];app.launch();return app
    }
    private func open(_ app:XCUIApplication){let block=app.descendants(matching:.any).matching(identifier:"bahw-block-habits").firstMatch;XCTAssertTrue(block.waitForExistence(timeout:20));let header=app.buttons["bahw-habits-open"]; if header.exists { header.tap() } else { block.tap() };XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout:10))}
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testPausedLongerHabitsAreNotClaimedAsCompleted() throws {
        continueAfterFailure = false
        for fixture in ["pausedLater", "pausedLaterMixed"] {
            let app = app(fixture); open(app)
            let later = app.buttons["habits-later"]
            XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
            shot(app, "M4-later-\(fixture)-L")
            XCTAssertEqual(later.label, fixture == "pausedLater" ? "عاداتك الأخرى مجمّدة" : "عادات مكتملة وأخرى مجمّدة")
            later.tap()
            let paused = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "صلة الأرحام،")).firstMatch
            XCTAssertTrue(paused.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(paused.label.contains("مجمّدة"), paused.label)
            shot(app, "M4-later-\(fixture)-all-L")
            app.terminate()
        }
    }
    func testPartialDurationIsNotACompleteDayAndPastSaveNamesItsAmount() throws {
        continueAfterFailure = false
        let app = app("partialDuration"); open(app)
        app.buttons["habits-view-all"].tap()
        let band = app.descendants(matching: .any)["habits-band-daily"]
        XCTAssertTrue(band.waitForExistence(timeout: 5)); XCTAssertEqual(band.label, "أسبوعك خطوات صغيرة؛ يكفي أن تبدأ")
        shot(app, "Final-habits-partial-L")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "قراءة هادئة،")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.press(forDuration: 1)
        app.buttons["فعلتها في يوم سابق"].tap()
        let save = app.buttons["habit-past-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.label.contains("١٥"), save.label)
        XCTAssertTrue(save.label.contains("دقيقة"), save.label); shot(app, "Final-habits-past-amount-L")
        save.tap(); XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(band.waitForExistence(timeout: 5)); XCTAssertEqual(band.label, "أسبوعك خطوات صغيرة؛ يكفي أن تبدأ")
        shot(app, "Final-habits-past-saved-L")
    }
    func testEmptyAddCompleteFreezeRestoreAndRelaunch() throws {
        continueAfterFailure=false;let app=app("empty");open(app)
        XCTAssertTrue(app.buttons["habit-first"].exists);shot(app,"M4-V02-empty-L");app.buttons["habit-first"].tap()
        let name=app.textFields["habit-name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("أذكار هادئة");shot(app,"M4-V02-editor-L");app.buttons["habit-save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout:10))
        func row()->XCUIElement{app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","habit-row-")).firstMatch}
        XCTAssertTrue(row().waitForExistence(timeout:10))
        // One tap from the room, as from the lobby: the row's own button completes a once-a-day habit and then leaves.
        let quick=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","habit-quick-")).firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout:5),app.debugDescription);shot(app,"GD-habits-quick-L");quick.tap();XCTAssertTrue(quick.waitForNonExistence(timeout:5))
        row().tap();XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["habit-progress"].label.contains("١ من ١"));app.buttons["habit-freeze"].tap();app.buttons["حتى أفكّه"].tap();XCTAssertTrue(app.buttons["habit-freeze"].waitForNonExistence(timeout:5))
        row().tap();XCTAssertTrue(app.buttons["habit-resume"].waitForExistence(timeout:5));shot(app,"M4-V02-frozen-L");app.buttons["habit-resume"].tap();XCTAssertTrue(app.buttons["habit-resume"].waitForNonExistence(timeout:5))
        row().tap();app.buttons["habit-delete"].tap();XCTAssertTrue(app.buttons["habit-first"].waitForExistence(timeout:5));app.buttons["habit-archived"].tap();app.buttons["استعدها"].tap();XCTAssertTrue(row().waitForExistence(timeout:5))
        app.terminate();app.launch();open(app);XCTAssertTrue(row().waitForExistence(timeout:10));shot(app,"M4-V02-accessory-after-L");XCTAssertTrue(row().isHittable)
        let accessory=app.descendants(matching:.any).matching(identifier:"tab-accessory-next-prayer").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout:10))
        XCTAssertLessThanOrEqual(row().frame.maxY,accessory.frame.minY,"The first habit row should finish above the floating room accessory.")
        row().tap();XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["habit-progress"].label.contains("١ من ١"))
        app.buttons["تمّ"].tap();row().tap();app.buttons["habit-delete"].tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForExistence(timeout:5));app.buttons["habit-archived"].tap()
        let finalDelete=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","حذف نهائي")).firstMatch
        XCTAssertTrue(finalDelete.waitForExistence(timeout:5));finalDelete.tap();app.buttons["احذف نهائيًا"].tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForNonExistence(timeout:5))
        let undo=app.buttons["تراجع"];XCTAssertTrue(undo.waitForExistence(timeout:5));undo.tap()
        XCTAssertTrue(app.buttons["habit-archived"].waitForExistence(timeout:5));if !app.buttons["استعدها"].exists {app.buttons["habit-archived"].tap()};app.buttons["استعدها"].tap()
        XCTAssertTrue(row().waitForExistence(timeout:5))
    }
    func testTodayStepAndAllHabitsLists() throws {
        continueAfterFailure=false;let app=app("showcase");open(app);shot(app,"M4-V02-Adat-L")
        // Owner 24 Oct «خطوة اليوم»: «اليوم» holds what is due now; the yearly habit waits in «كل عاداتي».
        let today=app.buttons["habits-view-today"],all=app.buttons["habits-view-all"]
        XCTAssertTrue(today.waitForExistence(timeout:5),app.debugDescription);XCTAssertTrue(today.isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","الماء،")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","العمرة")).firstMatch.exists)
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","الماء،")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));shot(app,"M4-V02-detail-L");app.buttons["تمّ"].tap()
        all.tap();XCTAssertTrue(all.isSelected)
        for habit in ["الماء،","الاتصال بالأخوال","صدقة الشهر","العمرة"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",habit)).firstMatch.waitForExistence(timeout:5),habit)
        }
        for kind in ["daily","weekly","monthly","yearly"] { XCTAssertTrue(app.descendants(matching:.any)["habits-group-"+kind].exists,kind) }
        shot(app,"M4-V02-Adat-all-L");app.swipeUp(velocity:.slow);shot(app,"M4-V02-Adat-all-s1-L")
        XCTAssertFalse(app.segmentedControls["عرض العادات"].exists) // RA8: alternate designs are v2; this is a filter.
    }
    /// Item 26 «ب مع ج»: each rhythm draws itself in «كل عاداتي»; a yearly habit opens on «منذ آخر مرة» with both dates and
    /// its diary line, and «فعلتها في يوم سابق» logs a past day linked to that day's line.
    func testRhythmBandsSinceLastTimeAndPastDay() throws {
        continueAfterFailure=false;let app=app("since");open(app)
        app.buttons["habits-view-all"].tap()
        for kind in ["daily","weekly","monthly","yearly"] {
            let band=app.descendants(matching:.any)["habits-band-"+kind]
            for _ in 0..<4 where !band.exists { app.swipeUp(velocity:.slow) }
            XCTAssertTrue(band.waitForExistence(timeout:5),kind)
        }
        XCTAssertTrue(app.descendants(matching:.any)["habits-band-yearly"].label.contains("آخر مرة منذ ٧ أشهر"),app.descendants(matching:.any)["habits-band-yearly"].label)
        app.swipeDown(velocity:.fast);app.swipeDown(velocity:.fast);shot(app,"I26-bands-L");app.swipeUp(velocity:.slow);shot(app,"I26-bands-s1-L")
        let gift=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","إهداء من تحب")).firstMatch
        for _ in 0..<4 where !gift.isHittable { app.swipeUp(velocity:.slow) }
        gift.tap()
        let since=app.staticTexts["habit-since"];XCTAssertTrue(since.waitForExistence(timeout:5));XCTAssertEqual(since.label,"منذ ٧ أشهر")
        XCTAssertTrue(app.staticTexts["أهديت أمي عطرها الذي تحبه، وفرحت به كثيرًا."].exists)
        shot(app,"I26-since-L");app.swipeUp(velocity:.slow);shot(app,"I26-since-s1-L")
        let past=app.buttons["habit-past-day"];for _ in 0..<3 where !past.isHittable { app.swipeUp(velocity:.slow) }
        past.tap()
        XCTAssertTrue(app.buttons["habit-past-save"].waitForExistence(timeout:5));shot(app,"I26-past-day-L")
        // Three days ago holds one diary line; pick that day, link the line, save.
        let day=app.datePickers["habit-past-date"].buttons.matching(NSPredicate(format:"label CONTAINS %@","12")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout:5),app.debugDescription);day.tap()
        let line=app.buttons["habit-past-line"];XCTAssertTrue(line.waitForExistence(timeout:5));line.tap();XCTAssertTrue(line.isSelected)
        shot(app,"I26-past-day-line-L");app.buttons["habit-past-save"].tap()
        XCTAssertTrue(app.buttons["habit-past-save"].waitForNonExistence(timeout:10))
        let again=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","إهداء من تحب")).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout:10));again.tap()
        XCTAssertTrue(since.waitForExistence(timeout:5));XCTAssertEqual(since.label,"منذ ٣ أيام")
        XCTAssertTrue(app.staticTexts["مشيت مع أخي بعد العصر."].exists);shot(app,"I26-since-after-L")
        // A forgotten day is a long-press away from the room's row.
        app.buttons["تمّ"].tap()
        let water=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","الماء،")).firstMatch
        for _ in 0..<6 where !water.isHittable { app.swipeDown(velocity:.slow) }
        water.press(forDuration:1.0)
        let menu=app.buttons["فعلتها في يوم سابق"];XCTAssertTrue(menu.waitForExistence(timeout:5),app.debugDescription);menu.tap()
        XCTAssertTrue(app.buttons["habit-past-save"].waitForExistence(timeout:5));app.buttons["إلغاء"].tap()
        XCTAssertTrue(app.buttons["habit-past-save"].waitForNonExistence(timeout:5))
    }
    func testOverdueYearlyHabitShowsTheGentleNudge() throws {
        continueAfterFailure = false
        let app = app("sinceOverdue"); open(app)
        app.buttons["habits-view-all"].tap()
        let gift = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إهداء من تحب")).firstMatch
        for _ in 0..<8 where !gift.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(gift.isHittable); gift.tap()
        let since = app.staticTexts["habit-since"]
        XCTAssertTrue(since.waitForExistence(timeout: 10)); XCTAssertEqual(since.label, "منذ سنة")
        XCTAssertTrue(app.staticTexts["مرّت سنة ولم تفعلها؛ لعلّ هذا وقتها"].exists)
        XCTAssertTrue(app.staticTexts["أهديت أمي عطرها الذي تحبه، وفرحت به كثيرًا."].exists)
        shot(app, "I26-year-overdue-L")
    }
}
