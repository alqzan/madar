import XCTest

@MainActor final class QuranMushafUITests: XCTestCase {
    func testMedinaSurahOpeningKeepsVerifiedAyahsInLightAndDark() {
        continueAfterFailure = false
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": theme,
                "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home", "MADAR_UI_QURAN_ROUTE": "madar://quran/page/128"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["quran-mushaf-page"].waitForExistence(timeout: 25), app.debugDescription)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "سورة الأن")).firstMatch.exists, app.debugDescription)
            attach(app, "M2-23-anam-opening-\(theme)-L")
            app.tapCoordinate(x: 0.5, y: 0.5)
            XCTAssertEqual(app.staticTexts["quran-mushaf-number"].label, "الوجه ١٢٨")
            app.buttons["quran-mushaf-ayahs"].tap()
            let verse = app.descendants(matching: .any)["quran-tafsir-ayah-title"]
            XCTAssertTrue(verse.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(verse.label.contains("سورة الأن") && verse.label.contains("الآية ١"), verse.label)
            app.terminate()
        }
    }

    func testOriginalPageToolsPagingZoomAndSemanticAyahAtDefaultSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-15T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 20))
        let entry = app.buttons["quran-tool-mushaf"]
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        let page = app.descendants(matching: .any)["quran-mushaf-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quran-mushaf-close"].exists)
        attach(app, "M2-V06-mushaf-L")
        app.tapCoordinate(x: 0.5, y: 0.5)
        XCTAssertTrue(app.buttons["quran-mushaf-next"].waitForExistence(timeout: 5))
        // The fixture's opening face moved with its clock (it opened on 284, not the recorded 285): turning is checked relatively.
        let opening = app.staticTexts["quran-mushaf-number"].label
        XCTAssertTrue(opening.hasPrefix("الوجه "), opening)
        app.buttons["quran-mushaf-next"].tap()
        // B1-4: the page on screen stays until the next one is ready, so turning never blanks the sheet.
        XCTAssertTrue(page.exists, "The mushaf page vanished while turning")
        let turned = NSPredicate(format: "label != %@", opening)
        expectation(for: turned, evaluatedWith: app.staticTexts["quran-mushaf-number"]); waitForExpectations(timeout: 10)
        app.buttons["quran-mushaf-previous"].tap()
        app.buttons["quran-mushaf-zoom"].tap()
        XCTAssertEqual(app.buttons["quran-mushaf-zoom"].label, "الحجم الطبيعي")
        app.buttons["quran-mushaf-zoom"].tap()
        attach(app, "M2-V06-tools-L")
        app.buttons["quran-mushaf-ayahs"].tap()
        let verse = app.descendants(matching: .any)["quran-tafsir-ayah-title"]
        XCTAssertTrue(verse.waitForExistence(timeout: 5)); XCTAssertTrue(verse.label.contains("الآية"), verse.label)
        let firstVerse = verse.label
        attach(app, "M2-V06-ayah-L")
        app.buttons["quran-tafsir-next"].tap()
        XCTAssertTrue(verse.waitForExistence(timeout: 5)); XCTAssertNotEqual(verse.label, firstVerse)
        app.buttons["quran-tafsir-close"].tap()
        app.tapCoordinate(x: 0.5, y: 0.5)
        app.buttons["quran-mushaf-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quran-resume"].exists)
        app.terminate()
    }

    func testFailedTurnKeepsVisibleFaceAndRetriesRequestedPage() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_ROUTE": "madar://quran/page/128", "MADAR_UI_QURAN_MUSHAF_FAIL_PAGE_ONCE": "129"
        ]
        app.launch()
        let face = app.descendants(matching: .any)["quran-mushaf-page"]
        XCTAssertTrue(face.waitForExistence(timeout: 25), app.debugDescription)
        app.tapCoordinate(x: 0.5, y: 0.5)

        let title = app.staticTexts["quran-mushaf-number"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "الوجه ١٢٨")
        app.buttons["quran-mushaf-next"].tap()

        let error = app.staticTexts["quran-mushaf-read-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("١٢٩"), error.label)
        XCTAssertTrue(face.exists)
        XCTAssertEqual(title.label, "الوجه ١٢٨")
        XCTAssertTrue(app.buttons["quran-mushaf-close"].isHittable)
        attach(app, "mushaf-page-turn-failure")

        app.buttons["quran-mushaf-retry"].tap()
        expectation(for: NSPredicate(format: "label == %@", "الوجه ١٢٩"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(error.exists)
        XCTAssertTrue(face.exists)
        app.terminate()
    }

    func testLandscapeMushafTurnsOnlyToAnotherVisiblePageOrSpread() {
        continueAfterFailure = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        for openingFirstSpread in [true, false] {
            let app = XCUIApplication()
            let pageNumber = openingFirstSpread ? 2 : 603
            app.launchEnvironment = [
                "MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
                "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
                "MADAR_UI_QURAN_ROUTE": "madar://quran/page/\(pageNumber)"
            ]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["quran-mushaf-page"].waitForExistence(timeout: 25), app.debugDescription)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(window.width, window.height)
            app.tapCoordinate(x: isPad ? 0.65 : 0.5, y: 0.5)

            let previous = app.buttons["quran-mushaf-previous"]
            let next = app.buttons["quran-mushaf-next"]
            let title = app.staticTexts["quran-mushaf-number"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertEqual(title.label, openingFirstSpread ? "الوجه ٢" : "الوجه ٦٠٣")
            let outward = openingFirstSpread ? previous : next
            let inward = openingFirstSpread ? next : previous
            XCTAssertEqual(outward.isEnabled, !isPad, "A spread at the edge of the mushaf has no outward turn")
            XCTAssertTrue(inward.isEnabled)
            if isPad { inward.tap() } else { outward.tap() }

            let expectedTitle: String
            if openingFirstSpread { expectedTitle = isPad ? "الوجه ٤" : "الوجه ١" }
            else { expectedTitle = isPad ? "الوجه ٦٠١" : "الوجه ٦٠٤" }
            expectation(for: NSPredicate(format: "label == %@", expectedTitle), evaluatedWith: title)
            waitForExpectations(timeout: 10)
            app.terminate()
        }
    }

    func testBookmarkNamesItsFaceAndReturnsThereAfterTurning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_ROUTE": "madar://quran/page/128"
        ]
        app.launch()
        let face = app.descendants(matching: .any)["quran-mushaf-page"]
        XCTAssertTrue(face.waitForExistence(timeout: 25), app.debugDescription)
        app.tapCoordinate(x: 0.5, y: 0.5)

        let title = app.staticTexts["quran-mushaf-number"]
        expectation(for: NSPredicate(format: "label == %@", "الوجه ١٢٨"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
        let menu = app.buttons["quran-mushaf-bookmarks"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        menu.tap()
        let add = app.descendants(matching: .any)["علامة على هذا الوجه"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription)
        add.tap()

        let naming = app.alerts["اسم العلامة"]
        XCTAssertTrue(naming.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(naming.textFields.firstMatch.value as? String, "علامة ١٢٨", naming.debugDescription)
        attach(app, "mushaf-bookmark-face-128")
        naming.buttons["احفظ"].tap()
        expectation(for: NSPredicate(format: "value == %@", "هذا الموضع معلَّم"), evaluatedWith: menu)
        waitForExpectations(timeout: 10)

        app.buttons["quran-mushaf-next"].tap()
        expectation(for: NSPredicate(format: "label != %@", "الوجه ١٢٨"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
        menu.tap()
        let target = app.descendants(matching: .any)["علامة ١٢٨، الوجه ١٢٨"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        target.tap()
        expectation(for: NSPredicate(format: "label == %@", "الوجه ١٢٨"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
    }

    func testLandscapePadCanBookmarkEitherFace() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-24T15:00:00+03:00", "MADAR_UI_QURAN_FIXTURE": "home",
            "MADAR_UI_QURAN_ROUTE": "madar://quran/page/128"
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["quran-mushaf-page"].waitForExistence(timeout: 25))
        app.tapCoordinate(x: 0.65, y: 0.5)
        let menu = app.buttons["quran-mushaf-bookmarks"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let right = app.descendants(matching: .any)["علامة على الوجه ١٢٧"].firstMatch
        let left = app.descendants(matching: .any)["علامة على الوجه ١٢٨"].firstMatch
        XCTAssertTrue(right.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(left.exists, app.debugDescription)
        attach(app, "mushaf-two-face-bookmarks-pad")
        right.tap()

        let naming = app.alerts["اسم العلامة"]
        XCTAssertTrue(naming.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(naming.textFields.firstMatch.value as? String, "علامة ١٢٧")
        naming.buttons["احفظ"].tap()
        expectation(for: NSPredicate(format: "value == %@", "هذا الموضع معلَّم"), evaluatedWith: menu)
        waitForExpectations(timeout: 10)

        app.buttons["quran-mushaf-next"].tap()
        let title = app.staticTexts["quran-mushaf-number"]
        expectation(for: NSPredicate(format: "label == %@", "الوجه ١٣٠"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
        menu.tap()
        let bookmark = app.descendants(matching: .any)["علامة ١٢٧، الوجه ١٢٧"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5), app.debugDescription)
        bookmark.tap()
        expectation(for: NSPredicate(format: "label == %@", "الوجه ١٢٧"), evaluatedWith: title)
        waitForExpectations(timeout: 10)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = app.screenshot(), shot = XCTAttachment(screenshot: image)
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
private extension XCUIApplication {
    func tapCoordinate(x: CGFloat, y: CGFloat) { coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap() }
}
