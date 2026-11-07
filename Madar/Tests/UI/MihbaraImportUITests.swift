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
        keepAsPDF(app)
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
        scannedPDFReaderSavesPositionAndResumes(failFirstOpen: false)
    }

    func testPDFOpenFailureRetriesWithoutLeavingAndKeepsPosition() {
        scannedPDFReaderSavesPositionAndResumes(failFirstOpen: true)
    }

    private func scannedPDFReaderSavesPositionAndResumes(failFirstOpen: Bool) {
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
        if failFirstOpen { app.launchEnvironment["MADAR_UI_PDF_OPEN_FAILURE_ONCE"] = "1" }
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
        keepAsPDF(app)
        let addBook = app.buttons["mihbara-add-paper"]
        let addBookVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addBook)
        XCTAssertEqual(XCTWaiter.wait(for: [addBookVisible], timeout: 15), .completed, app.debugDescription)
        addBook.tap()
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["mihbara-import-reopen"].exists)
        app.buttons["mihbara-add-back"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        XCTAssertTrue(app.staticTexts["ملف اختبار مصوّر"].firstMatch.waitForExistence(timeout: 8))
        let imported = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "mihbara-book-", "ملف اختبار مصوّر")).firstMatch
        // Bring the actual spine clear of the pinned navigation and floating accessory before tapping.
        for _ in 0..<8 {
            if imported.frame.minY > 125 && imported.frame.maxY < app.frame.maxY - 220 { break }
            if imported.frame.minY <= 125 { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(imported.isHittable, app.debugDescription)
        imported.tap()
        if failFirstOpen {
            let retry = app.buttons["mihbara-pdf-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 12), app.debugDescription)
            attach(app, "AU-46-PDF-open-error-L")
            retry.tap()
            XCTAssertFalse(retry.exists)
        }
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
        if failFirstOpen {
            let retry = app.buttons["mihbara-pdf-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 8), app.debugDescription)
            retry.tap()
        }
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
        keepAsPDF(app)

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

    /// FB-45: on the last page the reader asks «أنهيته؟»; a touch saves, puts the book on «أنهيتها» and closes.
    func testPDFLastPageAsksFinishedAndMovesTheBook() {
        continueAfterFailure = false
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            for page in 1...2 { canvas.beginPage(); ("الصفحة \(page) من كتاب قصير يُختم" as NSString).draw(in: CGRect(x: 20, y: 35, width: 260, height: 320), withAttributes: [.font: UIFont.systemFont(ofSize: 21)]) }
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب يُختم", "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString(),
            "MADAR_UI_MIHBARA_LOCATOR_FAIL_ON_CLOSE": "1"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap(); keepAsPDF(app)
        let want = app.buttons["mihbara-shelf-want"]; XCTAssertTrue(want.waitForExistence(timeout: 15)); want.tap()
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب يُختم")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription); imported.tap()
        let next = app.buttons["mihbara-pdf-next"]; XCTAssertTrue(next.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-reader-finish"].exists, "Page 1 of 2 is not the end")
        next.tap()
        let finish = app.buttons["mihbara-reader-finish"]; XCTAssertTrue(finish.waitForExistence(timeout: 5), app.debugDescription)
        attach(app, "FB45-pdf-finish-L")
        finish.tap()
        let pending = app.alerts["قارئ PDF"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(next.exists, "A failed position save must keep the reader open")
        pending.buttons["mihbara-reading-save-retry"].firstMatch.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(want.waitForExistence(timeout: 8)); want.tap()
        XCTAssertTrue(imported.waitForExistence(timeout: 8), "The book must remain on its original shelf after a failed save")
        imported.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 12), app.debugDescription)
        finish.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 10), "The reader closes after «أنهيته؟»")
        let finished = app.buttons["mihbara-shelf-finished"]; XCTAssertTrue(finished.waitForExistence(timeout: 8), app.debugDescription); finished.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب يُختم")).firstMatch.waitForExistence(timeout: 8), app.debugDescription)
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
                    .font: UIFont(name: "Arial", size: 24)!, .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph
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
        // Owner, 25 Oct 2026: adding a PDF offers the conversion; it runs while the room stays usable.
        let convert = app.alerts.buttons["حوّله"].firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 15), app.debugDescription)
        attach(app, "M6-PDF-flow-offer-L")
        convert.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-flow-progress"].waitForExistence(timeout: 15), app.debugDescription)
        let open = app.buttons["mihbara-pdf-flow-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "٣ صفحات")).firstMatch.exists, app.debugDescription)
        attach(app, "M6-PDF-flow-ready-L")
        open.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 15), app.debugDescription)
        let contents = app.buttons["mihbara-reader-contents"]
        XCTAssertTrue(contents.exists, app.debugDescription)
        contents.tap()
        let firstPage = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "صفحة ١")).firstMatch
        XCTAssertTrue(firstPage.waitForExistence(timeout: 8), app.debugDescription); firstPage.tap()
        // Arial's embedded PDF layer uses Arabic presentation forms. Compare
        // their Unicode equivalents, without changing the preserved source text.
        let body = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.webViews.staticTexts.allElementsBoundByIndex.contains {
                $0.label.precomposedStringWithCompatibilityMapping.contains("القراءة باب إلى المعرفة")
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [body], timeout: 15), .completed, app.debugDescription)
        attach(app, "M6-PDF-flow-reader-L")
        // «الكتاب تكرر مرتين»: the converted book stands for its PDF; the PDF stays reachable as «الأصل».
        let original = app.buttons["mihbara-reader-original-pdf"]
        XCTAssertTrue(original.waitForExistence(timeout: 5), app.debugDescription)
        original.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-close"].waitForExistence(timeout: 15), app.debugDescription)
        let originalPage = app.descendants(matching: .any)["mihbara-pdf-page"]
        XCTAssertTrue(originalPage.waitForExistence(timeout: 8), app.debugDescription)
        let bidiIsolates = CharacterSet(charactersIn: "\u{2066}\u{2067}\u{2068}\u{2069}")
        let originalPageLabel = String(originalPage.label.unicodeScalars.filter { !bidiIsolates.contains($0) })
        XCTAssertTrue(originalPageLabel.contains("١ من ٣"), originalPageLabel)
        app.buttons["mihbara-pdf-close"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        let copies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب منساب"))
        XCTAssertTrue(copies.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(copies.count, 1, app.debugDescription)
        attach(app, "M6-PDF-flow-shelf-L")
    }

    func testCancelAfterStagingKeepsTheOriginalPDFOnItsShelf() {
        continueAfterFailure = false
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            canvas.beginPage()
            ("كتاب الإيقاف\n\nالقراءة باب إلى المعرفة، والكتاب صاحب لا يمل." as NSString).draw(
                in: CGRect(x: 20, y: 35, width: 260, height: 320), withAttributes: [
                    .font: UIFont(name: "Arial", size: 24)!, .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph
                ])
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب الإيقاف", "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString(),
            "MADAR_UI_PDF_CONVERSION_STAGED_HOLD_MS": "15000"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let convert = app.alerts.buttons["حوّله"].firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 15), app.debugDescription); convert.tap()

        let staged = app.staticTexts["mihbara-pdf-flow-staged"]
        XCTAssertTrue(staged.waitForExistence(timeout: 45), app.debugDescription)
        attach(app, "M6-PDF-cancel-staged-L")
        app.buttons["mihbara-pdf-flow-cancel"].tap()
        let progress = app.descendants(matching: .any)["mihbara-pdf-flow-progress"]
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 15), .completed, app.debugDescription)

        app.buttons["mihbara-shelf-want"].tap()
        let original = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "mihbara-book-", "كتاب الإيقاف")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10), app.debugDescription)
        original.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-next"].waitForExistence(timeout: 12), "Cancel must leave the original PDF on its shelf.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["mihbara-reader-original-pdf"].exists, app.debugDescription)
    }

    func testCancelDuringEPUBAssemblyStopsBeforeStaging() {
        continueAfterFailure = false
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            canvas.beginPage()
            ("كتاب ترتيب الصفحات\n\nالقراءة باب إلى المعرفة، والكتاب صاحب لا يمل." as NSString).draw(
                in: CGRect(x: 20, y: 35, width: 260, height: 320), withAttributes: [
                    .font: UIFont(name: "Arial", size: 24)!, .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph
                ])
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب ترتيب الصفحات", "MADAR_UI_MIHBARA_IMPORT_PDF": pdf.base64EncodedString(),
            "MADAR_UI_PDF_CONVERSION_BUILD_HOLD_MS": "6000"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let convert = app.alerts.buttons["حوّله"].firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 15), app.debugDescription); convert.tap()

        let assembling = app.staticTexts["mihbara-pdf-flow-assembling"]
        XCTAssertTrue(assembling.waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["mihbara-pdf-flow-cancel"].tap()
        let canceling = app.staticTexts["mihbara-pdf-flow-canceling"]
        XCTAssertTrue(canceling.waitForExistence(timeout: 5), app.debugDescription)
        attach(app, "M6-PDF-cancel-assembling-L")
        let progress = app.descendants(matching: .any)["mihbara-pdf-flow-progress"]
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 15), .completed, app.debugDescription)

        app.buttons["mihbara-shelf-want"].tap()
        let original = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "mihbara-book-", "كتاب ترتيب الصفحات")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10), app.debugDescription)
        original.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-next"].waitForExistence(timeout: 12), "Cancel must leave the original PDF on its shelf.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["mihbara-reader-original-pdf"].exists, app.debugDescription)
    }

    /// Owner, 25 Oct 2026: «اقدر اتنقل بالتطبيق». A conversion iOS stopped by closing the app starts again
    /// the next time the room opens, and still ends as one flowing book.
    func testAConversionStoppedByClosingTheAppResumesWhenTheRoomOpens() throws {
        continueAfterFailure = false
        // Scanned pages (a picture of text) go through on-device OCR, slow enough to close the app mid-way.
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        let scan = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 600, height: 800))
            ("القراءة باب إلى المعرفة، والكتاب صاحب لا يمل.\nومن قرأ كثيرا عرف كثيرا." as NSString).draw(in: CGRect(x: 40, y: 70, width: 520, height: 640),
                withAttributes: [.font: UIFont(name: "Arial", size: 40)!, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { canvas in
            for _ in 1...120 { canvas.beginPage(); scan.draw(in: CGRect(x: 0, y: 0, width: 300, height: 400)) }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("long-book.pdf")
        try pdf.write(to: file)
        let store = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": store, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_PDF_NAME": "كتاب طويل", "MADAR_UI_MIHBARA_IMPORT_PDF_PATH": file.path,
            "MADAR_UI_PDF_CONVERSION_HOLD_AFTER_PAGE": "5", "MADAR_UI_PDF_CONVERSION_PAGE_HOLD_MS": "30000",
            "MADAR_UI_PDF_CONVERSION_RESUME_HOLD_MS": "10000"]
        func openRoom() {
            let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
            let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
            let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        }
        app.launch(); openRoom()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), app.debugDescription)
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp(velocity: .slow) }
        confirm.tap()
        let convert = app.alerts.buttons["حوّله"].firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 15), app.debugDescription); convert.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-pdf-flow-progress"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-pdf-flow-open"].exists, "120 scanned pages must still be converting")
        // Pause only after page five has been atomically saved, so termination is deterministic.
        let pageStatus = app.staticTexts["mihbara-pdf-flow-page"]
        XCTAssertTrue(pageStatus.waitForExistence(timeout: 60), app.debugDescription)
        let reachedCheckpoint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "٦", "١٢٠"), object: pageStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [reachedCheckpoint], timeout: 60), .completed, app.debugDescription)
        XCTAssertTrue(pageStatus.label.contains("٦"), app.debugDescription)
        XCTAssertTrue(app.staticTexts["mihbara-pdf-flow-time-left"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["mihbara-pdf-flow-time-left"].label.hasPrefix("باقي"), app.debugDescription)
        app.terminate()
        app.launch(); openRoom()
        XCTAssertTrue(pageStatus.waitForExistence(timeout: 20), app.debugDescription)
        let resumedAtCheckpoint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "٦", "١٢٠"), object: pageStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [resumedAtCheckpoint], timeout: 20), .completed, "The checkpoint must resume after five completed pages.\n\(app.debugDescription)")
        attach(app, "M6-PDF-flow-resumed-L")
        XCTAssertTrue(app.buttons["mihbara-pdf-flow-open"].waitForExistence(timeout: 600), app.debugDescription)
        app.buttons["mihbara-pdf-flow-open"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["mihbara-reader-close"].tap()
        app.buttons["mihbara-shelf-want"].tap()
        let copies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "كتاب طويل"))
        XCTAssertTrue(copies.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(copies.count, 1, app.debugDescription)
    }

    func testCancelEPUBScanReturnsToShelfWithoutAddingAndCanRetry() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_EPUB_SLOW_SCAN": "1", "MADAR_UI_MIHBARA_IMPORT_EPUB": try Data(contentsOf: fixture).base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        app.buttons["mihbara-add-paper"].tap()
        let progress = app.descendants(matching: .any)["mihbara-epub-scan-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-epub-import-confirm"].isEnabled)
        attach(app, "M6-EPUB-scan-cancel-L")
        XCTAssertTrue(progress.exists)
        XCTAssertFalse(app.buttons["mihbara-epub-import-confirm"].isEnabled, "Cancel while the scan is still active")
        app.buttons["mihbara-epub-import-back"].tap()
        let addBack = app.buttons["mihbara-add-back"]
        XCTAssertTrue(addBack.waitForExistence(timeout: 8), app.debugDescription); addBack.tap()
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["mihbara-add-paper"].tap()
        let reopen = app.buttons["mihbara-import-reopen"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 8), app.debugDescription); reopen.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-scan-text"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-epub-import-confirm"].isEnabled)
        XCTAssertFalse(app.staticTexts["mihbara-epub-import-error"].exists)
        app.buttons["mihbara-epub-import-back"].tap()
        XCTAssertTrue(addBack.waitForExistence(timeout: 8)); addBack.tap()
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout: 8))
        app.terminate()
    }

    func testEPUBScanExplainsReversedAnchorsAndPageLinks() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "scan-order-poc", withExtension: "epub"))
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_MIHBARA_IMPORT_EPUB": try Data(contentsOf: fixture).base64EncodedString()]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let add = app.buttons["mihbara-add-paper"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let toc = app.descendants(matching: .any)["mihbara-epub-scan-toc"]
        XCTAssertTrue(toc.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(toc.label.contains("بعضها ليس بترتيب الكتاب"), toc.label)
        let pages = app.descendants(matching: .any)["mihbara-epub-scan-pages"]
        for _ in 0..<5 where !pages.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(pages.label.contains("تحتاج بعض الأرقام أو روابطها إلى مراجعة الترتيب"), pages.label)
        XCTAssertTrue(pages.label.contains("يتكرر رقم واحد"), pages.label)
        XCTAssertTrue(pages.label.contains("تعذّر التحقق"), pages.label)
        XCTAssertFalse(pages.label.contains("بلا نقص ولا تكرار"), pages.label)
        let encoding = app.descendants(matching: .any)["mihbara-epub-scan-encoding"]
        XCTAssertTrue(encoding.exists && encoding.label.contains("ترميز غير معتاد"), app.debugDescription)
        let verses = app.descendants(matching: .any)["mihbara-epub-scan-verses"]
        XCTAssertTrue(verses.exists && verses.label.contains("آيات كاملة بلا أقواس"), app.debugDescription)
        for _ in 0..<5 where !verses.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-import-size"].label.contains("عدد صفحات المطبوع غير متحقق"))
        XCTAssertTrue(app.buttons["mihbara-epub-import-confirm"].isEnabled, "The scan reports faults; it does not block the owner's import choice")
        attach(app, "M6-21-scan-order-warning-L")
        app.terminate()
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
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-scan-text"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-scan-toc"].exists, app.debugDescription)
        XCTAssertTrue(confirm.isEnabled, app.debugDescription)
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
        let readerClose = app.buttons["mihbara-reader-close"]
        XCTAssertTrue(readerClose.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["mihbara-reader-settings"].tap()
        let scrollMode = app.buttons["mihbara-reader-mode-scroll"]
        XCTAssertTrue(scrollMode.waitForExistence(timeout: 8), app.debugDescription)
        if !scrollMode.isSelected { scrollMode.tap(); XCTAssertTrue(scrollMode.isSelected, app.debugDescription) }
        app.buttons["mihbara-reader-settings-close"].tap()
        let progress = app.descendants(matching: .any)["mihbara-reader-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8), app.debugDescription)
        let startingProgress = String(describing: progress.value ?? "")
        let finalChapter = app.staticTexts["Closing the Book"]
        for _ in 0..<12 where !finalChapter.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(finalChapter.isHittable, app.debugDescription)
        let savedProgress = String(describing: progress.value ?? "")
        XCTAssertNotEqual(savedProgress, startingProgress, "Scrolling should move the fixture EPUB's locator")
        readerClose.tap()
        let reopened = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A Book About Reading")).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 8), app.debugDescription)
        reopened.tap()
        XCTAssertTrue(readerClose.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(finalChapter.waitForExistence(timeout: 12), app.debugDescription)
        let resumedProgress = app.descendants(matching: .any)["mihbara-reader-progress"]
        XCTAssertTrue(resumedProgress.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(String(describing: resumedProgress.value ?? ""), savedProgress, "Reopening from the want shelf should restore the saved EPUB locator")
        XCTAssertTrue(finalChapter.isHittable, "The reopened EPUB should resume at its saved chapter.\n\(app.debugDescription)")
        readerClose.tap()
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
        // A Turath file holds 30 printed pages, so volume 2 begins mid-chapter here: the reader must turn to that page.
        XCTAssertTrue(subtitle.label.hasPrefix("الجزء الثاني"), "Reader subtitle: \(subtitle.label)")
        attach(app, "M6-UX-V-reader-second-volume-L")
    }

    /// Owner, 22 Oct 2026: twenty bindings, each on one book (eight sets and twelve single books), photographed along the shelf.
    func testTwentyBindingsAlongTheShelf() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "bindings",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        let wantShelf = app.buttons["mihbara-shelf-want"]; XCTAssertTrue(wantShelf.waitForExistence(timeout: 15), app.debugDescription)
        wantShelf.tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "زاد المعاد")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        sleep(1)
        attach(app, "bindings-shelf-01-L")
        // The bookcase grows downwards: five shelves, the rest under «كل كتبي».
        for n in 2...5 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            attach(app, String(format: "bindings-shelf-%02d-L", n))
        }
        // «أنهيتها»: the finished books lie in piles across the shelves.
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        let finished = app.buttons["mihbara-shelf-finished"]; XCTAssertTrue(finished.waitForExistence(timeout: 5), app.debugDescription)
        finished.tap(); sleep(1)
        attach(app, "bindings-finished-L")
        // Owner, 21 Oct 2026: «قديمًا» joined «أنهيتها»; piles are labelled by year, and books read long ago come last.
        let years = app.staticTexts.matching(identifier: "mihbara-pile-year")
        XCTAssertGreaterThanOrEqual(years.count, 2, app.debugDescription)
        XCTAssertTrue(app.staticTexts["قديمًا"].exists, "The old books lie under «أنهيتها».\n\(app.debugDescription)")
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        sleep(1); attach(app, "bindings-finished-old-L")
        let library = app.buttons["mihbara-library"]
        for _ in 0..<6 where !library.isHittable { app.swipeUp(velocity: .slow) }
        library.tap()
        let oldSection = app.descendants(matching: .any)["mihbara-library-section-old"]
        for _ in 0..<8 where !oldSection.exists || !oldSection.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(oldSection.exists, "«كل كتبي» has a «قديمًا» section.\n\(app.debugDescription)")
        attach(app, "library-old-section-L")
    }

    /// The owner's layout ٢ in dark: the wall bookcase, its labels and the stand keep their contrast.
    func testWallBookcaseAndStandInDark() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "home",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "dark"]
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        XCTAssertTrue(app.buttons["mihbara-shelf-want"].waitForExistence(timeout: 15), app.debugDescription)
        sleep(1); attach(app, "M6-UX-R-wall-dark")
        let go = app.buttons["mihbara-book-continue"]
        for _ in 0..<6 where !go.isHittable { app.swipeUp(velocity: .slow) }
        sleep(1); attach(app, "M6-UX-R-stand-dark")
    }

    func testTurathUnavailableCatalogueOffersRetryWithoutFalseEmptyResults() throws {
        let app = try openTurathForCatalogueFailure(catalogue: "invalid-catalogue")
        let field = app.textFields["mihbara-turath-search"]
        field.tap(); field.typeText("صيد\n")
        XCTAssertTrue(app.staticTexts["mihbara-turath-error"].waitForExistence(timeout: 8))
        attach(app, "M6-Turath-unavailable-L")
        let retry = app.buttons["mihbara-turath-retry"]
        XCTAssertTrue(retry.exists, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["mihbara-turath-empty"].exists, "Unavailable catalogue cannot establish that no book matches")
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, "صيد")
        app.terminate()
    }

    func testTurathCatalogueRetryPreservesQueryAndFindsTheBook() throws {
        let catalogue = #"{"cats":{},"authors":{},"books":{"12028":{"id":12028,"name":"صيد الخاطر","size":1000,"page_count":10}},"books_changed":[],"date":"2026-02-03","version":1}"#
        let app = try openTurathForCatalogueFailure(catalogue: catalogue, failOnce: true)
        let field = app.textFields["mihbara-turath-search"]
        field.tap(); field.typeText("صيد\n")
        let retry = app.buttons["mihbara-turath-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8), app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.buttons["mihbara-turath-book-12028"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(field.value as? String, "صيد")
        XCTAssertFalse(app.staticTexts["mihbara-turath-error"].exists)
        XCTAssertFalse(retry.exists)
        attach(app, "M6-Turath-retry-results-L")
        app.terminate()
    }

    private func openTurathForCatalogueFailure(catalogue: String, failOnce: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MIHBARA_FIXTURE": "empty",
            "MADAR_UI_NOW": "2026-10-18T12:00:00+03:00", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_TURATH_CATALOGUE_BASE64": Data(catalogue.utf8).base64EncodedString()]
        if failOnce { app.launchEnvironment["MADAR_UI_TURATH_CATALOGUE_FAILURE_ONCE"] = "1" }
        app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout: 8)); door.tap()
        app.buttons["mihbara-add-paper"].tap()
        let turath = app.buttons["mihbara-add-source-turath"]; XCTAssertTrue(turath.waitForExistence(timeout: 8)); turath.tap()
        XCTAssertTrue(app.staticTexts["mihbara-turath-error"].waitForExistence(timeout: 8), app.debugDescription)
        return app
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
        let notes = app.links["حواشي الصفحة"]
        for _ in 0..<5 where !notes.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(notes.waitForExistence(timeout: 8), app.debugDescription); notes.tap()
        let footnote = app.staticTexts["mihbara-footnote-text"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(footnote.label.contains("الدون: الأمر الخسيس الحقير"))
        attach(app, "OR-28-turath-page-footnotes-L")
        app.buttons["mihbara-footnote-close"].tap()
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
        XCTAssertFalse(preview.label.contains("shamela.ws"), preview.label)
        for extra in ["book", "author", "location", "source"] {
            let chip = app.buttons["mihbara-quote-extra-\(extra)"]
            if !chip.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription); chip.tap()
        }
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
        let scanFinished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [scanFinished], timeout: 120), .completed, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-epub-scan-text"].exists, app.debugDescription)
        XCTAssertTrue(confirm.isHittable, "Long real outlines keep the import action visible after the full scan")
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
        for extra in ["book", "author", "location", "source"] {
            let chip = app.buttons["mihbara-quote-extra-\(extra)"]
            if !chip.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        }
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

    /// Adding a PDF offers the conversion (owner, 25 Oct 2026); these flows keep the PDF as it is.
    private func keepAsPDF(_ app: XCUIApplication) {
        let keep = app.alerts.buttons["أبقه PDF"].firstMatch
        if keep.waitForExistence(timeout: 15) { keep.tap() }
    }
}
