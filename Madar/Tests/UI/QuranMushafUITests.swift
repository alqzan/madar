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
            let verse = app.staticTexts["quran-mushaf-semantic-ayah"]
            XCTAssertTrue(verse.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(verse.label.hasPrefix("ٱلۡحَمۡدُ لِلَّهِ"), verse.label)
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
        XCTAssertEqual(app.staticTexts["quran-mushaf-number"].label, "الوجه ٢٨٥")
        app.buttons["quran-mushaf-next"].tap()
        XCTAssertTrue(app.staticTexts["quran-mushaf-number"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["quran-mushaf-number"].label, "الوجه ٢٨٦")
        app.buttons["quran-mushaf-previous"].tap()
        app.buttons["quran-mushaf-zoom"].tap()
        XCTAssertEqual(app.buttons["quran-mushaf-zoom"].label, "الحجم الطبيعي")
        app.buttons["quran-mushaf-zoom"].tap()
        attach(app, "M2-V06-tools-L")
        app.buttons["quran-mushaf-ayahs"].tap()
        let verse = app.staticTexts["quran-mushaf-semantic-ayah"]
        XCTAssertTrue(verse.waitForExistence(timeout: 5)); XCTAssertTrue(verse.label.contains("وَإِمَّا"))
        attach(app, "M2-V06-ayah-L")
        app.buttons["التالية"].tap()
        XCTAssertTrue(verse.label.contains("وَلَا"))
        app.buttons["تمّ"].tap()
        app.buttons["quran-mushaf-close"].tap()
        XCTAssertTrue(app.staticTexts["quran-coverage-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quran-resume"].exists)
        app.terminate()
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
