import XCTest
import SwiftData
import PDFKit
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiaryYearbookIntegrationTests:XCTestCase {
    func testActualYearPagesPhotoOptionsCoverAndIndex() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryBook-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root),service=AppDiaryService(app:app);app.authorizeProtectedData()
        let context=ModelContext(container),a=Entry(),b=Entry(),note=MarginNote(),sealed=Letter()
        a.dayKey="2024-03-11";a.text="BOOK-FIRST";context.insert(a);b.dayKey="2024-04-11";b.text="BOOK-LAST";context.insert(b)
        note.targetDayKey=a.dayKey;note.writtenDayKey=b.dayKey;note.text="BOOK-MARGIN";context.insert(note)
        sealed.text="SEALED-BOOK-SECRET";context.insert(sealed);try context.save()
        let pages=try service.yearbookPages(year:2024,margins:true,sources:true,photos:true)
        XCTAssertEqual(pages.map(\.day.description),["2024-03-11","2024-04-11"]);XCTAssertTrue(pages.first?.lines.contains{$0.text=="BOOK-MARGIN"}==true)
        XCTAssertFalse(try service.yearbookPages(year:2024,margins:false,sources:false,photos:false).flatMap(\.lines).contains{$0.kind=="margin"})
        XCTAssertTrue(try service.yearbookPages(year:2020,margins:true,sources:true,photos:true).isEmpty)
        let plain=try service.exportYearbook(pages:pages,year:2024,index:false),indexed=try service.exportYearbook(pages:pages,year:2024,index:true)
        defer{try? FileManager.default.removeItem(at:plain.url.deletingLastPathComponent());try? FileManager.default.removeItem(at:indexed.url.deletingLastPathComponent())}
        let p=try XCTUnwrap(PDFDocument(url:plain.url)),i=try XCTUnwrap(PDFDocument(url:indexed.url));XCTAssertEqual(p.pageCount,3);XCTAssertEqual(i.pageCount,4)
        XCTAssertTrue(i.string?.contains("BOOK-LAST")==true);XCTAssertFalse(i.string?.contains("SEALED-BOOK-SECRET")==true);XCTAssertNotEqual(i.page(at:0)?.string,i.page(at:1)?.string)
    }
}
