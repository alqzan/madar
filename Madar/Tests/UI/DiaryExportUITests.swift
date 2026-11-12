import XCTest
@MainActor final class DiaryExportUITests:XCTestCase {
    func testPreparePreviewCloseChangeFormatAndShare() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout:25));app.buttons["diary-days"].tap()
        app.buttons["diary-hub-more"].tap();let open=app.buttons["diary-export"];open.tap()
        XCTAssertTrue(app.buttons["diary-export-prepare"].waitForExistence(timeout:10));capture(app,"M3-V10-export-L")
        let yearPicker=app.buttons["diary-export-year"];yearPicker.tap()
        let pairedYears=app.buttons.matching(NSPredicate(format:"label CONTAINS 'هـ' AND label CONTAINS ' م'"))
        let pairedYear=try XCTUnwrap(pairedYears.allElementsBoundByIndex.first(where:{$0.isHittable}),app.debugDescription)
        capture(app,"M3-V10-year-options-L");pairedYear.tap()
        XCTAssertTrue(yearPicker.label.contains("هـ") && yearPicker.label.contains(" م"),yearPicker.label)
        app.buttons["diary-export-prepare"].tap()
        let preview=app.buttons["diary-export-preview"];XCTAssertTrue(preview.waitForExistence(timeout:15));for _ in 0..<4 where !preview.isHittable {app.swipeUp()};capture(app,"M3-V10-ready-L");preview.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout:10));capture(app,"M3-V10-pdf-L");app.navigationBars.buttons["تم"].tap()
        let format=app.buttons["diary-export-format-markdown"];for _ in 0..<4 where !format.isHittable{app.swipeDown()};format.tap();XCTAssertFalse(app.buttons["diary-export-preview"].exists)
        let prepare=app.buttons["diary-export-prepare"];for _ in 0..<4 where !prepare.isHittable{app.swipeUp()};prepare.tap()
        let share=app.buttons["diary-export-share"];XCTAssertTrue(share.waitForExistence(timeout:15));for _ in 0..<4 where !share.isHittable{app.swipeUp()};share.tap()
        XCTAssertTrue(app.cells.matching(NSPredicate(format:"label IN %@",["Copy","نسخ","Save to Files","حفظ في الملفات"])).firstMatch.waitForExistence(timeout:10));capture(app,"M3-V10-share-L")
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
