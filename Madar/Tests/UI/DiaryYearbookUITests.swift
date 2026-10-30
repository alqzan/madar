import XCTest
@MainActor final class DiaryYearbookUITests:XCTestCase {
    func testActualPreviewOptionsPrepareAndReadBook() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout:25));app.buttons["diary-days"].tap()
        let book=app.buttons["diary-yearbook"];for _ in 0..<4 where !book.isHittable{app.swipeUp()};book.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-book-cover").firstMatch.waitForExistence(timeout:10));capture(app,"M3-V11-book-L")
        let yearPicker=app.buttons["diary-book-year"];yearPicker.tap()
        let pairedYears=app.buttons.matching(NSPredicate(format:"label CONTAINS 'هـ' AND label CONTAINS ' م'"))
        let pairedYear=try XCTUnwrap(pairedYears.allElementsBoundByIndex.first(where:{$0.isHittable}),app.debugDescription)
        capture(app,"M3-V11-year-options-L");pairedYear.tap()
        let prepare=app.buttons["diary-book-prepare"];for _ in 0..<5 where !prepare.isHittable{app.swipeUp()};capture(app,"M3-V11-book-s1-L");prepare.tap()
        let read=app.buttons["diary-book-preview"];XCTAssertTrue(read.waitForExistence(timeout:15));for _ in 0..<4 where !read.isHittable{app.swipeUp()};read.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout:10));capture(app,"M3-V11-pdf-L");app.navigationBars.buttons["تم"].tap()
        let photos=app.switches["diary-book-photos"];for _ in 0..<4 where !photos.isHittable{app.swipeDown()};photos.tap();XCTAssertFalse(read.exists)
    }
    func testYearbookFailedReloadDropsOldPagesAndCanRetry() throws {
        continueAfterFailure = false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor",
            "MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00",
            "MADAR_UI_DIARY_YEARBOOK_READ_FAILURE_AFTER_FIRST":"1"]
        app.launch();XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout:25));app.buttons["diary-days"].tap()
        let book=app.buttons["diary-yearbook"];for _ in 0..<4 where !book.isHittable{app.swipeUp()};book.tap()
        XCTAssertTrue(app.staticTexts["diary-book-error"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.buttons["diary-book-retry"].waitForExistence(timeout:5),app.debugDescription)
        capture(app,"AU-95-yearbook-read-failure-L")
        app.buttons["diary-book-retry"].tap()
        let prepare=app.buttons["diary-book-prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout:10),app.debugDescription)
        let enabled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:prepare)
        XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:10),.completed,app.debugDescription)
        capture(app,"AU-95-yearbook-read-recovered-L")
        app.terminate()
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
