import XCTest
import UIKit

@MainActor final class HabitsUITests:XCTestCase {
    private func app(_ fixture:String, appearance:String = "light", now:String = "2026-10-15T20:00:00+03:00", firstCalendar: String? = nil, habitWriteHoldMS: Int? = nil, rootRouteHarness: Bool = false)->XCUIApplication {
        let app=XCUIApplication();var environment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_HABIT_FIXTURE":fixture,"MADAR_UI_NOW":now,"MADAR_UI_SIZE":"L","MADAR_UI_THEME":appearance]
        if let firstCalendar { environment["MADAR_UI_FIRST_CALENDAR"] = firstCalendar }
        if let habitWriteHoldMS { environment["MADAR_UI_HABIT_WRITE_HOLD_MS"] = String(habitWriteHoldMS) }
        if rootRouteHarness { environment["MADAR_UI_BAHW_ROOT_ROUTE_HARNESS"] = "1" }
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
            let water = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "الماء،")).firstMatch
            XCTAssertTrue(water.waitForExistence(timeout: 5)); for _ in 0..<6 where !water.isHittable || water.frame.maxY > app.frame.maxY - 150 { app.swipeUp(velocity: .slow) }; water.tap()
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
            let weekly = app.staticTexts["habit-orbit-progress-weekly"]
            XCTAssertTrue(weekly.waitForExistence(timeout: 5))
            XCTAssertEqual(weekly.label, "الأسبوع، لا أهداف في هذه الفترة")
            XCTAssertFalse(weekly.label.contains("٪"), "A paused-only period has no completion denominator.")
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
    func testRapidCountHabitTapsDoNotDoubleLogWhileSaving() throws {
        continueAfterFailure = false
        let app = app("partialDuration", habitWriteHoldMS: 1200); open(app)
        app.buttons["habits-view-all"].tap()
        let quick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit-quick-")).firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 5), app.debugDescription)
        quick.tap()
        XCTAssertFalse(quick.isEnabled, "A count/duration completion stays locked until its write finishes.")
        if quick.isHittable { quick.tap() }

        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: quick)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let progress = app.staticTexts["habit-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.label.contains("١٥ من ٣٠"), progress.label)
        app.buttons["تمّ"].tap()

        XCTAssertTrue(quick.isEnabled); quick.tap()
        XCTAssertFalse(quick.isEnabled, "A new intentional tap is accepted after the previous save.")
        let enabledAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: quick)
        XCTAssertEqual(XCTWaiter.wait(for: [enabledAgain], timeout: 10), .completed)
        row.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.label.contains("٣٠ من ٣٠"), progress.label)
    }
    func testRapidLobbyHabitTapsDoNotDoubleLogWhileSaving() throws {
        continueAfterFailure = false
        let app = app("lobbySix", habitWriteHoldMS: 1200)
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bahw-habit-ring-")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(ring.label.contains("الماء"), ring.label)
        for _ in 0..<6 where !ring.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ring.isHittable)

        ring.tap()
        XCTAssertFalse(app.staticTexts["habits-title"].exists, "A quick-log tap should keep the lobby visible; only the header opens the room.")
        XCTAssertFalse(ring.isEnabled, "The lobby disables this habit's other entry points until its write finishes.")
        if ring.isHittable { ring.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        let first = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "١ من ٨"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [first], timeout: 5), .completed, ring.label)

        ring.tap()
        XCTAssertFalse(ring.isEnabled)
        let enabledAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [enabledAgain], timeout: 10), .completed)
        let second = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "٢ من ٨"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [second], timeout: 5), .completed, ring.label)
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
        XCTAssertTrue(app.descendants(matching: .any)["habits-orbit"].exists)
        // The fixture has no events today, two completed weekly goals, and completed monthly/yearly goals.
        for (frequency, expected) in [("daily", "اليوم ٠٪"), ("weekly", "الأسبوع ١٠٠٪"), ("monthly", "الشهر ١٠٠٪"), ("yearly", "السنة ١٠٠٪")] {
            XCTAssertEqual(app.staticTexts["habit-orbit-progress-" + frequency].label, expected)
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label BEGINSWITH %@","habit-row-", "العمرة")).firstMatch.exists)
        let yearlyBead = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-orbit-", "العمرة")).firstMatch
        XCTAssertTrue(yearlyBead.exists); yearlyBead.tap()
        XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout: 5)); app.buttons["تمّ"].tap()
        // The orbit sits above the lists, so rows are scrolled clear of the floating accessory before a tap.
        let accessory=app.descendants(matching:.any).matching(identifier:"tab-accessory-next-prayer").firstMatch
        func reveal(_ e:XCUIElement) {
            for _ in 0..<8 {
                let floor=accessory.exists ? accessory.frame.minY : app.frame.maxY-120
                if e.isHittable && e.frame.minY >= 90 && e.frame.maxY <= floor { return }
                if e.exists && e.frame.minY < 90 { app.swipeDown(velocity:.slow) } else { app.swipeUp(velocity:.slow) }
            }
        }
        let water=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label BEGINSWITH %@","habit-row-","الماء،")).firstMatch
        reveal(water);water.tap()
        XCTAssertTrue(app.staticTexts["habit-progress"].waitForExistence(timeout:5));shot(app,"M4-V02-detail-L");app.buttons["تمّ"].tap()
        reveal(all);all.tap();XCTAssertTrue(all.isSelected)
        for habit in ["الماء،","الاتصال بالأخوال","صدقة الشهر","العمرة"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",habit)).firstMatch.waitForExistence(timeout:5),habit)
        }
        for kind in ["daily","weekly","monthly","yearly"] { XCTAssertTrue(app.descendants(matching:.any)["habits-group-"+kind].exists,kind) }
        shot(app,"M4-V02-Adat-all-L");app.swipeUp(velocity:.slow);shot(app,"M4-V02-Adat-all-s1-L")
        XCTAssertFalse(app.segmentedControls["عرض العادات"].exists) // RA8: alternate designs are v2; this is a filter.
    }
    func testPeriodSummariesOpenTheirGroupsAndReturnToToday() throws {
        continueAfterFailure = false
        let app = app("showcase"); open(app)
        let today = app.buttons["habits-view-today"], all = app.buttons["habits-view-all"]
        XCTAssertTrue(today.isSelected, app.debugDescription)
        for frequency in ["daily", "weekly", "monthly", "yearly"] {
            XCTAssertTrue(app.buttons["habits-period-" + frequency].exists, frequency)
        }
        XCTAssertTrue(app.staticTexts["habits-today-group-daily"].exists, app.debugDescription)
        shot(app, "OR-02-habits-today-L")
        let weekly = app.buttons["habits-period-weekly"]
        weekly.tap()
        XCTAssertTrue(weekly.isSelected, app.debugDescription)
        XCTAssertFalse(all.isSelected, "The whole-list filter is not selected while only one period is shown.")
        XCTAssertTrue(app.descendants(matching: .any)["habits-group-weekly"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["habits-group-daily"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "الاتصال بالأخوال")).firstMatch.exists)
        shot(app, "OR-02-habits-weekly-L")
        all.tap()
        XCTAssertTrue(app.descendants(matching: .any)["habits-group-daily"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["habits-group-weekly"].exists)
        shot(app, "OR-02-habits-all-L")
        app.swipeUp(velocity: .slow); shot(app, "OR-02-habits-all-s1-L")
        app.swipeUp(velocity: .slow); shot(app, "OR-02-habits-all-s2-L")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        XCTAssertTrue(today.waitForExistence(timeout: 5)); today.tap()
        XCTAssertTrue(today.isSelected)
        XCTAssertTrue(app.staticTexts["habits-today-group-daily"].waitForExistence(timeout: 5))
    }
    func testOrbitPercentageUpdatesAfterCompletionAndRelaunch() throws {
        continueAfterFailure = false
        let app = app("showcase"); open(app)
        let daily = app.staticTexts["habit-orbit-progress-daily"]
        XCTAssertEqual(daily.label, "اليوم ٠٪")
        let morning = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-orbit-", "أذكار الصباح")).firstMatch
        XCTAssertTrue(morning.isHittable); morning.tap()
        XCTAssertTrue(app.buttons["habit-complete"].waitForExistence(timeout: 5)); app.buttons["habit-complete"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "اليوم ٣٣٪"), object: daily)], timeout: 10) == .completed)
        shot(app, "OR-02-orbit-one-of-three-L")
        app.terminate(); app.launch(); open(app)
        XCTAssertEqual(daily.label, "اليوم ٣٣٪")
    }
    func testScheduledMonthlyAndYearlyHabitsAppearOnTheirDates() {
        continueAfterFailure = false
        let app = app("scheduledToday"); open(app)
        let monthly = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "صدقة شهرية محددة")).firstMatch
        let yearly = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "موعد سنوي محدد")).firstMatch
        shot(app, "M4-V02-scheduled-due-after-L")
        XCTAssertTrue(monthly.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(yearly.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "هدف شهري مرن")).firstMatch.exists, app.debugDescription)
    }
    func testFixedMonthlyAndYearlyHabitsStayHiddenBeforeTheirDates() {
        continueAfterFailure = false
        let app = app("scheduledEarly", now: "2026-12-25T20:00:00+03:00"); open(app)
        shot(app, "M4-V02-scheduled-early-L")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "صدقة شهرية محددة")).firstMatch.exists, app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "موعد سنوي محدد")).firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "habit-row-", "هدف شهري مرن")).firstMatch.exists, app.debugDescription)
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

    func testSecondHabitDeepLinkUpdatesOpenHabitsRoom() throws {
        continueAfterFailure = false
        let app = app("showcase")
        open(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit-row-"))
        let first = rows.element(boundBy: 0), second = rows.element(boundBy: 1)
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(second.waitForExistence(timeout: 5), app.debugDescription)
        let prefix = "habit-row-"
        let firstID = String(first.identifier.dropFirst(prefix.count))
        let secondID = String(second.identifier.dropFirst(prefix.count))
        let firstName = first.label.components(separatedBy: "،").first ?? first.label
        let secondName = second.label.components(separatedBy: "،").first ?? second.label
        XCTAssertNotEqual(firstName, secondName)

        app.open(URL(string: "madar://bahw/habits/\(firstID)")!)
        XCTAssertTrue(app.staticTexts[firstName].waitForExistence(timeout: 10), app.debugDescription)
        app.open(URL(string: "madar://bahw/habits/\(secondID)")!)
        XCTAssertTrue(app.staticTexts[secondName].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testBahwRoutesReplaceOrCloseAnOpenSubroom() throws {
        continueAfterFailure = false
        let app = app("showcase", rootRouteHarness: true)
        XCTAssertTrue(app.descendants(matching: .any)["bahw-greeting"].waitForExistence(timeout: 15), app.debugDescription)
        open(app)
        app.buttons["habit-add"].tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        name.tap(); name.typeText("عادة قيد الحفظ")
        app.buttons["ui-test-open-bahw-root"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(name.value as? String, "عادة قيد الحفظ", "A lobby-root link must not remove the unsaved habit editor.")
        app.buttons["إلغاء"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bahw-greeting"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["habits-title"].exists)

        app.open(URL(string: "madar://bahw/year")!)
        XCTAssertTrue(app.descendants(matching: .any)["bahw-year-hero"].waitForExistence(timeout: 10), app.debugDescription)
        app.open(URL(string: "madar://bahw/habits")!)
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["bahw-year-hero"].exists)
        app.terminate()
    }

    func testBahwRootRoutePreservesPastDayDraftFromHabitDetail() throws {
        continueAfterFailure = false
        let app = app("since", rootRouteHarness: true)
        open(app)
        app.buttons["habits-view-all"].tap()
        let gift = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إهداء من تحب")).firstMatch
        for _ in 0..<8 where !gift.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(gift.isHittable, app.debugDescription)
        gift.tap()

        let past = app.buttons["habit-past-day"]
        for _ in 0..<6 where !past.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(past.isHittable, app.debugDescription)
        past.tap()
        XCTAssertTrue(app.buttons["habit-past-save"].waitForExistence(timeout: 5), app.debugDescription)
        let day = app.datePickers["habit-past-date"].buttons.matching(NSPredicate(format: "label CONTAINS %@", "12")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
        day.tap()
        let line = app.buttons["habit-past-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), app.debugDescription)
        line.tap()
        XCTAssertTrue(line.isSelected)

        let sheetTop = max(8, app.buttons["ui-test-open-bahw-root"].frame.minY - 20)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: sheetTop))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["habit-past-save"].waitForExistence(timeout: 5), "A swipe must not discard a changed past-day selection.")
        XCTAssertTrue(line.isSelected)

        app.buttons["ui-test-open-bahw-root"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5), "The past-day sheet should remain open until the draft is handled.")
        XCTAssertTrue(line.isSelected, "A root route must not discard the selected diary line.")
        XCTAssertTrue(app.staticTexts["مشيت مع أخي بعد العصر."].exists, "The selected historical day must remain active.")
        app.buttons["إلغاء"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bahw-greeting"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["habits-title"].exists)
    }

    func testHabitEditorSwipeKeepsUnsavedDraftOpen() throws {
        continueAfterFailure = false
        let app = app("empty"); open(app); app.buttons["habit-first"].tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        name.tap(); name.typeText("عادة قيد الحفظ")
        let sheetTop = max(8, name.frame.minY - 35)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: sheetTop))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "عادة قيد الحفظ", "A swipe must not discard an edited habit.")
        app.buttons["habit-cancel"].tap()
        app.terminate()
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
