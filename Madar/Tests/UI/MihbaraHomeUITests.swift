import XCTest
import UIKit

@MainActor final class MihbaraHomeUITests: XCTestCase {
    /// Handwritten legacy Turath EPUB: one chapter, no noteref link, two complete note paragraphs.
    /// Its immutable content is enriched only in the reader DOM; no converter or owner file is used.
    func testLegacyTurathPageNotesOpenWithoutReimportingTheBook() throws {
        continueAfterFailure = false
        let bytes = try XCTUnwrap(Data(base64Encoded: """
            UEsDBBQAAAAAAE2BW11vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAACABNgVtdnKtv
            WZcAAADdAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxVjsEKwjAQRH8l5Cpt9BqSCIJnBb9gTbcaTLJLkor+vUWk6m1gHm/G
            bB8pijuWGihbuenXcuuMp9wgZCz/jZjZXK2cStYENVSdIWHVzWtizAP5KWFu+o3pRSKdKURtDBHrN4pxirFjaFcrD/vd8aQY/A0u
            2BOPUiQcAnTtyWglMMfgoc1HFOGZa/dBV/OSVM6oH79adt0LUEsDBBQAAAAIAE2BW12N3OidfAEAAIoCAAARAAAAT0VCUFMvcGFj
            a2FnZS5vcGaNUt2K3CAUfhXxthgzU9iFkLgv0aveiZ4kUjVWT3ZmbguFsi9StqWUQh8meZsas53dvVsQVM73d462d2dnyT3EZCbf
            0UNV0zvRBqk+yQFIrvnU0RExNJyfTqfK6NBXUxz4sa5v+RR6uoMara64MEdbMFpxsODAY+KH6sDps9H7bERmbz7PwIzOCNMbiB01
            ugg2VvqhozJS0TpAqSVK0WrVPGOJ0QUu5ugblxGxSRePI6BRzMIg1YXhHCWOzE8IqeWv6EUNDVoQy6/12/J9+bs+kOXH8icff5L1
            y/J7fVi/Lo+FtwM3yhZszrMRMpbK9V5ykhCnABEvHdUKIbrUuElvhjnosT7esEPNjrcf6rop62PLN5rYt71LJ73pIaFoDYIrbXp5
            T8kYoS/H6jyis5Q40EYyvATIkwrBGiUxD5eX8rvzBnmKYyDtIvyFqPovqd4uyLek13wpGA8k5O5ZNhoipO1xmTYRFJZnjmjpbpmd
            suvuV2QKOe9Pf038A1BLAwQUAAAACABNgVtdPzCM7b0AAAD3AAAADwAAAE9FQlBTL25hdi54aHRtbFWOTQrCMBBGrxJygI4/C2mZ
            5i6pjbYQm1Cj1aUgCl5EXLgQEfEmk9uYmJWbGRje+77Bxq002610ty5545wtAIZhyIZpZvoljPM8h11keIIKZTfVH9nWdvFjJ6PR
            DIxdc6Zltyy57LnARslaoGudVoKu/ugP/kwPeiKkG0IiKlPvBXZyy2JB4fZWldyZeYgwWqBuBUrW9GpR8nmWHhL08ge6043RlV70
            9qewP/5CNwQZgqMDUYYQG2aqgOiKL1BLAwQUAAAACABNgVtdrpsFeRoBAACRAQAADQAAAE9FQlBTL2MueGh0bWxVkE1uwjAQha9i
            eU9M20UFcnwXg12IFBIruA1dQgNU3KIrfiREEUW0N5m5DWMsVe3GY42/ee+N5dCPcjYZ5cU45UPvXVeIuq6T+iEpq4G463Q6YhIY
            HqGudc+9f2Rm3NONvW+3H0XpxpyZrEp55Wkm18Ug5briSg6tNkr6zOdWwRmnsIctgzWc4YILqj+4gq0UEZAi4r3SvCrpFM5hhwuG
            b7AjdMNwBgdc4ZzBBme4ogci1kHuROA7HOFAdZlI4ZQ02Qvr53pMG4600VXL6YFtFaW3lLUqc5tyU/ZbtjCxdzP8YBRwDV8h1a9d
            uM5hj1Oy+IZtlCd4CZ/B/QQXOBIR0mDDsMHmjwhFbYiiYVKLo4Ki0Rm3FOGb1RVQSwECFAMUAAAAAABNgVtdb2GrLBQAAAAUAAAA
            CAAAAAAAAAAAAAAAgAEAAAAAbWltZXR5cGVQSwECFAMUAAAACABNgVtdnKtvWZcAAADdAAAAFgAAAAAAAAAAAAAAgAE6AAAATUVU
            QS1JTkYvY29udGFpbmVyLnhtbFBLAQIUAxQAAAAIAE2BW12N3OidfAEAAIoCAAARAAAAAAAAAAAAAACAAQUBAABPRUJQUy9wYWNr
            YWdlLm9wZlBLAQIUAxQAAAAIAE2BW10/MIztvQAAAPcAAAAPAAAAAAAAAAAAAACAAbACAABPRUJQUy9uYXYueGh0bWxQSwECFAMU
            AAAACABNgVtdrpsFeRoBAACRAQAADQAAAAAAAAAAAAAAgAGaAwAAT0VCUFMvYy54aHRtbFBLBQYAAAAABQAFADEBAADfBAAAAAA=
            """, options: .ignoreUnknownCharacters))
        let app = app("reader", epub: bytes)
        app.launch(); open(app)
        let read = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ابدأ القراءة")).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 8)); reach(app, read); read.tap()
        let link = app.links["حواشي الصفحة"]
        XCTAssertTrue(link.waitForExistence(timeout: 12), app.debugDescription); link.tap()
        let note = app.staticTexts["mihbara-footnote-text"]
        XCTAssertTrue(note.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(note.label.contains("حاشية قديمة محفوظة"))
        XCTAssertTrue(note.label.contains("سطر مكمل للحاشية بلا فقد"))
        shot(app, "OR-28-legacy-turath-notes-L")
        app.buttons["mihbara-footnote-close"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "متن كتاب قديم بقي كما استوردته")).firstMatch.exists)
    }

    func testUnavailableFileExplainsItsStateWithoutOfferingAPaperPositionSave() throws {
        continueAfterFailure = false
        let app = app("missingFile"); app.launch(); open(app)
        let read = app.buttons["mihbara-book-continue"]; reach(app, read); read.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-book-file-unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mihbara-book-page"].exists)
        XCTAssertFalse(app.buttons["mihbara-book-save-position"].exists)
        shot(app, "Final-missing-book-L")
        app.buttons["mihbara-book-mark-finished"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-book-file-unavailable"].waitForNonExistence(timeout: 10))
    }
    func testMissingPDFRestoresToItsOriginalBookAndOpens() {
        continueAfterFailure = false
        let app = app("missingFile", pdf: fixturePDF())
        app.launch(); open(app)
        let continueBook = app.buttons["mihbara-book-continue"]
        reach(app, continueBook); continueBook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-book-file-unavailable"].waitForExistence(timeout: 8), app.debugDescription)
        let restore = app.buttons["mihbara-book-file-restore-detail"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "M6-J27-file-missing-L")
        restore.tap()

        let confirm = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["كتاب بلا ملف"].firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "يعود هذا الملف إلى")).firstMatch.exists, app.debugDescription)
        reach(app, confirm); shot(app, "M6-J27-file-restore-preview-L"); confirm.tap()
        keepPDF(app)

        let restoredReader = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(restoredReader.waitForExistence(timeout: 15), app.debugDescription)
        restoredReader.tap()
        XCTAssertTrue(app.buttons["mihbara-pdf-close"].waitForExistence(timeout: 15), app.debugDescription)
        let page = app.descendants(matching: .any)["mihbara-pdf-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(page.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "").contains("١ من ١"), page.label)
        app.buttons["mihbara-pdf-close"].tap()
        let library = app.buttons["mihbara-library"]; reach(app, library); library.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-"))
        XCTAssertEqual(rows.count, 1, "Restoring the exact file must keep one copy of its original book.")
        XCTAssertTrue(rows.firstMatch.label.contains("كتاب بلا ملف"), rows.firstMatch.label)
    }

    func testMissingEPUBRestoresToItsOriginalBookAndOpens() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let epub = try Data(contentsOf: url)
        let app = app("missingFile", epub: epub)
        app.launchEnvironment["MADAR_UI_MIHBARA_IMPORT_EPUB"] = epub.base64EncodedString()
        app.launch(); open(app)
        let continueBook = app.buttons["mihbara-book-continue"]
        reach(app, continueBook); continueBook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-book-file-unavailable"].waitForExistence(timeout: 8), app.debugDescription)
        let restore = app.buttons["mihbara-book-file-restore-detail"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "M6-J27-epub-missing-L")
        restore.tap()

        let confirm = app.buttons["mihbara-epub-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertTrue(app.staticTexts["كتاب بلا ملف"].firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "يعود هذا الملف إلى")).firstMatch.exists, app.debugDescription)
        shot(app, "M6-J27-epub-restore-preview-L"); confirm.tap()

        let restoredReader = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(restoredReader.waitForExistence(timeout: 15), app.debugDescription)
        restoredReader.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["كتاب بلا ملف"].firstMatch.exists, app.debugDescription)
        let closeReader = app.buttons["mihbara-reader-close"]
        closeReader.tap()
        XCTAssertTrue(closeReader.waitForNonExistence(timeout: 10), app.debugDescription)
        let library = app.buttons["mihbara-library"]; reach(app, library); library.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-"))
        XCTAssertEqual(rows.count, 1, "Restoring the exact EPUB must keep one copy of its original book.")
        XCTAssertTrue(rows.firstMatch.label.contains("كتاب بلا ملف"), rows.firstMatch.label)
    }

    func testGoodreadsCSVPreviewImportsBookAndLinkedPrivateNote() {
        continueAfterFailure = false
        let csv = "Book Id,Title,Author,Additional Authors,ISBN,ISBN13,My Rating,Exclusive Shelf,Date Read,Read Count,My Review,Private Notes,Number of Pages,Year Published,Date Added,Bookshelves\r\n"
            + "9001,رحلة Goodreads,أحمد,,,9780306406157,4,currently-reading,,1,\"مراجعة متعددة\r\nالسطور\",ملاحظة من Goodreads,120,2020,2020/02/01,favorites\r\n"
            + "9002,كتاب مؤرخ,أحمد,,,,5,read,2020/02/01,1,,,,2020,2020/02/01,"
        let app = app("empty")
        app.launchEnvironment["MADAR_UI_MIHBARA_IMPORT_GOODREADS"] = Data(csv.utf8).base64EncodedString()
        app.launch(); open(app)
        let addBook = app.buttons["mihbara-add-paper"]
        reach(app, addBook); addBook.tap()

        let importButton = app.buttons["mihbara-goodreads-import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["رحلة Goodreads"].firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "مراجعة متعددة")).firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ملاحظة من Goodreads")).firstMatch.exists, app.debugDescription)
        let cutoff = app.descendants(matching: .any)["mihbara-goodreads-cutoff-year"]
        XCTAssertTrue(cutoff.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(cutoff.label.contains("هـ") && cutoff.label.contains(" م"), cutoff.label)
        shot(app, "M6-V17-goodreads-preview-L")
        importButton.tap()

        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 20), app.debugDescription)
        let notebook = app.buttons["mihbara-notebook"]
        reach(app, notebook); notebook.tap()
        shot(app, "M6-V17-goodreads-private-note-L")
        let note = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "mihbara-note-", "mihbara-note-add")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(note.label.contains("ملاحظة من Goodreads"), note.label)
        XCTAssertTrue(note.label.contains("رحلة Goodreads"), note.label)

        note.tap()
        let editor = app.textViews["mihbara-note-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8), app.debugDescription)
        editor.tap(); editor.typeText(" — تم التعديل")
        app.buttons["mihbara-note-save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(note.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(note.label.contains("تم التعديل"), note.label)
        XCTAssertTrue(note.label.contains("رحلة Goodreads"), note.label)

        note.tap()
        let delete = app.buttons["mihbara-note-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 8), app.debugDescription)
        undo(app)
        let restoredNote = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "mihbara-note-", "mihbara-note-add")).firstMatch
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(restoredNote.label.contains("تم التعديل"), restoredNote.label)
        XCTAssertTrue(restoredNote.label.contains("رحلة Goodreads"), restoredNote.label)
    }

    func testCancellingGoodreadsPickerReturnsWithoutAnError() {
        continueAfterFailure = false
        let app = app("empty"); app.launch(); open(app)
        let addBook = app.buttons["mihbara-add-paper"]
        reach(app, addBook); addBook.tap()
        let source = app.buttons["mihbara-add-source-goodreads"]
        XCTAssertTrue(source.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V16-goodreads-cancel-before-L")
        source.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 12), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].exists, app.debugDescription)
        shot(app, "M6-V16-goodreads-cancel-after-L")
    }

    func testRemovingPDFKeepsTheBookButClearsUndo() {
        continueAfterFailure = false
        let app = app("empty", pdf: fixturePDF())
        app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        let importButton = app.buttons["mihbara-import-confirm"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 20), app.debugDescription)
        reach(app, importButton); importButton.tap(); keepPDF(app)

        let library = app.buttons["mihbara-library"]; reach(app, library); library.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-"))
            .containing(NSPredicate(format: "label CONTAINS %@", "نسخة الملف")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.press(forDuration: 1.2)
        let remove = app.buttons["mihbara-book-file-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription); remove.tap()
        let confirm = app.buttons["احذف ملف الكتاب"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لا يمكن التراجع")).firstMatch.exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-book-file-unavailable"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-book-file-restore-detail"].exists, app.debugDescription)
        app.buttons["تمّ"].tap()
        XCTAssertFalse(app.buttons["mihbara-undo"].exists, "The file removal must clear the previous import's undo toast.")
        let reopenedLibrary = app.buttons["mihbara-library"]; reach(app, reopenedLibrary); reopenedLibrary.tap()
        let retainedRows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-"))
        XCTAssertEqual(retainedRows.count, 1)
        XCTAssertTrue(retainedRows.firstMatch.label.contains("نسخة الملف"), retainedRows.firstMatch.label)
    }

    private func fixturePDF() -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "نسخة الملف", kCGPDFContextAuthor as String: "اختبار المحبرة"]
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400), format: format).pdfData { canvas in
            canvas.beginPage()
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
            let content = ("نسخة الملف الأصلية\n\nيُستعاد الملف إلى سجل الكتاب نفسه.") as NSString
            content.draw(in: CGRect(x: 22, y: 30, width: 256, height: 330), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph])
        }
    }
    private func keepPDF(_ app: XCUIApplication) {
        let keep = app.alerts.buttons["أبقه PDF"].firstMatch
        if keep.waitForExistence(timeout: 15) { keep.tap() }
    }
    private func app(_ fixture: String, epub: Data? = nil, paperIndex: Bool = false, storeID: String? = nil, pdf: Data? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID":storeID ?? UUID().uuidString,"MADAR_UI_MIHBARA_FIXTURE":fixture,"MADAR_UI_NOW":"2026-10-17T12:00:00+03:00","MADAR_UI_SIZE":"L","MADAR_UI_THEME":"light"]
        if let epub { app.launchEnvironment["MADAR_UI_MIHBARA_EPUB_BASE64"] = epub.base64EncodedString() }
        if let pdf { app.launchEnvironment["MADAR_UI_MIHBARA_IMPORT_PDF"] = pdf.base64EncodedString() }
        if paperIndex { app.launchEnvironment["MADAR_UI_MIHBARA_PAPER_INDEX_FIXTURE"] = "1" }
        return app
    }
    private func open(_ app: XCUIApplication) {
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout:20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout:10)); search.tap(); search.typeText("المحبرة")
        let door = app.buttons["mihbara-open"]; XCTAssertTrue(door.waitForExistence(timeout:5)); door.tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout:10), app.debugDescription)
    }
    private func useReaderMode(_ app: XCUIApplication, _ mode: String) {
        let settings = app.buttons["mihbara-reader-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:8), app.debugDescription); settings.tap()
        let modeButton = app.buttons["mihbara-reader-mode-\(mode)"]
        XCTAssertTrue(modeButton.waitForExistence(timeout:5), app.debugDescription)
        if !modeButton.isSelected { modeButton.tap(); XCTAssertTrue(modeButton.waitForSelection(timeout:5), app.debugDescription) }
        let close = app.buttons["mihbara-reader-settings-close"]
        XCTAssertTrue(close.waitForExistence(timeout:5), app.debugDescription); close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout:5), app.debugDescription)
    }
    private func undo(_ app: XCUIApplication) {
        let button = app.descendants(matching: .any)["mihbara-undo"].buttons["undo-button"]
        XCTAssertTrue(button.waitForExistence(timeout:8), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot(), a = XCTAttachment(screenshot:s); a.name = name; a.lifetime = .keepAlways; add(a)
        // xcodebuild can hang after the run and lose attachments; a shot folder keeps them on disk.
        if let dir = ProcessInfo.processInfo.environment["MADAR_SHOT_DIR"] { try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")) }
    }
    private func reach(_ app: XCUIApplication, _ button: XCUIElement) { for _ in 0..<7 where !button.isHittable { app.swipeUp(velocity:.slow) }; XCTAssertTrue(button.isHittable) }
    func testHomeWirdExplicitUnderstandingUndoAndRelaunch() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        XCTAssertFalse(app.buttons["tab-customize"].isHittable)
        XCTAssertTrue(app.buttons["mihbara-shelf-finished"].waitForExistence(timeout:8))
        shot(app,"M6-V01-home-L")
        var wird = app.buttons["mihbara-wird-open"]; reach(app,wird)
        // Owner, 22 Oct 2026 («٢»): the wird is one strip under the stand: hadith, opening words, progress.
        XCTAssertTrue(wird.label.contains("١٢ من ٤٢، بقي ٣٠ حديثًا"), wird.label)
        XCTAssertTrue(wird.label.contains("لا يؤمن أحدكم"), wird.label)
        XCTAssertTrue(wird.isHittable)
        shot(app,"M6-V01-desk-L"); wird.tap()
        XCTAssertTrue(app.textViews["mihbara-hadith-text"].waitForExistence(timeout:8)); XCTAssertTrue(String(describing: app.textViews["mihbara-hadith-text"].value).contains("لا يؤمن أحدكم")); shot(app,"M6-V01-hadith-L")
        let returnTo = app.buttons["mihbara-hadith-return"]; reach(app,returnTo); returnTo.tap()
        undo(app)
        shot(app,"M6-V01-return-undone-L")
        wird = app.buttons["mihbara-wird-open"]; XCTAssertTrue(wird.waitForExistence(timeout:8)); wird.tap()
        let understood = app.buttons["mihbara-hadith-understood"]; reach(app,understood); understood.tap()
        XCTAssertTrue(app.buttons["mihbara-wird-closed"].waitForExistence(timeout:8)); shot(app,"M6-V01-understood-L"); undo(app)
        XCTAssertTrue(app.buttons["mihbara-wird-open"].waitForExistence(timeout:8)); app.terminate(); app.launch(); open(app)
        reach(app,app.buttons["mihbara-book-continue"])
        // M6 audit: the open book says what is left in real pages and time, not a bare number.
        XCTAssertTrue(app.staticTexts["بقي ١٠٣ صفحات، نحو ساعتين"].exists, app.debugDescription)
        app.buttons["mihbara-book-continue"].tap()
        openPaperDetails(app)
        let page = app.textFields["mihbara-paper-position"]; XCTAssertTrue(page.waitForExistence(timeout:8)); page.tap(); page.press(forDuration:1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout:2) { app.menuItems["تحديد الكل"].tap() }
        else { page.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        page.typeText("١٤٨"); let done = app.toolbars.buttons["تمّ"]; if done.exists { done.tap() }; let save = app.buttons["mihbara-paper-save"]; reach(app, save); save.tap()
        app.terminate(); app.launch(); open(app); reach(app,app.buttons["mihbara-book-continue"]); app.buttons["mihbara-book-continue"].tap(); openPaperDetails(app); XCTAssertTrue(app.textFields["mihbara-paper-position"].waitForExistence(timeout:8)); XCTAssertTrue(String(describing: app.textFields["mihbara-paper-position"].value).contains("١٤٨")); shot(app,"M6-V01-position-L")
    }
    /// Since M6-V23 the paper-book card opens first; the position field lives in «الفهرس والتفاصيل».
    private func openPaperDetails(_ app: XCUIApplication) {
        let details = app.buttons["mihbara-paper-index-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, details); details.tap()
    }

    func testSpotlightBookIndexIsVisibleOptInAndCanBeTurnedOff() {
        continueAfterFailure = false
        let storeID = UUID().uuidString
        var app = self.app("empty", storeID: storeID); app.launch()
        let customize = app.buttons["tab-customize"]; XCTAssertTrue(customize.waitForExistence(timeout: 20)); customize.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("فهرسة")
        var toggle = app.switches["setting-core.spotlightIndex"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.staticTexts["يفهرس عناوين كتب المحبرة فقط؛ لا يُفهرس نص الكتب أو المؤلفون أو الملاحظات الخاصة."].exists)
        search.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        shot(app, "M7-spotlight-off-L")
        toggle.tap(); XCTAssertTrue(toggle.waitForValue("1", timeout: 8))
        app.terminate()
        app = self.app("empty", storeID: storeID); app.launch()
        let reopenedCustomize = app.buttons["tab-customize"]; XCTAssertTrue(reopenedCustomize.waitForExistence(timeout: 20)); reopenedCustomize.tap()
        let reopenedSearch = app.textFields["settings-search"]; XCTAssertTrue(reopenedSearch.waitForExistence(timeout: 10)); reopenedSearch.tap(); reopenedSearch.typeText("فهرسة")
        toggle = app.switches["setting-core.spotlightIndex"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "1", "The Spotlight choice must persist after relaunch.")
        reopenedSearch.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        shot(app, "M7-spotlight-on-L")
        toggle.tap(); XCTAssertTrue(toggle.waitForValue("0", timeout: 8))
    }

    /// M6 audit: the library says how many books there are, tells each kind apart, and counts what a search matches.
    func testLibraryCountsBooksNamesTheOldShelfAndCountsMatches() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let library = app.buttons["mihbara-library"]; reach(app, library); shot(app, "M6-shelf-covers-L"); library.tap()
        XCTAssertTrue(app.staticTexts["٣ كتب في مكتبتك."].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["قديمًا"].exists, "an old-shelf book must not be labelled finished")
        XCTAssertTrue(app.staticTexts["كتاب ورقي، ١٨٠ صفحة"].exists)
        shot(app, "M6-audit-library-L")
        let search = app.textFields["mihbara-library-search"]; search.tap(); search.typeText("ينتظر")
        XCTAssertTrue(app.staticTexts["mihbara-library-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mihbara-library-status"].label.hasPrefix("المطابق: كتاب واحد"), app.staticTexts["mihbara-library-status"].label)
    }
    /// A long press on a library row moves the book between shelves with the existing book.moveShelf command.
    func testLongPressMovesATableBookToFinished() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let library = app.buttons["mihbara-library"]; reach(app, library); library.tap()
        let readingLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "أقرؤه"))
        XCTAssertTrue(readingLabels.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        let before = readingLabels.count
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-")).containing(NSPredicate(format: "label == %@", "أقرؤه")).firstMatch
        row.press(forDuration: 1.2)
        let finish = app.buttons["أنهيته"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), app.debugDescription); shot(app, "M6-audit-shelf-menu-L"); finish.tap()
        let fewer = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _, _ in readingLabels.count == before - 1 }), object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fewer], timeout: 8), .completed, "before \(before), after \(readingLabels.count)")
    }
    func testDeletingBookHidesItFromShelvesAndUndoRestoresIt() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let library = app.buttons["mihbara-library"]; reach(app, library); library.tap()
        let book = app.staticTexts["رحلة القراءة"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-J13-delete-before-L")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-library-book-")).containing(NSPredicate(format: "label CONTAINS %@", "رحلة القراءة")).firstMatch
        row.press(forDuration: 1.2)
        let remove = app.buttons["mihbara-book-delete"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), app.debugDescription); remove.tap()
        let confirm = app.buttons["احذف من مكتبتي"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "M6-J13-delete-confirm-L")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "يبقى عنوانه وسجل جلسات القراءة")).firstMatch.exists, app.debugDescription)
        confirm.tap()
        XCTAssertTrue(book.waitForNonExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-J13-delete-after-L")
        undo(app)
        XCTAssertTrue(app.staticTexts["رحلة القراءة"].waitForExistence(timeout: 8), app.debugDescription)
    }
    func testEmptyShelfPaperAddAndUndo() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app); shot(app,"M6-V01-empty-L")
        app.buttons["mihbara-add-paper"].tap()
        let paperSource = app.descendants(matching: .any)["mihbara-add-source-paper"]
        XCTAssertTrue(paperSource.waitForExistence(timeout:5)); paperSource.tap()
        let title = app.textFields["mihbara-paper-title"]; XCTAssertTrue(title.waitForExistence(timeout:8)); title.tap(); title.typeText("كتابي الأول")
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("٢٥٠"); if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let save = app.buttons["mihbara-paper-save"]; reach(app,save); shot(app,"M6-V01-add-paper-L"); save.tap()
        XCTAssertTrue(app.staticTexts["كتابي الأول"].firstMatch.waitForExistence(timeout:8)); shot(app, "M6-shared-undo-glass-L"); undo(app)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout:8))
    }
    func testPaperIndexUsesEditableChapterRowsAndOneUndoableSave() {
        continueAfterFailure = false; let app = app("empty", paperIndex: true); app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        let title = app.textFields["mihbara-paper-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(title.value as? String, "دفتر البدايات")
        XCTAssertEqual(app.textFields["mihbara-paper-chapter-title-0"].value as? String, "مدخل إلى القراءة")
        shot(app, "M6-V20-paper-index-L")
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            .press(forDuration: 0.33, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.79)))
        shot(app, "M6-V20-paper-index-s1-L")
        let save = app.buttons["mihbara-paper-save"]; reach(app, save); save.tap()
        XCTAssertTrue(app.staticTexts["دفتر البدايات"].waitForExistence(timeout: 8))
        undo(app)
        XCTAssertTrue(app.staticTexts["أضف كتابك الأول"].waitForExistence(timeout: 8))
    }
    func testPaperBookCardOpensPrefilledIndexEditorAndUndoRestoresMissingIndex() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        let title = app.textFields["mihbara-paper-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, title)
        title.tap(); title.typeText("كتاب ورقي تجريبي")
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("١٢٠")
        app.buttons["mihbara-paper-shelf"].tap()
        let wantShelf = app.buttons["أبي أقرأه"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 5), app.debugDescription)
        wantShelf.tap()
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let saveBook = app.buttons["mihbara-paper-save"]; reach(app, saveBook); saveBook.tap()

        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 { homeScroll.swipeDown(velocity: .slow) }
        let wantShelfTab = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelfTab.isHittable, app.debugDescription)
        wantShelfTab.tap()
        let book = app.otherElements["mihbara-wall-want"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-book-")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()
        let prompt = app.buttons["mihbara-paper-index-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["صوّر فهرس طبعتك أو أضف عناوينه وصفحاته يدويًا"].exists)
        shot(app, "M6-V23-index-guidance-L")
        XCTAssertTrue(app.buttons["mihbara-paper-start"].exists)
        XCTAssertTrue(app.buttons["mihbara-paper-index-details"].exists)
        app.buttons["mihbara-paper-index-details"].tap()
        let savedPosition = app.textFields["mihbara-paper-position"]
        XCTAssertTrue(savedPosition.waitForExistence(timeout: 8), app.debugDescription)
        reach(app, savedPosition); savedPosition.tap(); savedPosition.press(forDuration: 1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout: 2) { app.menuItems["تحديد الكل"].tap() }
        else { savedPosition.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        savedPosition.typeText("٤٧")
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let savePosition = app.buttons["mihbara-paper-save"]; reach(app, savePosition); savePosition.tap()
        XCTAssertTrue(app.buttons["mihbara-paper-index-prompt"].waitForExistence(timeout: 8), app.debugDescription)
        let positionSummary = app.staticTexts["mihbara-paper-position-summary"]
        XCTAssertTrue(positionSummary.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(positionSummary.label.contains("٤٧"), positionSummary.label)
        XCTAssertTrue(app.buttons["mihbara-paper-start"].label.contains("واصل القراءة"))
        shot(app, "M6-V23-page-progress-after-L")
        app.buttons["mihbara-paper-start"].tap()
        let continueBook = app.buttons["mihbara-book-continue"]
        reach(app, continueBook); continueBook.tap()
        shot(app, "M6-V23-paper-card-s1-L")

        app.buttons["mihbara-paper-index-details"].tap()
        let chapter = app.textFields["mihbara-paper-chapter-title-0"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 8), app.debugDescription)
        chapter.tap(); chapter.typeText("بداية الطريق")
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let saveIndex = app.buttons["mihbara-paper-save"]; reach(app, saveIndex); saveIndex.tap()
        XCTAssertTrue(app.staticTexts["فهرس طبعتك"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["mihbara-paper-start"].tap()
        undo(app)

        let savedBook = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(savedBook.waitForExistence(timeout: 8), app.debugDescription); savedBook.tap()
        XCTAssertTrue(app.buttons["mihbara-paper-index-prompt"].waitForExistence(timeout: 8), app.debugDescription)
    }

    func testLongPaperTitleKeepsReadingAndDetailsActionsReachable() {
        continueAfterFailure = false; let app = app("empty"); app.launch(); open(app)
        app.buttons["mihbara-add-paper"].tap()
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        let titleText = "مدخل طويل إلى القراءة العربية وفنون المطالعة في مجالس العلم وما وراءها"
        let title = app.textFields["mihbara-paper-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        title.tap(); title.typeText(titleText)
        let author = app.textFields["mihbara-paper-author"]; author.tap(); author.typeText("من مكتبتي")
        let pages = app.textFields["mihbara-paper-pages"]; pages.tap(); pages.typeText("١٢٠")
        app.buttons["mihbara-paper-shelf"].tap()
        let wantShelf = app.buttons["أبي أقرأه"]
        XCTAssertTrue(wantShelf.waitForExistence(timeout: 5), app.debugDescription); wantShelf.tap()
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let save = app.buttons["mihbara-paper-save"]; reach(app, save); save.tap()

        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 { homeScroll.swipeDown(velocity: .slow) }
        let wantShelfTab = app.buttons["mihbara-shelf-want"]
        XCTAssertTrue(wantShelfTab.isHittable, app.debugDescription); wantShelfTab.tap()
        let book = app.otherElements["mihbara-wall-want"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mihbara-book-")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); book.tap()

        let details = app.buttons["mihbara-paper-index-details"]
        let start = app.buttons["mihbara-paper-start"]
        XCTAssertTrue(details.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(details.isHittable, app.debugDescription)
        XCTAssertTrue(start.isHittable, app.debugDescription)
        details.tap()
        let position = app.textFields["mihbara-paper-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 8), app.debugDescription)
        position.tap(); position.press(forDuration: 1.1)
        if app.menuItems["تحديد الكل"].waitForExistence(timeout: 2) { app.menuItems["تحديد الكل"].tap() }
        else { position.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)) }
        position.typeText("٤٧")
        if app.toolbars.buttons["تمّ"].exists { app.toolbars.buttons["تمّ"].tap() }
        let savePosition = app.buttons["mihbara-paper-save"]; reach(app, savePosition); savePosition.tap()

        XCTAssertTrue(app.staticTexts["mihbara-paper-position-summary"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-paper-start"].label.contains("واصل القراءة"))
        XCTAssertFalse(app.staticTexts["mihbara-paper-title-pinned"].exists, app.debugDescription)
        shot(app, "M6-V23-long-title-actions-L")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        let pinnedTitle = app.staticTexts["mihbara-paper-title-pinned"]
        XCTAssertTrue(pinnedTitle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(pinnedTitle.isHittable, app.debugDescription)
        XCTAssertTrue(pinnedTitle.label.contains("مدخل طويل إلى القراءة"), pinnedTitle.label)
        XCTAssertTrue(details.isHittable, app.debugDescription)
        XCTAssertTrue(start.isHittable, app.debugDescription)
        shot(app, "M6-V23-long-title-actions-s1-L")
        details.tap()
        XCTAssertTrue(app.textFields["mihbara-paper-position"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(String(describing: app.textFields["mihbara-paper-position"].value).contains("٤٧"))
    }

    func testAddBookSourcesShowsV1FormatsAndHonestEmptyState() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let addBook = app.buttons["mihbara-add-paper"]
        XCTAssertTrue(addBook.label.contains("أضف كتابًا"))
        addBook.tap()
        XCTAssertTrue(app.staticTexts["أضف كتابًا"].waitForExistence(timeout:8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-add-source-file"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-add-source-paper"].exists)
        XCTAssertTrue(app.buttons["mihbara-add-source-goodreads"].exists)
        XCTAssertTrue(app.staticTexts["PDF مصوّر"].exists)
        XCTAssertTrue(app.staticTexts["لا يوجد ملف وصل مؤخرًا"].exists)
        XCTAssertFalse(app.staticTexts["تصدير الشاملة"].exists)
        shot(app, "M6-V16-add-L")
        app.descendants(matching: .any)["mihbara-add-source-paper"].tap()
        XCTAssertTrue(app.textFields["mihbara-paper-title"].waitForExistence(timeout:8), app.debugDescription)
    }
    func testPrivateNotebookOpensWithTheAlreadyUnlockedApp() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let notebook = app.buttons["mihbara-notebook"]; reach(app, notebook); notebook.tap()
        XCTAssertTrue(app.staticTexts["سر لا يظهر قبل المصادقة"].waitForExistence(timeout:8), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-notebook-unlock"].exists)
        shot(app, "UX-01-private-notebook-L")
        app.buttons["mihbara-notebook-close"].tap()
    }
    func testRahlOpeningChoiceResetUndoAndRelaunch() {
        continueAfterFailure = false; let app = app("home"); app.launch(); open(app)
        let preferences = app.buttons["mihbara-opening-preference"]; reach(app, preferences); preferences.tap()
        let afterFajr = app.buttons["mihbara-rahlOpens-afterFajr"]
        let untilDone = app.buttons["mihbara-rahlOpens-untilDone"]
        let manual = app.buttons["mihbara-rahlOpens-manual"]
        XCTAssertTrue(afterFajr.waitForExistence(timeout:8)); shot(app,"M6-V02-opening-L")
        XCTAssertEqual(afterFajr.value as? String, "محدد")
        untilDone.tap(); XCTAssertEqual(untilDone.value as? String, "محدد")
        // The undo runs a command first, so wait for the restored choice rather than reading it at once.
        undo(app); XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'محدد'"), object: afterFajr)], timeout: 5), .completed)
        manual.tap(); XCTAssertEqual(manual.value as? String, "محدد")
        func selected(_ element: XCUIElement) -> XCTWaiter.Result { XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'محدد'"), object: element)], timeout: 5) }
        app.buttons["mihbara-rahlOpens-reset"].tap()
        XCTAssertEqual(selected(afterFajr), .completed)
        undo(app); XCTAssertEqual(selected(manual), .completed)
        app.buttons["mihbara-rahlOpens-close"].tap(); app.terminate(); app.launch(); open(app)
        reach(app, preferences); preferences.tap()
        XCTAssertEqual(app.buttons["mihbara-rahlOpens-manual"].value as? String, "محدد")
    }

    func testSunnahDrawerUsesRealProgressAndOpensWirdAndImport() {
        continueAfterFailure = false
        let app = app("home"); app.launch(); open(app)
        let drawer = app.buttons["mihbara-sunnah-drawer"]
        reach(app, drawer)
        shot(app, "M6-V15-drawer-L")
        XCTAssertEqual(drawer.value as? String, "مغلق")
        drawer.tap()
        let read = app.buttons["mihbara-sunnah-drawer-read"]
        reach(app, read)
        XCTAssertTrue(app.staticTexts["فهمت ١٢ حديثًا من ٤٢"].exists)
        XCTAssertFalse(app.staticTexts["رياض الصالحين"].exists)
        reach(app, app.buttons["mihbara-sunnah-drawer-add"])
        app.swipeUp(velocity: .slow)
        shot(app, "M6-V15-drawer-s1-L")
        read.tap()
        XCTAssertTrue(app.textViews["mihbara-hadith-text"].waitForExistence(timeout: 8))
        app.buttons["تمّ"].tap()
        let add = app.buttons["mihbara-sunnah-drawer-add"]; reach(app, add); add.tap()
        XCTAssertTrue(app.buttons["mihbara-add-source-file"].waitForExistence(timeout: 8))
        app.buttons["mihbara-add-back"].tap()
        XCTAssertTrue(drawer.waitForExistence(timeout: 8))
        reach(app, drawer); drawer.tap()
        XCTAssertEqual(drawer.value as? String, "مغلق")
        XCTAssertFalse(app.buttons["mihbara-sunnah-drawer-add"].exists)
    }

    func testLocalEPUBOpensInArabicReaderAndClosesBackToItsShelf() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        // The book being read sits open on the desk (owner, 21 Oct), not on the shelf.
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["كتاب اختبار القارئ"].exists)
        XCTAssertTrue(app.staticTexts["تأمل في القراءة"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.waitForExistence(timeout: 12), app.debugDescription)
        let printPage = app.staticTexts["mihbara-reader-print-page"]
        XCTAssertTrue(printPage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(printPage.label.contains("بحسب الملف"), printPage.label)
        XCTAssertTrue(printPage.label.contains("٤٥٣"), printPage.label)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-progress"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-settings"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-contents"].exists)
        XCTAssertTrue(app.buttons["mihbara-reader-listen"].exists)
        shot(app, "M6-V06-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        let defaultSize = app.buttons["mihbara-reader-size-4"]
        XCTAssertTrue(defaultSize.waitForExistence(timeout: 5))
        XCTAssertTrue(defaultSize.isSelected)
        app.buttons["mihbara-reader-size-5"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-amiri"].isSelected)
        app.buttons["mihbara-reader-font-thmanyahSans"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].waitForSelection(timeout: 5))
        shot(app, "M6-V07-font-sheet-L")
        XCTAssertTrue(app.buttons["mihbara-reader-settings-close"].isHittable)
        app.buttons["mihbara-reader-settings-close"].tap()
        sleep(2); shot(app, "M6-V07-font-sans-L")
        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSans"].isSelected)
        app.buttons["mihbara-reader-font-thmanyahSerif"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-font-thmanyahSerif"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        sleep(2); shot(app, "M6-V07-font-serif-L")
        // Page options: change each, undo the last, then reset to the agreed defaults.
        app.buttons["mihbara-reader-settings"].tap()
        let more = app.buttons["mihbara-reader-more"]; XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        let footerBar = app.buttons["mihbara-reader-footer-bar"]
        for _ in 0..<4 where !footerBar.isHittable { app.swipeUp(velocity: .slow) }
        app.buttons["mihbara-reader-lineSpacing-3"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-3"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-margins-1"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-margins-1"].waitForSelection(timeout: 5))
        let justify = app.switches["mihbara-reader-justify"], heavier = app.switches["mihbara-reader-heavier"]
        XCTAssertEqual(justify.value as? String, "1"); XCTAssertEqual(heavier.value as? String, "0")
        heavier.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(heavier.waitForValue("1", timeout: 5))
        footerBar.tap()
        XCTAssertTrue(footerBar.waitForSelection(timeout: 5))
        shot(app, "M6-V07-options-changed-L")
        let undo = app.descendants(matching: .any)["mihbara-reader-undo"].buttons["undo-button"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-footer-full"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-3"].isSelected)
        footerBar.tap(); XCTAssertTrue(footerBar.waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-progress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["mihbara-reader-print-page"].exists)
        sleep(2); shot(app, "M6-V07-options-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        if !app.buttons["mihbara-reader-reset"].exists { app.buttons["mihbara-reader-more"].tap() }
        let reset = app.buttons["mihbara-reader-reset"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp(velocity: .slow) }
        reset.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-footer-full"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-2"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-margins-2"].isSelected)
        XCTAssertEqual(app.switches["mihbara-reader-heavier"].value as? String, "0")
        for _ in 0..<4 { app.swipeDown(velocity: .slow); if app.buttons["mihbara-reader-size-4"].isHittable { break } }
        XCTAssertTrue(app.buttons["mihbara-reader-size-4"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-font-amiri"].isSelected)
        shot(app, "M6-V07-sheet-L")
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.staticTexts["mihbara-reader-print-page"].waitForExistence(timeout: 5))
        app.buttons["mihbara-reader-contents"].tap()
        XCTAssertTrue(app.staticTexts["فهرس الكتاب"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-contents-close"].isHittable)
        app.buttons["mihbara-reader-contents-close"].tap()
        app.buttons["mihbara-reader-close"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-book-continue"].waitForExistence(timeout: 8))
    }

    func testArabicExpandedReaderSettingsPersistAcrossRelaunchAndUndoReset() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let epub = try Data(contentsOf: fixtureURL)
        let storeID = UUID().uuidString
        let app = app("reader", epub: epub, storeID: storeID)
        app.launch(); open(app)
        var book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-settings"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["mihbara-reader-settings"].tap()
        let more = app.buttons["mihbara-reader-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription); more.tap()

        let lineSpacing = app.buttons["mihbara-reader-lineSpacing-3"]
        reach(app, lineSpacing); lineSpacing.tap()
        XCTAssertTrue(lineSpacing.waitForSelection(timeout: 8), app.debugDescription)
        let margins = app.buttons["mihbara-reader-margins-1"]
        reach(app, margins); margins.tap()
        XCTAssertTrue(margins.waitForSelection(timeout: 8), app.debugDescription)
        let justify = app.switches["mihbara-reader-justify"]
        XCTAssertEqual(justify.value as? String, "1", app.debugDescription); justify.tap()
        XCTAssertTrue(justify.waitForValue("0", timeout: 8), app.debugDescription)
        let heavier = app.switches["mihbara-reader-heavier"]
        XCTAssertEqual(heavier.value as? String, "0", app.debugDescription); heavier.tap()
        XCTAssertTrue(heavier.waitForValue("1", timeout: 8), app.debugDescription)
        let footerBar = app.buttons["mihbara-reader-footer-bar"]
        reach(app, footerBar); footerBar.tap()
        XCTAssertTrue(footerBar.waitForSelection(timeout: 8), app.debugDescription)
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-progress"].waitForExistence(timeout: 8), app.debugDescription)

        app.terminate(); app.launch(); open(app)
        book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-settings"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["mihbara-reader-settings"].tap()
        let reopenedMore = app.buttons["mihbara-reader-more"]
        XCTAssertTrue(reopenedMore.waitForExistence(timeout: 5), app.debugDescription); reopenedMore.tap()
        shot(app, "M6-V24-reader-settings-reopened-L")
        let reopenedSpacing = app.buttons["mihbara-reader-lineSpacing-3"]
        reach(app, reopenedSpacing); XCTAssertTrue(reopenedSpacing.isSelected, app.debugDescription)
        let reopenedMargins = app.buttons["mihbara-reader-margins-1"]
        reach(app, reopenedMargins); XCTAssertTrue(reopenedMargins.isSelected, app.debugDescription)
        XCTAssertEqual(app.switches["mihbara-reader-justify"].value as? String, "0", app.debugDescription)
        XCTAssertEqual(app.switches["mihbara-reader-heavier"].value as? String, "1", app.debugDescription)
        let reopenedFooterBar = app.buttons["mihbara-reader-footer-bar"]
        reach(app, reopenedFooterBar); XCTAssertTrue(reopenedFooterBar.isSelected, app.debugDescription)
        shot(app, "M6-V24-reader-settings-reopened-s1-L")

        let reset = app.buttons["mihbara-reader-reset"]
        reach(app, reset); reset.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-2"].waitForSelection(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-reader-margins-2"].isSelected, app.debugDescription)
        XCTAssertTrue(app.switches["mihbara-reader-justify"].waitForValue("1", timeout: 8), app.debugDescription)
        XCTAssertTrue(app.switches["mihbara-reader-heavier"].waitForValue("0", timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-reader-footer-full"].waitForSelection(timeout: 8), app.debugDescription)
        let undo = app.descendants(matching: .any)["mihbara-reader-undo"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V24-reader-settings-undo-L")
        undo.tap()
        let restoredSpacing = app.buttons["mihbara-reader-lineSpacing-3"]
        reach(app, restoredSpacing); XCTAssertTrue(restoredSpacing.waitForSelection(timeout: 8), app.debugDescription)
        let restoredMargins = app.buttons["mihbara-reader-margins-1"]
        reach(app, restoredMargins); XCTAssertTrue(restoredMargins.isSelected, app.debugDescription)
        XCTAssertEqual(app.switches["mihbara-reader-justify"].value as? String, "0", app.debugDescription)
        XCTAssertEqual(app.switches["mihbara-reader-heavier"].value as? String, "1", app.debugDescription)
        let restoredFooterBar = app.buttons["mihbara-reader-footer-bar"]
        reach(app, restoredFooterBar); XCTAssertTrue(restoredFooterBar.isSelected, app.debugDescription)
    }

    func testReaderWordCardHighlightsParagraphUndoesNotesAndCopies() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        useReaderMode(app, "scroll")
        var paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)
        sleep(1)
        let closeReader = app.buttons["mihbara-reader-close"]
        let readerFooter = app.descendants(matching: .any)["mihbara-reader-print-page"]
        XCTAssertTrue(closeReader.exists, app.debugDescription)
        // A long press selects a word; Madar's card replaces the system menu.
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        let card = app.descendants(matching: .any)["mihbara-word-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(closeReader.exists, "The word card should have a clear page without reader chrome.\n\(app.debugDescription)")
        XCTAssertFalse(readerFooter.exists, "The reader footer should leave room to read behind the word card.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["mihbara-word-lookup"].exists || app.staticTexts["mihbara-word-lookup-unavailable"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-word-note"].exists)
        XCTAssertTrue(app.buttons["mihbara-word-copy"].exists)
        XCTAssertFalse(app.buttons["mihbara-highlight-yellow"].isSelected)
        shot(app, "M6-V08-card-L")
        app.swipeUp(velocity: .slow)
        sleep(1); shot(app, "M6-V08-card-s1-L")
        XCTAssertTrue(card.exists, app.debugDescription)
        app.buttons["mihbara-word-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout:5))
        XCTAssertTrue(closeReader.waitForExistence(timeout:5), app.debugDescription)
        useReaderMode(app, "pages")
        paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        XCTAssertTrue(card.waitForExistence(timeout:8), app.debugDescription)
        app.buttons["mihbara-highlight-yellow"].tap()
        XCTAssertTrue(app.buttons["mihbara-highlight-yellow"].waitForSelection(timeout: 8), app.debugDescription)
        let quoteCard = app.buttons["mihbara-quote-card-open"]
        XCTAssertTrue(quoteCard.waitForExistence(timeout: 5), app.debugDescription)
        quoteCard.tap()
        let quotePreview = app.descendants(matching: .any)["mihbara-quote-card-preview"]
        XCTAssertTrue(quotePreview.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(quotePreview.label.contains("كتاب اختبار القارئ"), quotePreview.label)
        XCTAssertTrue(quotePreview.label.contains("من مكتبتك"), quotePreview.label)
        let quotedSentence = "القراءة باب يدخل منه الإنسان إلى خبرات من سبقه"
        XCTAssertEqual(quotePreview.label.components(separatedBy: quotedSentence).count - 1, 1, quotePreview.label)
        XCTAssertFalse(quotePreview.label.contains("shamela.ws"), quotePreview.label)
        shot(app, "M6-V08-quote-card-L")
        app.buttons["mihbara-quote-card-close"].tap()
        XCTAssertTrue(quoteCard.waitForExistence(timeout: 5), app.debugDescription)
        sleep(1); shot(app, "M6-V08-highlight-L")
        app.buttons["mihbara-highlight-green"].tap()
        XCTAssertTrue(app.buttons["mihbara-highlight-green"].waitForSelection(timeout: 8))
        XCTAssertFalse(app.buttons["mihbara-highlight-yellow"].isSelected)
        app.buttons["mihbara-word-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(closeReader.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(readerFooter.waitForExistence(timeout: 5), app.debugDescription)
        let undo = app.descendants(matching: .any)["mihbara-reader-toast"].buttons["undo-button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), app.debugDescription); undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 8))
        // Tapping the highlighted paragraph reopens its card with the restored colour.
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1); shot(app, "M6-V08-retap-L")
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-highlight-yellow"].waitForSelection(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["mihbara-word-lookup"].exists)
        let copiedButton = app.buttons["mihbara-word-copy"]
        copiedButton.tap()
        XCTAssertTrue(copiedButton.waitForLabel("نُسخت", timeout: 2), app.debugDescription)
        app.buttons["mihbara-word-note"].tap()
        let text = app.textViews["mihbara-note-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        text.typeText("فكرة")
        shot(app, "M6-V08-note-L")
        app.buttons["mihbara-note-save"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 8))
        XCTAssertFalse(card.exists)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-toast"].waitForExistence(timeout: 5), app.debugDescription)
        sleep(1); shot(app, "M6-V08-saved-L")
    }

    func testReaderShowsUnmarkedAyahWithItsOriginalInlineText() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "scan-order-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixture)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        useReaderMode(app, "scroll")
        let verse = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لَقَدْ")).firstMatch
        XCTAssertTrue(verse.waitForExistence(timeout: 20), app.debugDescription)
        let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "تَقْوِيمٍ")).firstMatch
        XCTAssertTrue(text.exists, app.debugDescription)
        shot(app, "M6-21-unmarked-ayah-reader-L")
        app.buttons["mihbara-reader-close"].tap()
    }

    func testReaderColoursVersesAndOpensFootnoteInPlace() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        useReaderMode(app, "scroll")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "اقْرَأْ")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        sleep(1); shot(app, "M6-V09-verse-L")
        let marker = app.links["١"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        let closeReader = app.buttons["mihbara-reader-close"]
        let readerFooter = app.descendants(matching: .any)["mihbara-reader-print-page"]
        XCTAssertTrue(readerFooter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(readerFooter.label.contains("٤٥٣"), readerFooter.label)
        marker.tap()
        let card = app.descendants(matching: .any)["mihbara-footnote-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(closeReader.exists, "The footnote should have a clear page without reader chrome.\n\(app.debugDescription)")
        XCTAssertFalse(readerFooter.exists, "The reader footer should leave room to read behind the footnote.\n\(app.debugDescription)")
        let text = app.staticTexts["mihbara-footnote-text"]
        XCTAssertTrue(text.label.contains("هامش تجريبي"), text.label)
        XCTAssertFalse(text.label.contains("عودة إلى المتن"), text.label)
        // The reader stayed on the chapter rather than jumping to the notes file.
        sleep(1); shot(app, "M6-V09-footnote-L")
        let passage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 5), app.debugDescription)
        app.swipeUp(velocity: .slow)
        sleep(1); shot(app, "M6-V09-footnote-s1-L")
        XCTAssertTrue(card.exists)
        app.buttons["mihbara-footnote-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(closeReader.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(readerFooter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(readerFooter.label.contains("٤٥٣"), readerFooter.label)
    }

    func testReaderNightThemeScrollKeepsPlaceAndResets() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        sleep(3); shot(app, "M6-V10-open-L")
        app.buttons["mihbara-reader-settings"].tap()
        let auto = app.buttons["mihbara-reader-theme-auto"]
        XCTAssertTrue(auto.waitForExistence(timeout: 5)); XCTAssertTrue(auto.isSelected)
        for theme in ["paper", "warm", "calm", "black"] { XCTAssertTrue(app.buttons["mihbara-reader-theme-\(theme)"].exists, theme) }
        app.buttons["mihbara-reader-theme-night"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-theme-night"].waitForSelection(timeout: 5))
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-settings-close"].waitForNonExistence(timeout: 5))
        app.buttons["mihbara-reader-contents"].tap()
        let contentsClose = app.buttons["mihbara-reader-contents-close"]
        XCTAssertTrue(contentsClose.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V19-contents-night-L")
        contentsClose.tap()
        XCTAssertTrue(contentsClose.waitForNonExistence(timeout: 5))
        let marker = app.links["١"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 8), app.debugDescription)
        marker.tap()
        let footnote = app.descendants(matching: .any)["mihbara-footnote-card"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V09-footnote-night-L")
        app.buttons["mihbara-footnote-close"].tap()
        XCTAssertTrue(footnote.waitForNonExistence(timeout: 5))
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 8), app.debugDescription)
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).press(forDuration: 1.2)
        let wordCard = app.descendants(matching: .any)["mihbara-word-card"]
        XCTAssertTrue(wordCard.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V08-card-night-L")
        app.buttons["mihbara-word-note"].tap()
        let noteEditor = app.textViews["mihbara-note-text"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 8), app.debugDescription)
        shot(app, "M6-V08-note-night-L")
        app.buttons["mihbara-note-cancel"].tap()
        XCTAssertTrue(noteEditor.waitForNonExistence(timeout: 5))
        app.buttons["mihbara-word-close"].tap()
        XCTAssertTrue(wordCard.waitForNonExistence(timeout: 5))
        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-mode-scroll"].waitForExistence(timeout: 5))
        app.buttons["mihbara-reader-mode-scroll"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-mode-scroll"].waitForSelection(timeout: 5))
        shot(app, "M6-V10-sheet-night-L")
        app.buttons["mihbara-reader-settings-close"].tap()
        let printPage = app.staticTexts["mihbara-reader-print-page"]
        XCTAssertTrue(printPage.waitForExistence(timeout: 8))
        sleep(2)
        XCTAssertTrue(printPage.label.contains("٤٥٣"), printPage.label)
        shot(app, "M6-V10-night-scroll-L")
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.swipeUp(velocity: .slow)
        sleep(2); shot(app, "M6-V10-night-scroll-s1-L")
        app.swipeUp(velocity: .slow)
        sleep(2); shot(app, "M6-V10-night-scroll-s2-L")
        app.buttons["mihbara-reader-settings"].tap()
        if !app.buttons["mihbara-reader-reset"].exists { app.buttons["mihbara-reader-more"].tap() }
        let reset = app.buttons["mihbara-reader-reset"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp(velocity: .slow) }
        reset.tap()
        for _ in 0..<4 { app.swipeDown(velocity: .slow); if app.buttons["mihbara-reader-theme-auto"].isHittable { break } }
        XCTAssertTrue(app.buttons["mihbara-reader-theme-auto"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-mode-pages"].isSelected)
    }

    func testEnglishReaderAutoScrollAdvancesAndStopsFromGlassControls() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is original synthetic fixture text")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)

        app.buttons["mihbara-reader-settings"].tap()
        let slow = app.buttons["mihbara-reader-autoScroll-slow"]
        XCTAssertFalse(slow.exists, "Speed choices belong to scrolling mode")
        let scroll = app.buttons["mihbara-reader-mode-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5)); scroll.tap()
        XCTAssertTrue(scroll.waitForSelection(timeout: 5))
        reach(app, slow)
        XCTAssertTrue(slow.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-reader-autoScroll-off"].isSelected)
        slow.tap()
        XCTAssertTrue(slow.waitForSelection(timeout: 5), app.debugDescription)
        shot(app, "M6-V22-auto-scroll-sheet-L")

        let fast = app.buttons["mihbara-reader-autoScroll-fast"]
        for _ in 0..<4 where !fast.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(fast.waitForExistence(timeout: 5), app.debugDescription); fast.tap()
        XCTAssertTrue(fast.waitForSelection(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-reader-mode-scroll"].isSelected, app.debugDescription)
        app.buttons["mihbara-reader-settings-close"].tap()

        let player = app.descendants(matching: .any)["mihbara-auto-scroll-player"]
        let position = app.staticTexts["mihbara-auto-scroll-position"]
        XCTAssertTrue(player.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(position.waitForExistence(timeout: 5), app.debugDescription)
        let firstPosition = position.label
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", firstPosition), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 14), .completed, app.debugDescription)

        let pause = app.buttons["mihbara-auto-scroll-play-pause"]
        pause.tap()
        XCTAssertTrue(app.staticTexts["التمرير متوقف مؤقتًا"].waitForExistence(timeout: 4), app.debugDescription)
        pause.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "تمرير تلقائي")).firstMatch.waitForExistence(timeout: 4), app.debugDescription)
        app.buttons["mihbara-auto-scroll-stop"].tap()
        XCTAssertTrue(player.waitForNonExistence(timeout: 5), app.debugDescription)

        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-autoScroll-off"].waitForSelection(timeout: 5), app.debugDescription)
        app.buttons["mihbara-reader-settings-close"].tap()
    }

    func testFocusReaderAdvancesOneParagraphAndKeepsReadingChromeOutOfSight() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["mihbara-reader-settings"].tap()
        let calm = app.buttons["mihbara-reader-theme-calm"]
        XCTAssertTrue(calm.waitForExistence(timeout: 5), app.debugDescription); calm.tap()
        XCTAssertTrue(calm.waitForSelection(timeout: 5), app.debugDescription)
        let focus = app.buttons["mihbara-reader-mode-focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5), app.debugDescription); focus.tap()
        XCTAssertTrue(focus.waitForSelection(timeout: 5), app.debugDescription)
        app.buttons["mihbara-reader-settings-close"].tap()

        let previous = app.buttons["mihbara-focus-previous"]
        let next = app.buttons["mihbara-focus-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-footer-value"].waitForExistence(timeout: 5), app.debugDescription)
        next.tap()
        let positionReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != ''"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [positionReady], timeout: 8), .completed, app.debugDescription)
        let initialPosition = next.value as? String ?? ""
        XCTAssertFalse(initialPosition.isEmpty, "Advancing focus should expose its paragraph position\n\(app.debugDescription)")
        XCTAssertTrue(previous.exists)
        XCTAssertFalse(app.buttons["mihbara-reader-settings"].exists, "Focus mode should hide its reading chrome")
        shot(app, "M6-V11-focus-L")

        next.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialPosition), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 8), .completed, app.debugDescription)
        shot(app, "M6-V11-focus-s1-L")

        let nextMove = next.value as? String ?? ""
        next.tap()
        let movedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", nextMove), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [movedAgain], timeout: 8), .completed, app.debugDescription)
        sleep(1)
        shot(app, "M6-V11-focus-s2-L")
    }

    func testArabicListeningReadsParagraphsAndOffersSpeedControls() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "arabic-reader-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "القراءة باب يدخل")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        let listen = app.buttons["mihbara-reader-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 8), app.debugDescription); listen.tap()
        let player = app.descendants(matching: .any)["mihbara-listening-player"]
        if player.waitForExistence(timeout: 8) {
            let closeReader = app.buttons["mihbara-reader-close"]
            XCTAssertFalse(closeReader.exists, "The reader header should stay out of the listening view.\n\(app.debugDescription)")
            let paragraph = app.staticTexts["mihbara-listening-paragraph"]
            XCTAssertTrue(paragraph.waitForExistence(timeout: 5), app.debugDescription)
            let paragraphLabel = paragraph.label.filter { !["\u{2068}", "\u{2069}"].contains(String($0)) }
            XCTAssertTrue(paragraphLabel.contains("صوت عربي من جهازك"), app.debugDescription)
            XCTAssertTrue(paragraphLabel.contains("الفقرة"), app.debugDescription)
            XCTAssertTrue(app.buttons["mihbara-listening-speed-1"].exists, app.debugDescription)
            shot(app, "M6-V21-listening-L")

            let faster = app.buttons["mihbara-listening-speed-1_5"]
            XCTAssertTrue(faster.waitForExistence(timeout: 5), app.debugDescription); faster.tap()
            XCTAssertEqual(faster.value as? String, "السرعة الحالية", app.debugDescription)
            let pause = app.buttons["mihbara-listening-play-pause"]
            pause.tap()
            XCTAssertEqual(app.staticTexts["mihbara-listening-title"].label, "القراءة متوقفة مؤقتًا", app.debugDescription)
            pause.tap()
            app.buttons["mihbara-listening-stop"].tap()
            XCTAssertTrue(player.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(closeReader.waitForExistence(timeout: 5), "Stopping listening must restore the reader header.\n\(app.debugDescription)")
        } else {
            let alert = app.alerts["القارئ"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لا يتوفر صوت عربي")).firstMatch.exists, app.debugDescription)
            alert.buttons["حسنًا"].tap()
        }
    }

    func testEnglishWordCardSavesItsContextAndOnlyOffersSupportedTranslation() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is original synthetic fixture text")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 20), app.debugDescription)
        sleep(1)
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.14)).press(forDuration: 0.8)
        let card = app.descendants(matching: .any)["mihbara-word-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        let word = app.staticTexts["mihbara-word-title"]
        XCTAssertTrue(word.exists)
        XCTAssertEqual(word.label.split(whereSeparator: \.isWhitespace).count, 1, app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-word-save"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-word-lookup"].exists || app.staticTexts["mihbara-word-lookup-unavailable"].exists, app.debugDescription)
        shot(app, "M6-V14-word-L")
        app.buttons["mihbara-word-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mihbara-reader-toast"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.14)).press(forDuration: 0.8)
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["mihbara-word-saved"].waitForExistence(timeout: 5), app.debugDescription)

        let translate = app.buttons["mihbara-word-translate"]
        let needsDownload = app.descendants(matching: .any)["mihbara-translation-download"]
        let checking = app.descendants(matching: .any)["mihbara-translation-checking"]
        if translate.waitForExistence(timeout: 5) {
            shot(app, "M6-V14-translation-ready-L")
            translate.tap()
            let result = app.staticTexts["mihbara-translation-result"]
            let failure = app.staticTexts["mihbara-translation-error"]
            XCTAssertTrue(result.waitForExistence(timeout: 30) || failure.waitForExistence(timeout: 1), app.debugDescription)
        } else if needsDownload.waitForExistence(timeout: 2) {
            XCTAssertFalse(translate.exists)
        } else {
            XCTAssertFalse(checking.exists, app.debugDescription)
            XCTAssertFalse(translate.exists, app.debugDescription)
        }
    }

    func testEnglishEPUBReadsLeftToRightWithItsOwnSettings() throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english-import-poc", withExtension: "epub"))
        let app = app("reader", epub: try Data(contentsOf: fixtureURL)); app.launch(); open(app)
        let book = app.buttons["mihbara-book-continue"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), app.debugDescription); reach(app, book); book.tap()
        XCTAssertTrue(app.buttons["mihbara-reader-close"].waitForExistence(timeout: 20), app.debugDescription)
        sleep(4); shot(app, "M6-V13-reader-L")
        app.buttons["mihbara-reader-settings"].tap()
        XCTAssertTrue(app.staticTexts["كتاب إنجليزي · إعداداتك للإنجليزي"].waitForExistence(timeout: 5), app.debugDescription)
        let literata = app.buttons["mihbara-reader-font-literata"]
        let atkinson = app.buttons["mihbara-reader-font-atkinsonHyperlegible"]
        XCTAssertTrue(literata.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["mihbara-reader-font-sourceSerif"].exists)
        XCTAssertTrue(atkinson.exists)
        XCTAssertTrue(app.buttons["mihbara-reader-font-ibmPlexSerif"].exists)
        XCTAssertTrue(literata.isSelected)
        XCTAssertFalse(app.buttons["mihbara-reader-font-amiri"].exists)
        shot(app, "M6-V13-sheet-L")
        let more = app.buttons["mihbara-reader-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription); more.tap()
        atkinson.tap()
        XCTAssertTrue(atkinson.waitForSelection(timeout: 5), app.debugDescription)
        app.buttons["mihbara-reader-size-6"].tap()
        XCTAssertTrue(app.buttons["mihbara-reader-size-6"].waitForSelection(timeout: 5))
        for _ in 0..<5 where !app.buttons["mihbara-reader-lineSpacing-4"].isHittable { app.swipeUp(velocity: .slow) }
        app.buttons["mihbara-reader-lineSpacing-4"].tap()
        app.buttons["mihbara-reader-margins-1"].tap()
        let justify = app.switches["mihbara-reader-justify"]
        let heavier = app.switches["mihbara-reader-heavier"]
        let hyphenation = app.switches["mihbara-reader-hyphenation"]
        let wordSpacing = app.switches["mihbara-reader-wordSpacing"]
        XCTAssertTrue(justify.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(hyphenation.value as? String, "1")
        for _ in 0..<5 where !wordSpacing.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(wordSpacing.isHittable, app.debugDescription)
        hyphenation.tap()
        XCTAssertTrue(hyphenation.waitForValue("0", timeout: 5), app.debugDescription)
        wordSpacing.tap()
        XCTAssertTrue(wordSpacing.waitForValue("1", timeout: 5), app.debugDescription)
        heavier.tap()
        XCTAssertTrue(heavier.waitForValue("1", timeout: 5), app.debugDescription)
        let percentage = app.buttons["mihbara-reader-footer-percentage"]
        XCTAssertTrue(percentage.waitForExistence(timeout: 5), app.debugDescription)
        percentage.tap()
        XCTAssertTrue(percentage.waitForSelection(timeout: 5))
        shot(app, "M6-V13-sheet-s1-L")
        let reset = app.buttons["mihbara-reader-reset"]
        for _ in 0..<5 where !reset.isHittable { app.swipeUp(velocity: .slow) }
        reset.tap()
        XCTAssertTrue(literata.waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-size-4"].waitForSelection(timeout: 5))
        XCTAssertTrue(app.buttons["mihbara-reader-lineSpacing-2"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-margins-2"].isSelected)
        XCTAssertTrue(app.buttons["mihbara-reader-footer-remaining"].isSelected)
        XCTAssertEqual(justify.value as? String, "1")
        XCTAssertEqual(heavier.value as? String, "0")
        XCTAssertEqual(hyphenation.value as? String, "1")
        XCTAssertEqual(wordSpacing.value as? String, "0")
        app.buttons["mihbara-reader-settings-close"].tap()
        XCTAssertTrue(app.staticTexts["mihbara-reader-footer-value"].waitForExistence(timeout: 5))
        app.buttons["mihbara-reader-close"].tap()
        XCTAssertTrue(app.buttons["mihbara-add-paper"].waitForExistence(timeout: 10), app.debugDescription)
    }
}

private extension XCUIElement {
    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: self)], timeout: timeout) == .completed
    }
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: self)], timeout: timeout) == .completed
    }
    func waitForSelection(timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: self)], timeout: timeout) == .completed
    }
}
