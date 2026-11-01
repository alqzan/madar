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
        let tafsir = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-187"]
        let sabab = app.staticTexts["quran-reference-excerpt-bukhari-2-187"]
        let tafsir188 = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-188"]
        let sabab188 = app.staticTexts["quran-reference-excerpt-maathur-2-188"]
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
        let excerpt = app.staticTexts["quran-reference-excerpt-ibn-kathir-1-5"]
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
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-tabari-1-2"].waitForExistence(timeout: 5), app.debugDescription)
        let saadi = app.staticTexts["quran-reference-excerpt-saadi-1-2"]
        XCTAssertTrue(saadi.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi.label.contains("الثناء على الله بصفات الكمال"), saadi.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-1-2"].label.contains("ص ٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-1-2"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-qurtubi-1-3-in-ibn-kathir"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-ibn-kathir-1-4"].exists)
        let saadi14 = app.staticTexts["quran-reference-excerpt-saadi-1-4"]
        XCTAssertTrue(saadi14.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi14.label.contains("من آثارها أنه يأمر وينهى"), saadi14.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-1-4"].label.contains("ص ٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-1-4"].exists)
        for _ in 0..<5 where !saadi14.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saadi14.isHittable, app.debugDescription)
        app.swipeUp(velocity: .slow)
        attach(app, "M2-X01-wird-reference-fatiha-1-4-L")
        let saadi15 = app.staticTexts["quran-reference-excerpt-saadi-1-5"]
        XCTAssertTrue(saadi15.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi15.label.contains("تقديم المعمول يفيد الحصر"), saadi15.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-1-5"].label.contains("ص ٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-1-5"].exists)
        for _ in 0..<3 where !saadi15.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saadi15.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-fatiha-1-5-L")
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
        let excerpt = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-255"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("هذه آية الكرسي، ولها شأن عظيم"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-255"].label.contains("٢/ ٢٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-255"].exists)
        let context = app.staticTexts["quran-reference-excerpt-ibn-ashur-2-255-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(context.label.contains("تَقْرِيرِ الْوَحْدَانِيَّةِ وَالْبَعْثِ"), context.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-ashur-2-255-context"].label.contains("٣/ ١٧"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-ashur-2-255-context"].exists)
        for _ in 0..<3 where !context.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(context.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-kursi-r40-L")
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
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-183"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("أكبر أسباب التقوى"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-183"].label.contains("ص ٨٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-183"].exists)
        let ibnKathir = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-183"]
        XCTAssertTrue(ibnKathir.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(ibnKathir.label.contains("فلهم فيه أسوة") && ibnKathir.label.contains("أكمل مما فعله أولئك"), ibnKathir.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-183"].label.contains("٢/ ٥٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-183"].exists)
        for _ in 0..<3 where !ibnKathir.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ibnKathir.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-baqara-183-after-r46-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
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
        XCTAssertTrue(excerpt.label.contains("الذين سألوا عن الأهلة") && excerpt.label.contains("النسيء"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-ashur-2-189-context"].label.contains("٢/ ١٩٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-ashur-2-189-context"].exists)
        let note = app.staticTexts["quran-reference-note-ibn-ashur-2-189-context"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(note.label.contains("مثلٌ للنسيء") && note.label.contains("لا تقرير لسبب النزول"), note.label)
        attach(app, "M2-X01-wird-reference-baqara-189-after-r49-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah190TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara190"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٠"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٠"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-190"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("النهي عن الاعتداء"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-190"].label.contains("ص ٨٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-190"].exists)
        attach(app, "M2-X01-wird-reference-baqara-190-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah191TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara191"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩١"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩١"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-tabari-2-191"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("والشركُ") && excerpt.label.contains("القتلِ"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-2-191"].label.contains("٣/ ٢٩٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-2-191"].exists)
        attach(app, "M2-X01-wird-reference-baqara-191-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah193TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara193"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٣"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٣"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-193"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("فكفوا عنهم"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-193"].label.contains("٢/ ٨٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-193"].exists)
        attach(app, "M2-X01-wird-reference-baqara-193-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah192TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara192"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٢"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٢"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-192"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("فإن تركوا القتال في الحرم"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-192"].label.contains("٢/ ٨٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-192"].exists)
        attach(app, "M2-X01-wird-reference-baqara-192-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah194TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara194"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٤"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٤"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-194"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("المماثلة في مقابلة المعتدي"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-194"].label.contains("ص ٨٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-194"].exists)
        attach(app, "M2-X01-wird-reference-baqara-194-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah195TafsirWithItsCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara195"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٥"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٥"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-195"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("ساق النفقة"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-195"].label.contains("ص ٩٠"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-195"].exists)
        attach(app, "M2-X01-wird-reference-baqara-195-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah196To198TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara196198"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٦") && referenceButton.label.contains("١٩٨"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٦") && rangeTitle.label.contains("١٩٨"), rangeTitle.label)
        let verse196 = app.staticTexts["quran-reference-excerpt-saadi-2-196"]
        XCTAssertTrue(verse196.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse196.label.contains("إتقانهما وإحسانهما"), verse196.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-196"].label.contains("ص ٩٠"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-196"].exists)
        attach(app, "M2-X01-wird-reference-baqara-196-198-L")

        let verse197 = app.staticTexts["quran-reference-excerpt-saadi-2-197"]
        for _ in 0..<4 where !verse197.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse197.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse197.label.contains("عشر من ذي الحجة"), verse197.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-197"].label.contains("ص ٩١"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-197"].exists)

        let verse198 = app.staticTexts["quran-reference-excerpt-saadi-2-198"]
        for _ in 0..<4 where !verse198.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse198.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse198.label.contains("في مواسم الحج وغيره"), verse198.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-198"].label.contains("ص ٩٢"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-198"].exists)
        attach(app, "M2-X01-wird-reference-baqara-198-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah199To202TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara199202"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٩") && referenceButton.label.contains("٢٠٢"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٩") && rangeTitle.label.contains("٢٠٢"), rangeTitle.label)
        let verse199 = app.staticTexts["quran-reference-excerpt-saadi-2-199"]
        XCTAssertTrue(verse199.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse199.label.contains("باستغفاره والإكثار من ذكره"), verse199.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-199"].label.contains("ص ٩٢"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-199"].exists)
        attach(app, "M2-X01-wird-reference-baqara-199-202-L")

        let verse200 = app.staticTexts["quran-reference-excerpt-saadi-2-200"]
        for _ in 0..<4 where !verse200.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse200.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse200.label.contains("مطالب الدنيا"), verse200.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-200"].label.contains("ص ٩٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-200"].exists)

        let verse201 = app.staticTexts["quran-reference-excerpt-saadi-2-201"]
        for _ in 0..<4 where !verse201.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse201.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse201.label.contains("مصلحة الدارين"), verse201.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-201"].label.contains("ص ٩٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-201"].exists)

        let verse202 = app.staticTexts["quran-reference-excerpt-saadi-2-202"]
        for _ in 0..<4 where !verse202.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse202.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse202.label.contains("نصيب من كسبهم وعملهم"), verse202.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-202"].label.contains("ص ٩٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-202"].exists)
        attach(app, "M2-X01-wird-reference-baqara-202-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah203To206TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara203206"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢٠٣") && referenceButton.label.contains("٢٠٦"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢٠٣") && rangeTitle.label.contains("٢٠٦"), rangeTitle.label)
        for (id, phrase, page) in [
            ("saadi-2-203", "أيام التشريق الثلاثة بعد العيد", "ص ٩٣"),
            ("saadi-2-204", "يخالف قوله فعله", "ص ٩٣"),
            ("saadi-2-205", "أعمال المعاصي", "ص ٩٣"),
            ("saadi-2-206", "تكبر وأنف", "ص ٩٤")
        ] {
            let excerpt = app.staticTexts["quran-reference-excerpt-\(id)"]
            for _ in 0..<5 where !excerpt.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(excerpt.label.contains(phrase), excerpt.label)
            XCTAssertTrue(app.staticTexts["quran-reference-citation-\(id)"].label.contains(page))
            XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-\(id)"].exists)
        }
        attach(app, "M2-X01-wird-reference-baqara-203-206-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah208To209TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara208209"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢٠٨") && referenceButton.label.contains("٢٠٩"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢٠٨") && rangeTitle.label.contains("٢٠٩"), rangeTitle.label)
        let verse208 = app.staticTexts["quran-reference-excerpt-saadi-2-208"]
        XCTAssertTrue(verse208.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse208.label.contains("في جميع شرائع الدين"), verse208.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-208"].label.contains("ص ٩٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-208"].exists)
        attach(app, "M2-X01-wird-reference-baqara-208-209-L")

        let verse209 = app.staticTexts["quran-reference-excerpt-saadi-2-209"]
        for _ in 0..<3 where !verse209.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse209.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse209.label.contains("على علم ويقين"), verse209.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-209"].label.contains("ص ٩٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-209"].exists)
        attach(app, "M2-X01-wird-reference-baqara-209-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah211To213TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara211213"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢١١") && referenceButton.label.contains("٢١٣"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢١١") && rangeTitle.label.contains("٢١٣"), rangeTitle.label)
        attach(app, "M2-X01-wird-reference-baqara-211-213-L")

        for (id, phrase) in [
            ("saadi-2-211", "بدلوا نعمة الله كفرا"),
            ("saadi-2-212", "بإيمانه وصبره"),
            ("saadi-2-213", "فهو حق")
        ] {
            let excerpt = app.staticTexts["quran-reference-excerpt-\(id)"]
            for _ in 0..<4 where !excerpt.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(excerpt.label.contains(phrase), excerpt.label)
            XCTAssertTrue(app.staticTexts["quran-reference-citation-\(id)"].label.contains("ص ٩٥"))
            XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-\(id)"].exists)
        }
        attach(app, "M2-X01-wird-reference-baqara-213-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah214To215TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara214215"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢١٤") && referenceButton.label.contains("٢١٥"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢١٤") && rangeTitle.label.contains("٢١٥"), rangeTitle.label)
        let verse214 = app.staticTexts["quran-reference-excerpt-saadi-2-214"]
        XCTAssertTrue(verse214.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse214.label.contains("الفرج عند الشدة"), verse214.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-214"].label.contains("ص ٩٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-214"].exists)
        attach(app, "M2-X01-wird-reference-baqara-214-215-L")

        let verse215 = app.staticTexts["quran-reference-excerpt-saadi-2-215"]
        for _ in 0..<3 where !verse215.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(verse215.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(verse215.label.contains("القرب والحاجة"), verse215.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-215"].label.contains("ص ٩٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-215"].exists)
        attach(app, "M2-X01-wird-reference-baqara-215-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah219TafsirWithCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara219"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢١٩"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢١٩"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-219"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("أكبر مما يظنونه من نفعهما"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-219"].label.contains("ص ٩٨"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-219"].exists)
        attach(app, "M2-X01-wird-reference-baqara-219-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlBaqarah220TafsirWithCitation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara220"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٢٢٠"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("٢٢٠"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-2-220"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("إصلاح أموال اليتامى"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-220"].label.contains("ص ٩٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-220"].exists)
        attach(app, "M2-X01-wird-reference-baqara-220-L")
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
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-saadi-3-190"].waitForExistence(timeout: 5), app.debugDescription)
        let context = app.staticTexts["quran-reference-excerpt-maathur-3-190-context"]
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

    func testDailyWirdReferenceShowsAlImran191To195TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceAalImran191195"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩١") && referenceButton.label.contains("١٩٥"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩١") && rangeTitle.label.contains("١٩٥"), rangeTitle.label)
        attach(app, "M2-X01-wird-reference-alimran-191-195-L")

        for (id, phrase, citation) in [
            ("saadi-3-191", "التفكر عبادة", "ص ١٦١"),
            ("saadi-3-192", "السخط من الله", "ص ١٦١"),
            ("saadi-3-193", "مبادرة، وسارعنا إليه", "ص ١٦١"),
            ("saadi-3-194", "الثواب على ذلك", "ص ١٦١"),
            ("saadi-3-195", "ثواب أعمالهم كاملا موفرا", "ص ١٦٢")
        ] {
            let excerpt = app.staticTexts["quran-reference-excerpt-\(id)"]
            for _ in 0..<5 where !excerpt.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(excerpt.label.contains(phrase), excerpt.label)
            XCTAssertTrue(app.staticTexts["quran-reference-citation-\(id)"].label.contains(citation))
            XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-\(id)"].exists)
        }
        attach(app, "M2-X01-wird-reference-alimran-195-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsAlImran198To200TafsirWithCitations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceAalImran198200"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٩٨") && referenceButton.label.contains("٢٠٠"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٩٨") && rangeTitle.label.contains("٢٠٠"), rangeTitle.label)
        attach(app, "M2-X01-wird-reference-alimran-198-200-L")

        for (id, phrase) in [
            ("saadi-3-198", "البر الرحيم من بره أجرا عظيما"),
            ("saadi-3-199", "طائفة موفقة للخير"),
            ("saadi-3-200", "لزوم الصبر")
        ] {
            let excerpt = app.staticTexts["quran-reference-excerpt-\(id)"]
            for _ in 0..<5 where !excerpt.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(excerpt.label.contains(phrase), excerpt.label)
            XCTAssertTrue(app.staticTexts["quran-reference-citation-\(id)"].label.contains("ص ١٦٢"))
            XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-\(id)"].exists)
        }
        attach(app, "M2-X01-wird-reference-alimran-200-L")
        app.buttons["quran-reference-close"].tap()
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testDailyWirdReferenceShowsVerifiedNisaa36NeighborTafsir() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceNisaa36"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("٣٦"), referenceButton.label)
        referenceButton.tap()

        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("النِّسَاء") && rangeTitle.label.contains("٣٦"), rangeTitle.label)
        let excerpt = app.staticTexts["quran-reference-excerpt-saadi-4-36-neighbor"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(excerpt.label.contains("الجار أقرب بابا كان آكد حقا"), excerpt.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-4-36-neighbor"].label.contains("ص ١٧٧"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-4-36-neighbor"].exists)
        attach(app, "M2-X01-wird-reference-nisaa-36-L")
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
        let saadi = app.staticTexts["quran-reference-excerpt-saadi-2-286"]
        XCTAssertTrue(saadi.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi.label.contains("غذاء للأرواح ودواء للأبدان"), saadi.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-286"].label.contains("ص ١٢٠"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-286"].exists)
        let tabari = app.staticTexts["quran-reference-excerpt-tabari-2-286"]
        XCTAssertTrue(tabari.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(tabari.label.contains("فلا يُضَيِّقُ عليها ولا يَجْهَدُها"), tabari.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-2-286"].label.contains("٥/ ١٥٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-2-286"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "quran-reference-excerpt-tabari-2-286").count, 1)
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

    func testDailyWirdReferenceShowsBaqara178To186Sources() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referenceBaqara178186"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٧٨") && referenceButton.label.contains("١٨٦"), referenceButton.label)
        referenceButton.tap()
        let rangeTitle = app.staticTexts["quran-reference-range"]
        XCTAssertTrue(rangeTitle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rangeTitle.label.contains("١٧٨") && rangeTitle.label.contains("١٨٦"), rangeTitle.label)

        let ibnKathir = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-178-context"]
        XCTAssertTrue(ibnKathir.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(ibnKathir.label.contains("غزت قريظة"), ibnKathir.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-178-context"].label.contains("٢/ ٤٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-178-context"].exists)
        let ibnKathir185 = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-185"]
        XCTAssertTrue(ibnKathir185.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-185"].label.contains("٢/ ٥٧"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-185"].exists)
        let saadi185 = app.staticTexts["quran-reference-excerpt-saadi-2-185"]
        XCTAssertTrue(saadi185.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi185.label.contains("يريد الله تعالى أن ييسر عليكم الطرق الموصلة إلى رضوانه"), saadi185.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-185"].label.contains("ص ٨٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-185"].exists)
        let saadi178 = app.staticTexts["quran-reference-excerpt-saadi-2-178"]
        XCTAssertTrue(saadi178.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi178.label.contains("إقامة للعدل والقسط بين العباد"), saadi178.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-178"].label.contains("ص ٨٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-178"].exists)
        attach(app, "M2-X01-wird-reference-baqara-178-after-L")

        let ibnAshur = app.staticTexts["quran-reference-excerpt-ibn-ashur-2-186"]
        XCTAssertTrue(ibnAshur.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-ashur-2-186"].label.contains("٢/ ١٧٨"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-ashur-2-186"].exists)
        let saadi186 = app.staticTexts["quran-reference-excerpt-saadi-2-186"]
        XCTAssertTrue(saadi186.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi186.label.contains("فهو قريب أيضا من داعيه، بالإجابة"), saadi186.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-186"].label.contains("ص ٨٧"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-186"].exists)
        for _ in 0..<8 where !saadi186.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saadi186.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-baqara-186-after-L")
        for _ in 0..<2 where !saadi185.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(saadi185.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-baqara-185-L")
        app.terminate()
    }

    func testDailyWirdReferenceShowsContextAndPartialSourceCoverage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "referencePartial"]
        app.launch()

        let referenceButton = app.buttons["quran-step-reference-hifz"]
        XCTAssertTrue(referenceButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(referenceButton.label.contains("١٧٧") && referenceButton.label.contains("١٨٤"), referenceButton.label)
        referenceButton.tap()

        XCTAssertTrue(app.staticTexts["quran-reference-title"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["quran-reference-filter-context"].tap()
        let qisasContext = app.staticTexts["quran-reference-excerpt-ibn-kathir-2-178-context"]
        XCTAssertTrue(qisasContext.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(qisasContext.label.contains("غزت قريظة"), qisasContext.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-178-context"].label.contains("٢/ ٤٤"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-178-context"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-note-ibn-kathir-2-178-context"].label.contains("لا يصوغه خبرًا صريحًا عن سبب النزول"))
        app.buttons["quran-reference-filter-all"].tap()
        let tabari179 = app.staticTexts["quran-reference-excerpt-tabari-2-179"]
        XCTAssertTrue(tabari179.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(tabari179.label.contains("بينَكم بذلك حياةٌ"), tabari179.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-2-179"].label.contains("٣/ ١٢٠"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-2-179"].exists)
        let saadi179 = app.staticTexts["quran-reference-excerpt-saadi-2-179"]
        XCTAssertTrue(saadi179.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi179.label.contains("لأن من عرف أنه مقتول إذا قتل، لا يكاد يصدر منه القتل"), saadi179.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-179"].label.contains("ص ٨٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-179"].exists)
        for _ in 0..<4 where !saadi179.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saadi179.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-baqara-179-L")
        let tabari180 = app.staticTexts["quran-reference-excerpt-tabari-2-180"]
        XCTAssertTrue(tabari180.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(tabari180.label.contains("والخيرُ المالُ"), tabari180.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-2-180"].label.contains("٣/ ١٢٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-2-180"].exists)
        let saadi180 = app.staticTexts["quran-reference-excerpt-saadi-2-180"]
        XCTAssertTrue(saadi180.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi180.label.contains("بل يرتبهم على القرب والحاجة"), saadi180.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-180"].label.contains("ص ٨٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-180"].exists)
        for _ in 0..<4 where !saadi180.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saadi180.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-baqara-180-L")
        let tabari181 = app.staticTexts["quran-reference-excerpt-tabari-2-181"]
        XCTAssertTrue(tabari181.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(tabari181.label.contains("إثمُ التبديلِ"), tabari181.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-tabari-2-181"].label.contains("٣/ ١٣٩"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-tabari-2-181"].exists)
        let saadi182 = app.staticTexts["quran-reference-excerpt-saadi-2-182"]
        XCTAssertTrue(saadi182.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi182.label.contains("الأحسن والأعدل"), saadi182.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-182"].label.contains("ص ٨٥"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-182"].exists)
        XCTAssertTrue(app.staticTexts["quran-reference-excerpt-ibn-kathir-2-184"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-ibn-kathir-2-184"].label.contains("٢/ ٥٣"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-ibn-kathir-2-184"].exists)
        let saadi184 = app.staticTexts["quran-reference-excerpt-saadi-2-184"]
        XCTAssertTrue(saadi184.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saadi184.label.contains("أن يقضي أياما قصيرة باردة"), saadi184.label)
        XCTAssertTrue(app.staticTexts["quran-reference-citation-saadi-2-184"].label.contains("ص ٨٦"))
        XCTAssertTrue(app.descendants(matching: .any)["quran-reference-source-saadi-2-184"].exists)
        let coverage = app.descendants(matching: .any)["quran-reference-partial-coverage-count"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(coverage.label.contains("٧") && coverage.label.contains("٨"), coverage.label)
        XCTAssertFalse(app.descendants(matching: .any)["quran-reference-empty"].exists)
        for _ in 0..<3 where !coverage.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(coverage.isHittable, app.debugDescription)
        attach(app, "M2-X01-wird-reference-partial-coverage-L")
        app.buttons["quran-reference-ayahs-toggle"].tap()
        XCTAssertTrue(app.staticTexts["quran-reference-ayah-text-184"].waitForExistence(timeout: 5), app.debugDescription)
        let uncoveredSearch = app.descendants(matching: .any)["quran-reference-search-184"]
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
