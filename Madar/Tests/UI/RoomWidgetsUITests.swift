import XCTest
@MainActor final class RoomWidgetsUITests:XCTestCase {
    private func openGallery()->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_HABIT_FIXTURE":"showcase","MADAR_UI_NOW":"2026-10-15T20:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["خصّص"].waitForExistence(timeout:20));app.tabBars.buttons["خصّص"].tap()
        let search=app.textFields["settings-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("خارج التطبيق")
        let gallery=app.buttons["room-widgets-gallery"];XCTAssertTrue(gallery.waitForExistence(timeout:10));gallery.tap()
        XCTAssertTrue(app.staticTexts["room-widgets-title"].waitForExistence(timeout:10));return app
    }
    private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testDefaultRoomPreviewsAndDirectDiaryWriting() throws {
        continueAfterFailure=false;let app=openGallery();shot(app,"M4-W01-X1-Raisiya-L")
        app.swipeUp(velocity:.slow);shot(app,"M4-W01-X1-Raisiya-s1-L")
        let write=app.buttons["room-widget-diaryWrite"]
        for _ in 0..<3 where !write.isHittable{app.swipeUp(velocity:.slow)}
        XCTAssertTrue(write.exists);write.tap()
        XCTAssertTrue(app.textViews["diary-editor-text"].waitForExistence(timeout:10))
    }
    /// RD7: turning on «محتوى المذكرات في الودجات» adds the memory and last-line templates.
    func testDiaryContentWidgetsAppearOnlyAfterTheOptIn() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"home","MADAR_UI_NOW":"2026-10-15T20:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"];app.launch()
        // The opt-in lives in the diary's own «خصّص المذكرات», section «خارج التطبيق»; the off-by-default gallery is covered by RoomWidgetSnapshotTests.
        let customize=app.buttons["diary-customize"];XCTAssertTrue(customize.waitForExistence(timeout:25));customize.tap()
        let diarySearch=app.textFields["diary-customize-search"];XCTAssertTrue(diarySearch.waitForExistence(timeout:10));diarySearch.tap();diarySearch.typeText("الودجات")
        let toggle=app.switches["setting-notes.widgetContent"];XCTAssertTrue(toggle.waitForExistence(timeout:10))
        if toggle.switches.firstMatch.exists{toggle.switches.firstMatch.tap()}else{toggle.tap()}
        XCTAssertEqual(toggle.value as? String,"1")
        shot(app,"M3-V16-diary-setting-L")
        app.buttons["diary-customize-back"].tap()
        XCTAssertTrue(app.tabBars.buttons["خصّص"].waitForExistence(timeout:10));app.tabBars.buttons["خصّص"].tap()
        let search=app.textFields["settings-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("خارج التطبيق")
        let gallery=app.buttons["room-widgets-gallery"];XCTAssertTrue(gallery.waitForExistence(timeout:10));gallery.tap();XCTAssertTrue(app.staticTexts["room-widgets-title"].waitForExistence(timeout:10))
        let last=app.buttons["room-widget-diary-lastLine"]
        for _ in 0..<4 where !last.isHittable{app.swipeUp(velocity:.slow)}
        XCTAssertTrue(last.exists);XCTAssertTrue(app.buttons["room-widget-diary-thatDay"].exists)
        shot(app,"M3-V16-diary-widgets-L")
    }
    func testLockStandByAndControlPreviewsOpenHabits() throws {
        continueAfterFailure=false;let app=openGallery()
        let link=app.buttons["room-widgets-lock"];XCTAssertTrue(link.waitForExistence(timeout:5));link.tap()
        XCTAssertTrue(app.staticTexts["lock-widgets-title"].waitForExistence(timeout:5));shot(app,"M4-W02-X2-Qifl-L")
        app.swipeUp(velocity:.slow);shot(app,"M4-W02-X2-Qifl-s1-L")
        let habits=app.buttons["control-preview-habits"]
        for _ in 0..<3 where !habits.isHittable{app.swipeUp(velocity:.slow)}
        XCTAssertTrue(habits.exists);habits.tap()
        XCTAssertTrue(app.staticTexts["habits-title"].waitForExistence(timeout:10))
    }
    func testPrayerWidgetPreviewOpensPrayerDirectly() throws {
        continueAfterFailure=false;let app=openGallery();app.buttons["room-widget-prayer"].tap()
        XCTAssertTrue(app.staticTexts["room-widgets-title"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.tabBars.buttons["الصلاة"].isSelected)
    }
    func testMihbaraWidgetPreviewOpensRoomDirectly() throws {
        continueAfterFailure=false;let app=openGallery(),mihbara=app.buttons["room-widget-mihbara"]
        for _ in 0..<5 where !mihbara.isHittable{app.swipeUp(velocity:.slow)}
        XCTAssertTrue(mihbara.waitForExistence(timeout:10));shot(app,"M6-X01-mihbara-widget-L");mihbara.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout:10),app.debugDescription)
        shot(app,"M6-X01-mihbara-open-L")
    }
    func testMihbaraControlPreviewOpensRoom() throws {
        continueAfterFailure=false;let app=openGallery()
        app.buttons["room-widgets-lock"].tap();XCTAssertTrue(app.staticTexts["lock-widgets-title"].waitForExistence(timeout:8))
        let control=app.buttons["control-preview-mihbara"]
        for _ in 0..<5 where !control.isHittable{app.swipeUp(velocity:.slow)}
        XCTAssertTrue(control.waitForExistence(timeout:10));shot(app,"M6-X01-control-preview-L");control.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout:10),app.debugDescription)
        shot(app,"M6-X01-mihbara-from-control-L")
    }
    func testMihbaraDiaryLineTogglePersists() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"home","MADAR_UI_NOW":"2026-10-15T20:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"];app.launch()
        let customize=app.buttons["diary-customize"];XCTAssertTrue(customize.waitForExistence(timeout:25));customize.tap()
        let search=app.textFields["diary-customize-search"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("سطور الأقسام")
        let toggle=app.switches["diary-auto-mihbara"];XCTAssertTrue(toggle.waitForExistence(timeout:10));XCTAssertEqual(toggle.value as? String,"1")
        toggle.tap();XCTAssertEqual(toggle.value as? String,"0");shot(app,"M6-X01-diary-auto-line-L")
        app.buttons["diary-customize-back"].tap();XCTAssertTrue(app.buttons["diary-customize"].waitForExistence(timeout:10));app.buttons["diary-customize"].tap()
        let reopenedSearch=app.textFields["diary-customize-search"];XCTAssertTrue(reopenedSearch.waitForExistence(timeout:10));reopenedSearch.tap();reopenedSearch.typeText("سطور الأقسام")
        XCTAssertEqual(app.switches["diary-auto-mihbara"].value as? String,"0")
    }
}
