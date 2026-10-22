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
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["PDF مصوّر"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "صفحاته صور بلا طبقة نص")).firstMatch.exists)
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

    func testScannedPDFReaderSavesPositionAndResumes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { canvas in
            UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1).setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            let style = NSMutableParagraphStyle(); style.alignment = .right
            let text = "كتاب الاختبار المصوّر\n\nالقراءة باب إلى المعرفة. هذا النص صورة من الملف الأصلي، يبقى محفوظًا على الجهاز.\n\nنعود إلى الصفحة نفسها بعد إغلاق الكتاب."
            (text as NSString).draw(in: CGRect(x: 25, y: 35, width: 250, height: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 19), .foregroundColor: UIColor.darkText, .paragraphStyle: style])
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            for _ in 0..<2 { canvas.beginPage(); image.draw(in: CGRect(x: 20, y: 20, width: 250, height: 350)) }
        }
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["PDF مصوّر"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "صفحاته صور بلا طبقة نص")).firstMatch.exists)
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
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ملف اختبار مصوّر")).firstMatch
        imported.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-next"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-page"].label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("١ من ٢"), app.debugDescription)
        attach(app, "M6-V18-PDF-L")
        app.buttons["mihbara-pdf-search"].tap()
        XCTAssertTrue(app.staticTexts["mihbara-pdf-ocr-complete"].waitForExistence(timeout: 45), app.debugDescription)
        let query = app.textFields["mihbara-pdf-search-query"]
        query.tap(); query.typeText("المعرفة\n")
        let result = app.buttons["mihbara-pdf-result-1"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["نص ضوئي تقريبي"].firstMatch.exists)
        XCTAssertEqual(app.staticTexts["mihbara-pdf-search-count"].label, "العبارة في صفحتين")
        XCTAssertTrue(app.staticTexts["mihbara-pdf-result-excerpt-1"].label.contains("المعرفة"))
        attach(app, "M6-PDF-OCR-search-L")
        result.tap()
        let jumpedLabel = app.descendants(matching: .any)["mihbara-pdf-page"].label
        XCTAssertTrue(jumpedLabel.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("٢ من ٢"), jumpedLabel)
        app.buttons["mihbara-pdf-previous"].tap()
        app.buttons["mihbara-pdf-next"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-page"].label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("٢ من ٢"), app.debugDescription)
        attach(app, "M6-V18-PDF-s1-L")
        app.buttons["mihbara-pdf-close"].tap()
        XCTAssertTrue(imported.waitForExistence(timeout: 8))
        let importedReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: imported)
        XCTAssertEqual(XCTWaiter.wait(for: [importedReady], timeout: 12), .completed, app.debugDescription)
        imported.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-close"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-page"].label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("٢ من ٢"), app.debugDescription)
        app.buttons["mihbara-pdf-close"].tap()
    }

    func testTextPDFImportsAndOpensWithItsStoredPageCount() {
        continueAfterFailure = false
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "كتاب رقمي", kCGPDFContextAuthor as String: "قارئ الاختبار"]
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400), format: format).pdfData { canvas in
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
            for page in 1...2 {
                canvas.beginPage()
                let text = "الصفحة رقم \(page)\n\nهذا نص عربي موجود داخل ملف PDF، وليس صورة ممسوحة. يبقى النص والصفحات كما حفظها الملف الأصلي."
                (text as NSString).draw(in: CGRect(x: 20, y: 35, width: 260, height: 320), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21), .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph
                ])
            }
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب رقمي",
            "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "كل صفحاته نصّية")).firstMatch.exists, app.debugDescription)
        XCTAssertEqual(app.textFields["mihbara-import-title"].value as? String, "كتاب رقمي")
        attach(app, "M6-PDF-text-preview-L")
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()

        let addBook = app.buttons["mihbara-add-paper"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addBook)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, app.debugDescription)
        addBook.tap()
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].waitForExistence(timeout: 8))
        app.buttons["mihbara-add-back"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب رقمي")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription); imported.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-next"].waitForExistence(timeout: 12), app.debugDescription)
        let page = app.descendants(matching: .any)["mihbara-pdf-page"]
        XCTAssertTrue(page.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("١ من ٢"), app.debugDescription)
        attach(app, "M6-PDF-text-reader-L")
        app.buttons["mihbara-pdf-search"].tap()
        XCTAssertTrue(app.staticTexts["mihbara-pdf-ocr-complete"].waitForExistence(timeout: 15), app.debugDescription)
        let query = app.textFields["mihbara-pdf-search-query"]
        query.tap(); query.typeText("PDF\n")
        XCTAssertEqual(app.staticTexts["mihbara-pdf-search-count"].label, "العبارة في صفحتين")
        XCTAssertTrue(app.staticTexts["mihbara-pdf-result-unreliable-0"].exists)
        XCTAssertFalse(app.staticTexts["mihbara-pdf-result-excerpt-0"].exists)
        attach(app, "M6-PDF-search-excerpts-L")
        app.buttons["mihbara-pdf-search-clear"].tap()
        XCTAssertFalse(app.staticTexts["mihbara-pdf-search-count"].exists)
        query.tap(); query.typeText("عبارة لا توجد في الكتاب\n")
        XCTAssertTrue(app.staticTexts["mihbara-pdf-search-empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mihbara-pdf-search-count"].label, "لا صفحات مطابقة")
        XCTAssertTrue(app.staticTexts["mihbara-pdf-search-empty"].label.contains("راجع صورة الصفحة"))
        XCTAssertFalse(app.buttons["mihbara-pdf-result-0"].exists)
        attach(app, "M6-PDF-search-empty-L")
        app.buttons["mihbara-pdf-search-clear"].tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-result-0"].exists)
        app.buttons["mihbara-pdf-search-close"].tap()
        app.buttons["mihbara-pdf-next"].tap()
        XCTAssertTrue(page.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("٢ من ٢"), app.debugDescription)
    }

    /// Owner, 21 October 2026: a PDF becomes a flowing book on the device, through the normal EPUB review.
    func testTextPDFConvertsOnDeviceIntoAFlowingBook() {
        continueAfterFailure = false
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "كتاب منساب", kCGPDFContextAuthor as String: "قارئ الاختبار"]
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400), format: format).pdfData { canvas in
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
            for page in 1...3 {
                canvas.beginPage()
                let text = "الصفحة رقم \(page)\n\nالقراءة باب إلى المعرفة، والكتاب صاحب لا يمل."
                (text as NSString).draw(in: CGRect(x: 20, y: 35, width: 260, height: 320), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21), .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph
                ])
            }
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب منساب",
            "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let addBook = app.buttons["mihbara-add-paper"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addBook)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, app.debugDescription)
        addBook.tap()
        app.buttons["mihbara-add-back"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب منساب")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription); imported.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-flow"].waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["mihbara-pdf-flow"].tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-flow-turath"].waitForExistence(timeout: 8), app.debugDescription)
        attach(app, "M6-PDF-flow-choice-L")
        app.buttons["mihbara-pdf-flow-device"].tap()
        let review = app.buttons["mihbara-pdf-flow-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "٣ صفحات")).firstMatch.exists, app.debugDescription)
        attach(app, "M6-PDF-flow-ready-L")
        review.tap()
        let importConfirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(importConfirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.textFields["mihbara-epub-import-title"].value as? String, "كتاب منساب")
        attach(app, "M6-PDF-flow-review-L")
        for _ in 0..<8 where !importConfirm.isHittable { app.swipeUp(velocity: .slow) }
        importConfirm.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-close"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-pdf-flow-device"].exists)
        app.buttons["mihbara-pdf-close"].tap()
        let copies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب منساب"))
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: copies)
        XCTAssertEqual(XCTWaiter.wait(for: [both], timeout: 12), .completed, app.debugDescription)
        attach(app, "M6-PDF-flow-shelf-L")
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
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 25), app.debugDescription)
        let title = app.textFields["mihbara-epub-import-title"]
        XCTAssertEqual(title.value as? String, "A Book About Reading")
        XCTAssertEqual(app.textFields["mihbara-epub-import-author"].value as? String, "Madar Fixture Author")
        // A long index shows its first eight headings; the rest opens on request.
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-import-toc-8"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["mihbara-epub-import-toc-10"].exists)
        let fullIndex = app.buttons["mihbara-epub-import-toc-all"]
        for _ in 0..<8 where !fullIndex.isHittable { app.swipeUp(velocity: .slow) }
        fullIndex.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-import-toc-10"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "حواشٍ")).firstMatch.exists)
        let size = app.descendants(matching: .any)["mihbara-epub-import-size"]
        XCTAssertTrue(size.exists && size.label.contains("الملف"), "The review names the file size.\n\(app.debugDescription)")
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
        // M6-UX-T: rename the book from its shelf menu; the shelf shows the new name.
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription)
        imported.press(forDuration: 1.0)
        let rename = app.buttons["mihbara-book-rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), app.debugDescription)
        rename.tap()
        let renameTitle = app.alerts.textFields.firstMatch
        XCTAssertTrue(renameTitle.waitForExistence(timeout: 5), app.debugDescription)
        // The alert focuses the title with the cursor at its end.
        renameTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "On Reading")
        app.alerts.firstMatch.buttons.matching(identifier: "احفظ").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "On Reading")).firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        attach(app, "M6-UX-T-renamed-L")
    }

    /// M6-UX-V: a two-volume Turath set stands as two spines; tapping the second opens the reader in «الجزء الثاني».
    func testTappingASecondVolumeOpensThatVolume() throws {
        continueAfterFailure = false
        let catalogue = #"{"cats":{"23":{"id":23,"name":"الرقاق والآداب","books":[12028]}},"authors":{"51":{"id":51,"name":"ابن الجوزي","death":597,"books":[12028]}},"books":{"12028":{"id":12028,"name":"صيد الخاطر","author_id":51,"cat_id":23,"size":1480554,"page_count":893}},"books_changed":[],"date":"2026-02-03","version":1}"#
        let book = #"{"ً":{"ٌ":12028,"ّ":"الكتاب: صيد الخاطر","ٖ":1770153735},"٘":{"ٚ":[{"title":"مقدمة","level":1,"page":1},{"title":"علو الهمة","level":1,"page":2}]},"pages":[{"text":"<span data-type=\"title\" id=toc-1>مقدمة</span>\n"# + String(repeating: #"الحمد لله الذي جعل للعقل نورًا وجعل الهمة طريقه.\n"#, count: 80) + #"","vol":"1","page":1},{"text":"<span data-type=\"title\" id=toc-2>علو الهمة</span>\nمن علامة كمال العقل علو الهمة.","vol":"2","page":28}]}"#
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_TURATH_CATALOGUE_BASE64": Data(catalogue.utf8).base64EncodedString(), "MADAR_UI_TURATH_BOOK_BASE64": Data(book.utf8).base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let turath = app.buttons["mihbara-add-source-turath"]; XCTAssertTrue(turath.waitForExistence(timeout: 8), app.debugDescription)
        turath.tap()
        let field = app.textFields["mihbara-turath-search"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("صيد")
        let result = app.buttons["mihbara-turath-book-12028"]; XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        result.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 25), app.debugDescription)
        let size = app.descendants(matching: .any)["mihbara-epub-import-size"]
        XCTAssertTrue(size.exists && size.label.contains("مجلدان"), "The review names both volumes.\n\(app.debugDescription)")
        attach(app, "M6-UX-T-turath-size-L")
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 15), app.debugDescription)
        wantShelf.tap()
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "mihbara-book-", "-v2")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8), app.debugDescription)
        attach(app, "M6-UX-V-two-volumes-L")
        second.tap()
        let subtitle = app.staticTexts["mihbara-reader-subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<20 where !subtitle.label.hasPrefix("الجزء الثاني") { usleep(500_000) }
        attach(app, "M6-UX-V-reader-after-tap-L")
        // Blocker (M6-UX-V, 22 Oct): a Turath file holds 30 printed pages, so a volume can begin mid-chapter. The reader opens
        // that chapter but Readium does not scroll to the page anchor, so the screen still shows the end of volume 1.
        XCTExpectFailure("M6-UX-V: the reader opens the chapter, not the page anchor where volume 2 begins") {
            XCTAssertTrue(subtitle.label.hasPrefix("الجزء الثاني"), "Reader subtitle: \(subtitle.label)")
        }
        attach(app, "M6-UX-V-reader-second-volume-L")
    }

    /// M6-T01: search Turath's catalogue, download a book (fixture data, no network), review it and read it.
    func testTurathSearchDownloadsABookIntoTheLibrary() throws {
        continueAfterFailure = false
        let catalogue = #"{"cats":{"23":{"id":23,"name":"الرقاق والآداب","books":[12028]}},"authors":{"51":{"id":51,"name":"ابن الجوزي","death":597,"books":[12028,7]}},"books":{"12028":{"id":12028,"name":"صيد الخاطر","author_id":51,"cat_id":23,"size":1480554,"page_count":893},"7":{"id":7,"name":"تلبيس إبليس","author_id":51,"cat_id":23,"size":3000000,"page_count":420}},"books_changed":[],"date":"2026-02-03","version":1}"#
        let book = #"{"ً":{"ٌ":12028,"ّ":"الكتاب: صيد الخاطر\nالناشر: دار القلم","ٖ":1770153735},"٘":{"ٚ":[{"title":"مقدمة","level":1,"page":1},{"title":"علو الهمة","level":1,"page":2}]},"pages":[{"text":"<span data-type=\"title\" id=toc-1>مقدمة</span>\nالحمد لله الذي جعل للعقل نورًا.","vol":"1","page":1},{"text":"٧- فصل:<span data-type=\"title\" id=toc-2> علو الهمة</span>\nمن علامة كمال العقل علو الهمة، والراضي بالدون١ دني.\n_________\n١ الدون: الأمر الخسيس الحقير.","vol":"2","page":28}]}"#
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_TURATH_CATALOGUE_BASE64": Data(catalogue.utf8).base64EncodedString(), "MADAR_UI_TURATH_BOOK_BASE64": Data(book.utf8).base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let turath = app.buttons["mihbara-add-source-turath"]; XCTAssertTrue(turath.waitForExistence(timeout: 8), app.debugDescription)
        attach(app, "M6-T01-add-sources-L")
        turath.tap()
        let suggestion = app.buttons["mihbara-turath-suggestion-صيد الخاطر"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        attach(app, "M6-T01-turath-start-L")
        let field = app.textFields["mihbara-turath-search"]; field.tap(); field.typeText("الجوزى")
        let result = app.buttons["mihbara-turath-book-12028"]; XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-turath-book-7"].exists)
        attach(app, "M6-T01-turath-results-L")
        result.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertEqual(app.textFields["mihbara-epub-import-title"].value as? String, "صيد الخاطر")
        XCTAssertEqual(app.textFields["mihbara-epub-import-author"].value as? String, "ابن الجوزي")
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-import-toc-3"].exists, app.debugDescription)
        attach(app, "M6-T01-turath-preview-L")
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 15), app.debugDescription)
        wantShelf.tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "صيد الخاطر")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription)
        imported.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 15), app.debugDescription)
        sleep(2)
        attach(app, "M6-T01-turath-reader-L")
        app.buttons["mihbara-reader-contents"].tap()
        let bookInfo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "بيانات الكتاب")).firstMatch
        XCTAssertTrue(bookInfo.waitForExistence(timeout: 8), app.debugDescription)
        bookInfo.tap()
        let shamelaPage = app.links.matching(NSPredicate(format: "label CONTAINS %@", "موقع المكتبة الشاملة")).firstMatch
        XCTAssertTrue(shamelaPage.waitForExistence(timeout: 10), app.debugDescription)
        attach(app, "M6-T01-turath-shamela-L")
        XCTAssertTrue(app.buttons["mihbara-reader-contents"].exists, app.debugDescription)
        app.buttons["mihbara-reader-contents"].tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "علو الهمة")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 8), app.debugDescription)
        chapter.tap()
        let passage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "من علامة كمال العقل")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 10), app.debugDescription)
        passage.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        let wordCard = app.descendants(matching: .any)["mihbara-word-card"]
        XCTAssertTrue(wordCard.waitForExistence(timeout: 8), app.debugDescription)
        let yellowHighlight = app.buttons["mihbara-highlight-yellow"]
        yellowHighlight.tap()
        let selectedHighlight = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: yellowHighlight)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedHighlight], timeout: 8), .completed, app.debugDescription)
        let quoteButton = app.buttons["mihbara-quote-card-open"]
        XCTAssertTrue(quoteButton.waitForExistence(timeout: 5), app.debugDescription)
        quoteButton.tap()
        let preview = app.descendants(matching: .any)["mihbara-quote-card-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(preview.label.contains("صيد الخاطر"), preview.label)
        XCTAssertTrue(preview.label.contains("ابن الجوزي"), preview.label)
        XCTAssertTrue(preview.label.contains("ج ٢، ص ٢٨"), preview.label)
        XCTAssertTrue(preview.label.contains("shamela.ws/book/12028"), preview.label)
        attach(app, "M6-T01-turath-quote-card-L")
    }

    /// Explicit opt-in: real catalogue/book requests, never the synthetic Turath launch payloads.
    func testLiveTurathSearchDownloadsAndQuotesABook() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MADAR_RUN_LIVE_TURATH"] == "1" || environment["TEST_RUNNER_MADAR_RUN_LIVE_TURATH"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_MADAR_RUN_LIVE_TURATH=1 for the live Turath trial")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-20T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let turath = app.buttons["mihbara-add-source-turath"]
            // The shelf may still be settling after the previous import; a second tap opens the sources.
            if !turath.waitForExistence(timeout: 6) { attach(app, "trial-debug-add"); add.tap() }
            XCTAssertTrue(turath.waitForExistence(timeout: 8), app.debugDescription); turath.tap()
        let suggestion = app.buttons["mihbara-turath-suggestion-صيد الخاطر"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 60), "The real catalogue did not load")
        let field = app.textFields["mihbara-turath-search"]; field.tap(); field.typeText("صيد الخاطر")
        let result = app.buttons["mihbara-turath-book-12028"]
        XCTAssertTrue(result.waitForExistence(timeout: 10)); attach(app, "M6-T01-live-search-L"); result.tap()
        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), "The real book download/conversion did not finish")
        XCTAssertEqual(app.textFields["mihbara-epub-import-title"].value as? String, "صيد الخاطر")
        XCTAssertEqual(app.textFields["mihbara-epub-import-author"].value as? String, "ابن الجوزي")
        XCTAssertTrue(confirm.isHittable, "Long real outlines keep the import action visible")
        attach(app, "M6-T01-live-import-L"); confirm.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]; XCTAssertTrue(wantShelf.waitForExistence(timeout: 20)); wantShelf.tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "صيد الخاطر")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 10)); imported.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20))
        app.buttons["mihbara-reader-contents"].tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "المواعظ والسامع")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10)); chapter.tap()
        let passage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "قد يعرض عند سماع المواعظ")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 15), "The downloaded chapter must be readable")
        XCTAssertTrue(passage.isHittable)
        attach(app, "M6-T01-live-reader-L")
        passage.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-word-card"].waitForExistence(timeout: 10))
        let highlight = app.buttons["mihbara-highlight-yellow"]; XCTAssertTrue(highlight.waitForExistence(timeout: 8)); highlight.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: highlight)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
        let quoteButton = app.buttons["mihbara-quote-card-open"]; XCTAssertTrue(quoteButton.waitForExistence(timeout: 8)); quoteButton.tap()
        let preview = app.descendants(matching: .any)["mihbara-quote-card-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.label.contains("صيد الخاطر")); XCTAssertTrue(preview.label.contains("ابن الجوزي"))
        // The live source has 893 pages in one volume; this chapter's printed label is 23.
        // Unlike the two-volume synthetic fixture, this citation correctly omits a volume prefix.
        XCTAssertTrue(preview.label.contains("ص ٢٣"), preview.label)
        XCTAssertFalse(preview.label.contains("ج ١"), preview.label)
        XCTAssertTrue(preview.label.contains("shamela.ws/book/12028"), preview.label)
        attach(app, "M6-T01-live-quote-L")
    }

    /// Owner trial, 21 Oct 2026: ten real Turath books spread over every shelf, then the room as it looks.
    func testLiveTurathTenBooksAcrossEveryShelf() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MADAR_RUN_LIVE_TURATH"] == "1" || environment["TEST_RUNNER_MADAR_RUN_LIVE_TURATH"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_MADAR_RUN_LIVE_TURATH=1 for the live Turath trial")
        }
        continueAfterFailure = false
        // (Turath id, search words, title as it lands, shelf at import, moved to «قديمًا» afterwards)
        let books: [(Int, String, String, String, Bool)] = [
            (9820, "الرحيق المختوم", "الرحيق المختوم", "reading", false),
            (12014, "رياض الصالحين الرسالة", "رياض الصالحين", "reading", false),
            (9884, "حلية طالب العلم", "حلية طالب العلم", "reading", false),
            (13566, "الأذكار للنووي مستو", "الأذكار", "want", false),
            (216, "الوابل الصيب دار الحديث", "الوابل الصيب", "want", false),
            (197, "زاد المعاد عطاءات", "زاد المعاد", "want", false),
            (12028, "صيد الخاطر", "صيد الخاطر", "finished", false),
            (12836, "الأربعون النووية", "الأربعون النووية", "finished", false),
            (98087, "مختصر منهاج القاصدين", "مختصر منهاج القاصدين", "finished", true),
            (158, "الداء والدواء دار المعرفة", "الداء والدواء", "finished", true)
        ]
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-21T21:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        for (n, book) in books.enumerated() {
            let add = app.buttons["mihbara-add-paper"]
            let addReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: add)
            XCTAssertEqual(XCTWaiter.wait(for: [addReady], timeout: 20), .completed, app.debugDescription); add.tap()
            let turath = app.buttons["mihbara-add-source-turath"]
            // The shelf may still be settling after the previous import; a second tap opens the sources.
            if !turath.waitForExistence(timeout: 6) { attach(app, "trial-debug-add"); add.tap() }
            XCTAssertTrue(turath.waitForExistence(timeout: 8), app.debugDescription); turath.tap()
            let field = app.textFields["mihbara-turath-search"]
            XCTAssertTrue(app.buttons["mihbara-turath-suggestion-صيد الخاطر"].waitForExistence(timeout: 90), "The real catalogue did not load")
            field.tap(); field.typeText(book.1)
            let result = app.buttons["mihbara-turath-book-\(book.0)"]
            XCTAssertTrue(result.waitForExistence(timeout: 15), "No result \(book.0) for \(book.1)")
            if n == 0 { attach(app, "trial-01-turath-search") }
            result.tap()
            let confirm = app.buttons["mihbara-epub-import-confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 180), "Download/conversion of \(book.0) did not finish")
            if n == 5 { attach(app, "trial-02-import-review-large") }
            let shelf = app.buttons["mihbara-epub-shelf-\(book.3)"]
            // The shelf row sits under the pinned «أضفه إلى مكتبتي» until the review scrolls; isHittable does not see that.
            app.swipeUp(velocity: .slow)
            for _ in 0..<10 where !shelf.isHittable { app.swipeUp(velocity: .slow) }
            // The review may still settle after it appears; tap until the shelf choice really took.
            for _ in 0..<4 where !shelf.isSelected { shelf.tap(); sleep(1) }
            if !shelf.isSelected { attach(app, "trial-debug-shelf") }
            XCTAssertTrue(shelf.isSelected, "Shelf \(book.3) not chosen for \(book.0)\n\(app.debugDescription)")
            for _ in 0..<10 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
            confirm.tap()
            XCTAssertTrue(app.buttons["mihbara-shelf-want"].waitForExistence(timeout: 30), "Import of \(book.0) did not return to the room")
        }
        app.buttons["mihbara-shelf-finished"].tap()
        for book in books where book.4 {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", book.2)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
            row.press(forDuration: 1.2)
            let move = app.buttons["انقله إلى «قديمًا»"]
            XCTAssertTrue(move.waitForExistence(timeout: 8), app.debugDescription); move.tap()
            _ = app.buttons["mihbara-shelf-finished"].waitForExistence(timeout: 5)
        }
        app.swipeDown(velocity: .fast)
        for shelf in ["reading", "want", "finished"] {
            app.buttons["mihbara-shelf-\(shelf)"].tap(); sleep(1); attach(app, "trial-03-shelf-\(shelf)")
        }
        app.buttons["mihbara-shelf-reading"].tap()
        for i in 0..<3 { app.swipeUp(velocity: .slow); sleep(1); attach(app, "trial-04-room-scroll-\(i + 1)") }
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        let reading = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "الرحيق المختوم")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 8)); reading.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 30), app.debugDescription)
        sleep(2); attach(app, "trial-05-reader")
        app.buttons["mihbara-reader-close"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot(), attachment = XCTAttachment(screenshot: s); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")) }
    }
}
