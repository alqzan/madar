import XCTest
import UIKit

@MainActor final class MihbaraImportUITests: XCTestCase {
    func testScannedPDFPreviewRequiresConfirmationAndImportCanBeUndone() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { canvas in
            UIColor.brown.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            for _ in 0..<2 { canvas.beginPage(); image.draw(in: CGRect(x: 20, y: 20, width: 250, height: 350)) }
        }
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString()]
        app.launch()
        let customize = app.tabBars.buttons["خصّص"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["PDF مصوّر"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لا توجد طبقة نص")).firstMatch.exists)
        attach(app, "M6-V17-preview-L")
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(confirm.isHittable)
        let title = app.textFields["mihbara-import-title"]
        XCTAssertEqual(title.value as? String, "ملف اختبار مصوّر")
        attach(app, "M6-V17-preview-s1-L")
        confirm.tap()
        let addBook = app.buttons["mihbara-add-paper"]
        let addBookVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addBook)
        XCTAssertEqual(XCTWaiter.wait(for: [addBookVisible], timeout: 15), .completed, app.debugDescription)
        addBook.tap()
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["mihbara-import-reopen"].exists)
        app.buttons["mihbara-add-back"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        XCTAssertTrue(app.staticTexts["ملف اختبار مصوّر"].firstMatch.waitForExistence(timeout: 8))
        let undo = app.descendants(matching: .any)["mihbara-undo"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8)); undo.tap()
        XCTAssertFalse(app.staticTexts["ملف اختبار مصوّر"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].exists)
    }

    func testEPUBPreviewUsesFileMetadataAndAddsAnOfflineBook() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let bytes = try Data(contentsOf: fixture)
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_EPUB": bytes.base64EncodedString()]
        app.launch()
        let customize = app.tabBars.buttons["خصّص"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 25), app.debugDescription)
        let title = app.textFields["mihbara-epub-import-title"]
        XCTAssertEqual(title.value as? String, "A Book About Reading")
        XCTAssertEqual(app.textFields["mihbara-epub-import-author"].value as? String, "Madar Fixture Author")
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-import-toc-10"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "حواشٍ")).firstMatch.exists)
        attach(app, "M6-V19-epub-preview-L")
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(confirm.isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-epub-shelf-want"].isSelected)
        attach(app, "M6-V19-epub-preview-s1-L")
        app.buttons["mihbara-epub-import-back"].tap()
        let reopen = app.buttons["mihbara-import-reopen"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 8), app.debugDescription)
        reopen.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        confirm.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 15), app.debugDescription)
        wantShelf.tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A Book About Reading")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription)
        imported.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["mihbara-reader-close"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
