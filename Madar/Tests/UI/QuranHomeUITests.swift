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
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "reference"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٨٧") && referenceButton.label.contains("١٨٨"), referenceButton.label)
        referenceButton.tap()

        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)
        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.label.contains("١٨٧") && rangeTitle.label.contains("١٨٨"), rangeTitle.label)
        let tafsir = app.staticTexts["quran-reference-excerpt-tafsir-194"]
        let sabab = app.staticTexts["quran-reference-excerpt-asbab-194"]
        let tafsir188 = app.staticTexts["quran-reference-excerpt-tafsir-195"]
        let sabab188 = app.staticTexts["quran-reference-excerpt-asbab-195"]
        XCTAssertTrue(tafsir.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(sabab.exists, app.debugDescription)
        XCTAssertTrue(tafsir188.exists, app.debugDescription)
        XCTAssertTrue(sabab188.exists, app.debugDescription)
        XCTAssertTrue(sabab188.label.contains("وأراد امرؤُ القيس"), sabab188.label)
        let transmission = app.staticTexts["quran-reference-note-maathur-2-188"]
        XCTAssertTrue(transmission.label.contains("سعيد بن جبير"))
        XCTAssertTrue(transmission.label.contains("لا يحكم هذا الموضع على إسناده"), transmission.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-187"].label.contains("٢/ ٦٧"))
        XCTAssertTrue(app.staticTexts["quran-reference-citation-bukhari-2-187"].label.contains("٢/ ٦٧٦"))
        XCTAssertTrue(app.staticTexts["quran-reference-citation-maathur-2-188"].label.contains("٣/ ٤٢٣"))
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-188"].label.contains("٢/ ٧٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-187"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-bukhari-2-187"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-maathur-2-188"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-188"].exists)
        attach(app, "M2-X01-wird-reference-L")

        app.buttons["quran-reference-filter-tafsir"].tap()
        XCTAssertTrue(tafsir.exists)
        XCTAssertTrue(tafsir188.exists)
        XCTAssertFalse(sabab.exists)
        app.buttons["quran-reference-filter-all"].tap()

        app.buttons["quran-reference-ayahs-toggle"].tap()
        let ayahText = app.staticTexts["quran-reference-ayah-text-194"]
        XCTAssertTrue(ayahText.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(ayahText.label.count, 80, "The selected ayah should display its full text.")
        XCTAssertTrue(app.staticTexts["quran-reference-ayah-text-195"].exists)
        let sourceSearch = app.descendants(matching: .any)["quran-reference-search-194"]
        XCTAssertTrue(sourceSearch.exists, app.debugDescription)
        XCTAssertTrue(sourceSearch.label.contains("ابحث عن مطلع الآية في الشاملة"), sourceSearch.label)
        for _ in 0..<3 where !sourceSearch.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(sourceSearch.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-ayah-search-L")
        XCTAssertFalse(app.staticTexts["quran-reference-ayah-text-193"].exists, "The reference must follow the exact verse range, not the whole page.")
        XCTAssertFalse(app.staticTexts["quran-reference-ayah-text-196"].exists, "The reference must stop at the exact end of the daily range.")

        app.buttons["quran-reference-filter-asbab"].tap()
        XCTAssertTrue(sabab.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(sabab188.exists)
        XCTAssertFalse(tafsir.exists)
        XCTAssertFalse(tafsir188.exists)
        app.buttons["quran-reference-filter-context"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-empty"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["quran-reference-close"].tap()

        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(referenceButton.isHittable)
        XCTAssertTrue(app.buttons["quran-begin"].exists)
        app.terminate()
    }

    func testDailyWirdReferenceShowsFatihaSourceForItsExactAyah() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceFatiha"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٥"), referenceButton.label)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-range"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-range"].label.contains("٥"))
        let excerpt = app.staticTexts["quran-reference-excerpt-tafsir-5"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("كمال المحبة والخضوع والخوف"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-1-5"].label.contains("١/ ٢٠٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-1-5"].exists)
        attach(app, "M2-X01-wird-reference-fatiha-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsVerifiedOpeningOfFatihaWithCarefulAttribution() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceFatihaOpening"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢") && referenceButton.label.contains("٥"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢") && rangeTitle.label.contains("٥"), rangeTitle.label)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-2"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-3"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-4"].exists)
        let attribution = app.staticTexts["quran-reference-note-qurtubi-1-3-in-ibn-kathir"]
        XCTAssertTrue(attribution.label.contains("ينقل ابن كثير هذا التعليل عن القرطبي"), attribution.label)
        let qiraat = app.staticTexts["quran-reference-note-ibn-kathir-1-4"]
        XCTAssertTrue(qiraat.label.contains("مَلِكِ") && qiraat.label.contains("مَالِكِ"), qiraat.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-1-2"].label.contains("١/ ١٣٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-1-2"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-qurtubi-1-3-in-ibn-kathir"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-1-4"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quran-reference-partial-coverage-count"].exists)
        attach(app, "M2-X01-wird-reference-fatiha-opening-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAyatAlKursiSourceForItsExactAyah() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceKursi"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢٥٥"), referenceButton.label)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-range"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-range"].label.contains("٢٥٥"))
        let excerpt = app.staticTexts["quran-reference-excerpt-tafsir-262"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("هذه آية الكرسي، ولها شأن عظيم"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-255"].label.contains("٢/ ٢٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-255"].exists)
        attach(app, "M2-X01-wird-reference-kursi-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsVerifiedTafsirForAlBaqarah183() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceSadi183"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٨٣"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٨٣"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-tafsir-190"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("أكبر أسباب التقوى"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-183"].label.contains("ص ٨٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-183"].exists)
        attach(app, "M2-X01-wird-reference-baqara-183-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
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
        XCTAssertTrue(app.staticTexts["quran-reference-intro"].label.contains("مقتطفات موثّقة"))
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-483"].waitForExistence(timeout: 5), app.debugDescription)
        let context = app.staticTexts["quran-reference-excerpt-context-483"]
        XCTAssertTrue(context.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(context.label.contains("ولِمَ لا أفعل"), context.label)
        let note = app.staticTexts["quran-reference-note-maathur-3-190-context"]
        XCTAssertTrue(note.label.contains("إسناد جيد"), note.label)
        XCTAssertTrue(note.label.contains("لا يذكر حادثةً سبقت نزولها"), note.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-maathur-3-190-context"].label.contains("٥/ ٧٦٢"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-maathur-3-190-context"].exists)
        attach(app, "M2-X01-wird-reference-alimran-190-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferencePreservesCrossSurahBoundary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBoundary"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        referenceButton.tap()
        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)
        let rangeTitle = app.staticTexts["quran-reference-range"].label
        XCTAssertTrue(rangeTitle.contains("البَقَرَة") && rangeTitle.contains("آل عِمران"), rangeTitle)
        XCTAssertTrue(rangeTitle.contains("٢٨٦") && rangeTitle.contains("١"), rangeTitle)
        let tafsir = app.staticTexts["quran-reference-excerpt-tafsir-293"]
        XCTAssertTrue(tafsir.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(tafsir.label.contains("غذاء للأرواح ودواء للأبدان"), tafsir.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-286"].label.contains("ص ١٢٠"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-286"].exists)
        XCTAssertFalse(app.staticTexts["quran-reference-excerpt-tafsir-294"].exists, "The adjacent first ayah of آل عمران is outside the selected hifz range.")
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-partial-coverage-count"].label.contains("١") )
        attach(app, "M2-X01-wird-reference-boundary-L")
        attach(app, "M2-X01-wird-reference-boundary-L")

        app.buttons["quran-reference-ayahs-toggle"].tap()
        XCTAssertTrue(app.staticTexts["quran-reference-ayah-text-293"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-ayah-text-294"].exists)
        XCTAssertFalse(app.staticTexts["quran-reference-ayah-text-292"].exists)
        XCTAssertFalse(app.staticTexts["quran-reference-ayah-text-295"].exists)
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(referenceButton.isHittable)
        app.terminate()
    }

    func testDailyWirdReferenceReportsPartialSourceCoverage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referencePartial"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٨١") && referenceButton.label.contains("١٨٥"), referenceButton.label)
        referenceButton.tap()

        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)
        let saadi182 = app.staticTexts["quran-reference-excerpt-tafsir-189"]
        XCTAssertTrue(saadi182.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi182.label.contains("الأحسن والأعدل"), saadi182.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-182"].label.contains("ص ٨٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-182"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-191"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tafsir-192"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-184"].label.contains("٢/ ٥٣"))
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-185"].label.contains("٢/ ٥٧"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-184"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-185"].exists)
        app.buttons["quran-reference-filter-context"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-empty"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["quran-reference-filter-all"].tap()
        let coverage = app.descendants(matching: .any)["quran-reference-partial-coverage-count"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(coverage.label.contains("٤") && coverage.label.contains("٥"), coverage.label)
        XCTAssertFalse(app.descendants(matching: .any)["quran-reference-empty"].exists)
        for _ in 0..<3 where !coverage.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(coverage.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-partial-coverage-L")
        app.buttons["quran-reference-ayahs-toggle"].tap()
        XCTAssertTrue(app.staticTexts["quran-reference-ayah-text-188"].waitForExistence(timeout: 5), app.debugDescription)
        let uncoveredSearch = app.descendants(matching: .any)["quran-reference-search-188"]
        XCTAssertTrue(uncoveredSearch.exists, app.debugDescription)
        for _ in 0..<3 where !uncoveredSearch.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(uncoveredSearch.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-partial-search-L")
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
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), app.debugDescription)
        for title in ["البهو", "الصلاة", "القرآن", "المال", "المحبرة"] {
            XCTAssertTrue(tabBar.buttons[title].waitForExistence(timeout: 5), "Missing native destination: \(title)\n\(app.debugDescription)")
        }
        let notes = app.buttons["tab-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "Notes must stay directly reachable.\n\(app.debugDescription)")
        let tabsShot = XCTAttachment(screenshot: app.screenshot()); tabsShot.name = "M0-native-glass-room-shortcuts-L"; tabsShot.lifetime = .keepAlways; add(tabsShot)
        notes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["notes-tab"].waitForExistence(timeout: 8), app.debugDescription)
        app.tabBars.buttons["المال"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["money-home"].waitForExistence(timeout: 10), app.debugDescription)
        let moneyShot = XCTAttachment(screenshot: app.screenshot()); moneyShot.name = "M0-native-glass-money-active-L"; moneyShot.lifetime = .keepAlways; add(moneyShot)
        app.tabBars.buttons["المحبرة"].tap()
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
    private func waitSelected(_ button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "محدد"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
