import XCTest
import UIKit

@MainActor final class HabitsUITests:XCTestCase {
    private func app(_ fixture:String, appearance:String = "light", now:String = "2026-10-15T20:00:00+03:00", firstCalendar: String? = nil)->XCUIApplication {
        let app=XCUIApplication();var environment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_HABIT_FIXTURE":fixture,"MADAR_UI_NOW":now,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":appearance]
        if let firstCalendar { environment["MADAR_UI_FIRST_CALENDAR"] = firstCalendar }
        app.launchEnvironment=environment;app.launch();return app
    }
    private func open(_ app:XCUIApplication){let block=app.descendants(matching:.any).matching(identifier:"bahw-block-habits").firstMatch;XCTAssertTrue(block.waitForExistence(timeout:20));let header=app.buttons["bahw-habits-open"]; if header.exists { header.tap() } else { block.tap() };XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout:10))}
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testAutomaticThemeUsesResolvedAppearanceInLobbyAndHabitSheets() throws {
        continueAfterFailure = false
        // Fixture leaves core.theme at its schema default, auto. Only the root's resolved scheme is forced.
        for appearance in ["dark", "light"] {
            let app = app("showcase", appearance: appearance)
            XCTAssertTrue(app.descendants(matching: .any)["bahw-greeting"].waitForExistence(timeout: 15))
            shot(app, "M4-auto-\(appearance)-lobby-L"); try assertPaper(app, dark: appearance == "dark")
            open(app)
            shot(app, "M4-auto-\(appearance)-habits-L"); try assertPaper(app, dark: appearance == "dark")
            let water = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "الماء،")).firstMatch
            XCTAssertTrue(water.waitForExistence(timeout: 5)); water.tap()
            XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-detail-L"); try assertPaper(app, dark: appearance == "dark")
            let past = app.buttons["habit-past-day"]
            for _ in 0..<6 where !past.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(past.isHittable); past.tap()
            XCTAssertTrue(app.buttons["habit-past-save"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-past-L"); try assertPaper(app, dark: appearance == "dark")
            app.buttons["إلغاء"].tap(); app.buttons["تمّ"].tap()
            let add = app.buttons["habit-add"]; XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
            XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-editor-L"); try assertPaper(app, dark: appearance == "dark")
            app.terminate()
        }
    }
    func testAutomaticThemeUsesResolvedAppearanceInYearAndWidgetPreviews() throws {
        continueAfterFailure = false
        for appearance in ["dark", "light"] {
            let app = app("showcase", appearance: appearance)
            let year = app.descendants(matching: .any)["bahw-block-year"]
            XCTAssertTrue(year.waitForExistence(timeout: 15))
            for _ in 0..<6 where !year.isHittable { app.swipeUp(velocity: .slow) }
            year.tap()
            XCTAssertTrue(app.descendants(matching: .any)["bahw-year-hero"].waitForExistence(timeout: 10))
            shot(app, "M4-auto-\(appearance)-year-L"); try assertPaper(app, dark: appearance == "dark")
            let add = app.buttons["bahw-add-day"]
            for _ in 0..<8 where !add.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(add.isHittable); add.tap()
            XCTAssertTrue(app.textFields["bahw-day-title"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-day-L"); try assertPaper(app, dark: appearance == "dark")
            app.buttons["إلغاء"].tap(); app.buttons["bahw-year-back"].tap()
            app.buttons["tab-customize"].tap()
            let search = app.textFields["settings-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("ودجات")
            let gallery = app.buttons["room-widgets-gallery"]
            XCTAssertTrue(gallery.waitForExistence(timeout: 5)); gallery.tap()
            XCTAssertTrue(app.staticTexts["room-widgets-title"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-widgets-L"); try assertPaper(app, dark: appearance == "dark")
            app.buttons["room-widgets-lock"].tap()
            XCTAssertTrue(app.staticTexts["lock-widgets-title"].waitForExistence(timeout: 5))
            shot(app, "M4-auto-\(appearance)-lock-widgets-L"); try assertPaper(app, dark: appearance == "dark")
            app.terminate()
        }
    }
    private func assertPaper(_ app:XCUIApplication, dark:Bool, file:StaticString = #filePath, line:UInt = #line) throws {
        let image = try XCTUnwrap(app.screenshot().image.cgImage, file:file, line:line)
        let scale = CGFloat(image.width) / app.frame.width
        let pixel = try XCTUnwrap(image.cropping(to:CGRect(x:5*scale,y:150*scale,width:1,height:1)), file:file, line:line)
        var rgba = [UInt8](repeating:0,count:4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
                                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
        }
        let brightness = (Int(rgba[0])+Int(rgba[1])+Int(rgba[2]))/3
        XCTAssertTrue(dark ? brightness < 100 : brightness > 160,"Resolved appearance paper brightness: \(brightness)",file:file,line:line)
    }
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
    func testSameDayTripFreezesHomeOnlyHabit() throws {
        continueAfterFailure = false
        let app = app("sameDayTrip"); open(app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "عادة البيت،")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "M4-same-day-trip-home-only-L")
        XCTAssertTrue(row.label.contains("مجمّدة"), row.label)
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
    func testScheduledMonthlyAndYearlyHabitsAppearOnTheirDates() {
        continueAfterFailure = false
        let app = app("scheduledToday"); open(app)
        let monthly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "صدقة شهرية محددة")).firstMatch
        let yearly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "موعد سنوي محدد")).firstMatch
        shot(app, "M4-V02-scheduled-due-after-L")
        XCTAssertTrue(monthly.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(yearly.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "هدف شهري مرن")).firstMatch.exists, app.debugDescription)
    }
    func testFixedMonthlyAndYearlyHabitsStayHiddenBeforeTheirDates() {
        continueAfterFailure = false
        let app = app("scheduledEarly", now: "2026-12-25T20:00:00+03:00"); open(app)
        shot(app, "M4-V02-scheduled-early-L")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "صدقة شهرية محددة")).firstMatch.exists, app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "موعد سنوي محدد")).firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "هدف شهري مرن")).firstMatch.exists, app.debugDescription)
    }
    func testAtRiskFixedHabitsStayHiddenBeforeTheirDates() {
        continueAfterFailure = false
        let app = app("scheduledRisk", now: "2026-12-25T20:00:00+03:00"); open(app)
        let monthly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "صدقة شهرية محددة")).firstMatch
        let yearly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "موعد سنوي محدد")).firstMatch
        shot(app, "M4-V02-scheduled-risk-early-L")
        XCTAssertFalse(monthly.exists, app.debugDescription)
        XCTAssertFalse(yearly.exists, app.debugDescription)
        app.buttons["habits-view-all"].tap()
        XCTAssertTrue(monthly.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(yearly.waitForExistence(timeout: 5), app.debugDescription)
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
    func testSinceTimelineYearLabelsShowBothCalendarsInPreferenceOrder() throws {
        continueAfterFailure = false
        for (calendar, firstMarker) in [("hijri", "هـ"), ("gregorian", "م")] {
            let app = app("since", firstCalendar: calendar); open(app)
            app.buttons["habits-view-all"].tap()
            let gift = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إهداء من تحب")).firstMatch
            for _ in 0..<8 where !gift.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(gift.isHittable, app.debugDescription); gift.tap()
            let hijri = app.staticTexts["١٤٤٦ هـ – ١٤٤٧ هـ"]
            let gregorian = app.staticTexts["٢٠٢٥ م"]
            XCTAssertTrue(hijri.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(gregorian.exists, app.debugDescription)
            if firstMarker == "هـ" { XCTAssertLessThan(hijri.frame.minY, gregorian.frame.minY) }
            else { XCTAssertLessThan(gregorian.frame.minY, hijri.frame.minY) }
            shot(app, "I26-since-years-\(calendar)-L")
            app.terminate()
        }
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
