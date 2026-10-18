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
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["mihbara-shelf-want"].tap()
        XCTAssertTrue(app.staticTexts["ملف اختبار مصوّر"].firstMatch.waitForExistence(timeout: 8))
        let undo = app.descendants(matching: .any)["mihbara-undo"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8)); undo.tap()
        XCTAssertFalse(app.staticTexts["ملف اختبار مصوّر"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].exists)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
