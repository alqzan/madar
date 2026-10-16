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
    func testPrayerWidgetPreviewOpensPrayerDirectly() throws {
        continueAfterFailure=false;let app=openGallery();app.buttons["room-widget-prayer"].tap()
        XCTAssertTrue(app.staticTexts["room-widgets-title"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.tabBars.buttons["الصلاة"].isSelected)
    }
}
