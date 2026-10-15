import XCTest
@MainActor final class DiaryYearbookUITests:XCTestCase {
    func testActualPreviewOptionsPrepareAndReadBook() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchEnvironment=["MADAR_UI_STORE_ID":UUID().uuidString,"MADAR_UI_DIARY_FIXTURE":"editor","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light","MADAR_UI_NOW":"2026-10-15T15:00:00+03:00"]
        app.launch();XCTAssertTrue(app.buttons["diary-days"].waitForExistence(timeout:25));app.buttons["diary-days"].tap()
        let book=app.buttons["diary-yearbook"];for _ in 0..<4 where !book.isHittable{app.swipeUp()};book.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"diary-book-cover").firstMatch.waitForExistence(timeout:10));capture(app,"M3-V11-book-L")
        let prepare=app.buttons["diary-book-prepare"];for _ in 0..<5 where !prepare.isHittable{app.swipeUp()};capture(app,"M3-V11-book-s1-L");prepare.tap()
        let read=app.buttons["diary-book-preview"];XCTAssertTrue(read.waitForExistence(timeout:15));for _ in 0..<4 where !read.isHittable{app.swipeUp()};read.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout:10));capture(app,"M3-V11-pdf-L");app.navigationBars.buttons["تم"].tap()
        let photos=app.switches["diary-book-photos"];for _ in 0..<4 where !photos.isHittable{app.swipeDown()};photos.tap();XCTAssertFalse(read.exists)
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
