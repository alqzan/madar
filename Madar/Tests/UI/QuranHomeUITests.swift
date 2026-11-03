import XCTest

@MainActor final class QuranHomeUITests: XCTestCase {
    func testHomeLevelsDetailsAndDraftResumeAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), store = UUID().uuidString
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        for level in ["simple", "medium", "deep", "max"] {
            let option = app.buttons["quran-level-hifz-" + level]
            XCTAssertFalse(option.label.contains("×"), option.label)
            XCTAssertTrue(option.label.contains("صفح") || option.label.contains("سطر") || option.label.contains("آي"), option.label)
        }
        let coverageLabel = app.staticTexts["quran-coverage-label"]
        let hadith = app.buttons["quran-coverage-hadith"]
        XCTAssertLessThan(hadith.frame.maxY, coverageLabel.frame.minY)
        let countFrame = app.staticTexts["quran-coverage-title"].frame
        XCTAssertGreaterThan(countFrame.minY, coverageLabel.frame.maxY)
        XCTAssertLessThanOrEqual(countFrame.minY - coverageLabel.frame.maxY, 7)
        XCTAssertTrue(hadith.label.contains("يُقال لصاحب القرآن"))
        XCTAssertTrue(hadith.label.contains("فإن منزلك عند آخر آية تقرؤها"))
        attach(app, "M2-V01-home-L")
        app.swipeUp()
        XCTAssertTrue(app.otherElements["quran-log14"].exists)
        attach(app, "M2-V01-home-scrolled-L")
        app.swipeDown()
        let coverageBeforeHadith = app.staticTexts["quran-coverage-title"].label
        app.buttons["quran-coverage-hadith"].tap()
        XCTAssertTrue(app.staticTexts["quran-hadith-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quran-hadith-text"].label.contains("فإن منزلك عند آخر آية تقرؤها"))
        XCTAssertTrue(app.staticTexts["quran-hadith-source"].label.contains("١٤٦٤"))
        attach(app, "M2-V01-hadith-L")
        app.buttons["quran-hadith-close"].tap()
        XCTAssertEqual(app.staticTexts["quran-coverage-title"].label, coverageBeforeHadith)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        app.buttons["quran-step-hifz"].tap()
        XCTAssertTrue(app.buttons["تمّ"].waitForExistence(timeout: 5)); app.buttons["تمّ"].tap()
        let deep = app.buttons["quran-level-hifz-deep"]; deep.tap()
        waitSelected(app.buttons["quran-level-hifz-deep"])
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["quran-level-hifz-deep"].waitForExistence(timeout: 20)); waitSelected(app.buttons["quran-level-hifz-deep"])
        app.buttons["quran-level-hifz-medium"].tap()
        let begin = app.buttons["quran-begin"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: begin)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        begin.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        let resume = app.buttons["quran-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), app.debugDescription)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "M2-improve-resume-L"; capture.lifetime = .keepAlways; add(capture)
        resume.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15))
        app.terminate()
    }
    /// Owner 20 Oct: the day is flexible; a later open step starts directly from its sheet.
    func testLaterStepStartsOutOfOrderFromItsSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quran-begin"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-step-hifz"].exists, app.debugDescription)
        let later = app.buttons["quran-step-review"], laterID = later.identifier
        XCTAssertTrue(later.waitForExistence(timeout: 5), app.debugDescription)
        if !later.isHittable { app.swipeUp(velocity: .slow) }
        later.tap()
        let start = app.buttons["quran-step-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "\(laterID) " + app.debugDescription)
        XCTAssertEqual(start.label, "ابدأ بها الآن", "review must be a later step than hifz here")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "M2-V01-step-start-L"; shot.lifetime = .keepAlways; add(shot)
        start.tap()
        XCTAssertTrue(app.buttons["quran-session-advance"].waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsVerifiedSourcesAndReturnsToItsRow() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(
            variant: "reference",
            expectedExcerptID: "bukhari-2-187",
            expectedExcerptText: "الرَّفَثُ إِلَى نِسَائِكُمْ"
        )
    }

    func testDailyWirdReferenceCanSelectMultipleSavedTafsirBooks() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_QURAN_FIXTURE": "reference",
            "MADAR_UI_TAFSIR_FIXTURE": "secondBook",
        ]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)

        let saadiText = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quran-reference-tafsir-text-42-")
        ).firstMatch
        XCTAssertTrue(saadiText.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("السعدي"))

        app.buttons["quran-reference-tafsir-picker"].tap()
        let ibnKathirChoice = app.buttons["quran-reference-tafsir-choice-1503"]
        XCTAssertTrue(ibnKathirChoice.waitForExistence(timeout: 5), app.debugDescription)
        ibnKathirChoice.tap()

        let ibnKathir187 = app.staticTexts["quran-reference-tafsir-text-1503-194"]
        let ibnKathir188 = app.staticTexts["quran-reference-tafsir-text-1503-195"]
        XCTAssertTrue(ibnKathir187.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(ibnKathir188.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(ibnKathir187.label.contains("١٨٧"), ibnKathir187.label)
        XCTAssertTrue(ibnKathir188.label.contains("١٨٨"), ibnKathir188.label)
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("ابن كثير"))
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("السعدي"))

        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-tafsir-text-1503-194"].waitForExistence(timeout: 10), app.debugDescription)
        let saadiAfterReopen = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quran-reference-tafsir-text-42-")
        ).firstMatch
        XCTAssertTrue(saadiAfterReopen.exists, "The original selection remains alongside Ibn Kathir.")
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("ابن كثير"))
        app.terminate()
    }

    func testDailyWirdReferenceShowsFatihaSourceForItsExactAyah() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceFatiha")
    }

    func testDailyWirdReferenceShowsVerifiedOpeningOfFatihaWithCarefulAttribution() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceFatihaOpening")
    }

    func testDailyWirdReferenceShowsAyatAlKursiSourceForItsExactAyah() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceKursi")
    }

    func testDailyWirdReferenceShowsVerifiedTafsirForAlBaqarah183() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceSadi183")
    }

    func testDailyWirdReferenceShowsAlBaqarah189ContextWithoutClaimingCause() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara189"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٨٩"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٨٩"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-ibn-ashur-2-189-context"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("وقد قيل في تفسير الآية"), excerpt.label)
        XCTAssertTrue(excerpt.label.contains("الذين سألوا عن الأهلة") && excerpt.label.contains("النسيء"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-ashur-2-189-context"].label.contains("٢/ ١٩٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-ashur-2-189-context"].exists)
        let note = app.staticTexts["quran-reference-note-ibn-ashur-2-189-context"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(note.label.contains("مثلٌ للنسيء") && note.label.contains("لا تقرير لسبب النزول"), note.label)
        app.buttons["quran-reference-filter-context"].tap()
        attach(app, "M2-X01-wird-reference-baqara-189-after-cn03-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah190TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara190")
    }

    func testDailyWirdReferenceShowsAlBaqarah191TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara191")
    }

    func testDailyWirdReferenceShowsAlBaqarah193TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara193")
    }

    func testDailyWirdReferenceShowsAlBaqarah192TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara192")
    }

    func testDailyWirdReferenceShowsAlBaqarah194TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara194")
    }

    func testDailyWirdReferenceShowsAlBaqarah195TafsirWithItsCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara195")
    }

    func testDailyWirdReferenceShowsAlBaqarah196To198TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara196198")
    }

    func testDailyWirdReferenceShowsAlBaqarah199To202TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara199202")
    }

    func testDailyWirdReferenceShowsAlBaqarah203To206TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara203206")
    }

    func testDailyWirdReferenceShowsAlBaqarah208To209TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara208209")
    }

    func testDailyWirdReferenceShowsAlBaqarah211To213TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara211213")
    }

    func testDailyWirdReferenceShowsAlBaqarah214To215TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara214215")
    }

    func testDailyWirdReferenceShowsAlBaqarah219TafsirWithCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara219")
    }

    func testDailyWirdReferenceShowsAlBaqarah220TafsirWithCitation() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara220")
    }

    func testDailyWirdReferenceSeparatesAlImranContextFromCauseOfRevelation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceAalImran"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٠"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٠"), rangeTitle.label)
        XCTAssertTrue(app.staticTexts["quran-reference-intro"].label.contains("أسباب النزول والسياق"))
        let selectedTafsir = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quran-reference-tafsir-text-42-")
        ).firstMatch
        XCTAssertTrue(selectedTafsir.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("السعدي"))
        let context = app.staticTexts["quran-reference-excerpt-maathur-3-190-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(context.label.contains("ولِمَ لا أفعل"), context.label)
        XCTAssertTrue(context.label.contains("سبحانك فقنا عذاب النار"), context.label)
        let note = app.staticTexts["quran-reference-note-maathur-3-190-context"]
        XCTAssertTrue(note.label.contains("إسناد جيد"), note.label)
        XCTAssertTrue(note.label.contains("لا يذكر حادثةً سبقت نزولها"), note.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-maathur-3-190-context"].label.contains("٥/ ٧٦٢"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-maathur-3-190-context"].exists)
        app.buttons["quran-reference-filter-context"].tap()
        attach(app, "M2-X01-wird-reference-alimran-190-after-cn03-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlImran191To195TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceAalImran191195")
    }

    func testDailyWirdReferenceShowsAlImran198To200TafsirWithCitations() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceAalImran198200")
    }

    func testDailyWirdReferenceShowsVerifiedNisaa36NeighborTafsir() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceNisaa36")
    }

    func testDailyWirdReferencePreservesCrossSurahBoundary() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBoundary")
    }

    func testDailyWirdReferenceShowsBaqara178To186Sources() throws {
        try assertDailyWirdReferenceUsesSavedFullTafsir(variant: "referenceBaqara178186")
    }

    func testDailyWirdReferenceShowsContextAndPartialSourceCoverage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_QURAN_FIXTURE": "referencePartial",
        ]
        app.launch()
        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)

        app.buttons["quran-reference-filter-context"].tap()
        let context = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-178-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(context.label.contains("غزت قريظة"), context.label)
        XCTAssertTrue(app.staticTexts["quran-reference-note-ibn-kathir-2-178-context"].label.contains("لا يصوغه خبرًا صريحًا عن سبب النزول"))

        app.buttons["quran-reference-filter-all"].tap()
        let tafsir = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quran-reference-tafsir-text-42-")
        ).firstMatch
        XCTAssertTrue(tafsir.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testFirstUseShowsPlanActionWithoutZeroStreakOrDepthControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        if app.buttons["first-run-skip"].waitForExistence(timeout: 2) { app.buttons["first-run-skip"].tap() }
        let start = app.buttons["first-run-continue"]
        if start.waitForExistence(timeout: 2) { start.tap(); if start.exists && start.isHittable { start.tap() } }
        let tabBar = app.otherElements["fixed-tab-bar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), app.debugDescription)
        for title in ["البهو", "الصلاة", "القرآن", "المال", "المحبرة"] {
            XCTAssertTrue(tabBar.buttons[title].waitForExistence(timeout: 5), "Missing native destination: \(title)\n\(app.debugDescription)")
        }
        let notes = app.buttons["tab-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "Notes must stay directly reachable.\n\(app.debugDescription)")
        let tabsShot = XCTAttachment(screenshot: app.screenshot()); tabsShot.name = "M0-native-glass-room-shortcuts-L"; tabsShot.lifetime = .keepAlways; add(tabsShot)
        notes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["notes-tab"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["tab-money"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-home"].waitForExistence(timeout: 10), app.debugDescription)
        let moneyShot = XCTAttachment(screenshot: app.screenshot()); moneyShot.name = "M0-native-glass-money-active-L"; moneyShot.lifetime = .keepAlways; add(moneyShot)
        app.buttons["tab-mihbara"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        tabBar.buttons["القرآن"].tap()
        XCTAssertTrue(app.buttons["quran-start-plan"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-streak"].exists)
        XCTAssertFalse(app.buttons["quran-level-hifz-medium"].exists)
        XCTAssertFalse(app.buttons["quran-level-review-medium"].exists)
        attach(app, "UX-09-first-use-L")
        app.buttons["quran-start-plan"].tap()
        XCTAssertTrue(app.staticTexts["quran-setup-title"].waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 { let next = app.buttons["quran-setup-next"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap() }
        XCTAssertTrue(app.buttons["quran-open-plan"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["quran-streak"].exists)
        XCTAssertTrue(app.buttons["quran-level-hifz-medium"].exists)
        attach(app, "UX-09-new-plan-L")
        app.buttons["quran-open-plan"].tap()
        XCTAssertTrue(app.staticTexts["quran-plan-forecast"].waitForExistence(timeout: 10))
    }

    private func assertDailyWirdReferenceUsesSavedFullTafsir(
        variant: String,
        expectedExcerptID: String? = nil,
        expectedExcerptText: String? = nil
    ) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00",
            "MADAR_UI_QURAN_FIXTURE": variant,
        ]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)
        let range = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(range.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(range.label.contains("الآية") || range.label.contains("الآيات"), range.label)
        let reading = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quran-reference-tafsir-text-42-")
        ).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["quran-reference-tafsir-picker"].label.contains("السعدي"))
        XCTAssertGreaterThan(reading.label.count, 50, "The selected book should show its full sourced passage.")
        if let expectedExcerptID, let expectedExcerptText {
            let excerpt = app.staticTexts["quran-reference-excerpt-\(expectedExcerptID)"]
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(excerpt.label.contains(expectedExcerptText), excerpt.label)
            XCTAssertFalse(excerpt.label.contains("…"), excerpt.label)
            app.buttons["quran-reference-filter-asbab"].tap()
            XCTAssertTrue(excerpt.isHittable, app.debugDescription)
            attach(app, "M2-X01-wird-reference-baqara-187-after-cn03-L")
        }
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    private func waitSelected(_ button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "محدد"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
