import XCTest
import SwiftData
import PDFKit
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiaryYearbookIntegrationTests:XCTestCase {
    func testActualYearPagesPhotoOptionsCoverAndIndex() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryBook-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root),service=AppDiaryService(app:app);app.authorizeProtectedData()
        let context=ModelContext(container),a=Entry(),b=Entry(),note=MarginNote(),sealed=Letter()
        a.dayKey="2024-03-11";a.text="BOOK-FIRST";context.insert(a);b.dayKey="2024-04-11";b.text="BOOK-LAST";context.insert(b)
        note.targetDayKey=a.dayKey;note.writtenDayKey="2025-01-01";note.text="BOOK-MARGIN";context.insert(note)
        sealed.text="SEALED-BOOK-SECRET";context.insert(sealed)
        let photo = Media()
        photo.kind = "photo"; photo.data = Data([1, 2, 3]); context.insert(photo)
        let photoPage = DayPage()
        photoPage.dayKey = "2024-04-12"; photoPage.photoMediaID = photo.id; context.insert(photoPage)
        try context.save()
        let pages=try service.yearbookPages(year:2024,margins:true,sources:true,photos:true)
        XCTAssertEqual(pages.map(\.day.description),["2024-03-11","2024-04-11","2024-04-12"]);XCTAssertTrue(pages.first?.lines.contains{$0.text=="BOOK-MARGIN"}==true)
        XCTAssertEqual(pages.last?.media.map(\.id), [photo.id])
        let withoutPhotos = try service.yearbookPages(year:2024,margins:false,sources:false,photos:false)
        XCTAssertEqual(withoutPhotos.map(\.day.description), ["2024-03-11", "2024-04-11"])
        XCTAssertFalse(withoutPhotos.flatMap(\.lines).contains{$0.kind=="margin"})
        XCTAssertTrue(try service.yearbookPages(year:2020,margins:true,sources:true,photos:true).isEmpty)
        let seen = LockedFlags()
        AppDiaryService.exportBuildProbe = { seen.record(Thread.isMainThread) }
        defer { AppDiaryService.exportBuildProbe = nil }
        let writtenPages = Array(pages.prefix(2))
        let plain = try await service.exportYearbook(pages: writtenPages, year: 2024, index: false)
        defer { try? FileManager.default.removeItem(at: plain.url.deletingLastPathComponent()) }
        let indexed = try await service.exportYearbook(pages: writtenPages, year: 2024, index: true)
        XCTAssertEqual(seen.values, [false, false])
        defer{try? FileManager.default.removeItem(at:indexed.url.deletingLastPathComponent())}
        let p=try XCTUnwrap(PDFDocument(url:plain.url)),i=try XCTUnwrap(PDFDocument(url:indexed.url));XCTAssertEqual(p.pageCount,3);XCTAssertEqual(i.pageCount,4)
        XCTAssertTrue(i.string?.contains("BOOK-LAST")==true);XCTAssertFalse(i.string?.contains("SEALED-BOOK-SECRET")==true);XCTAssertNotEqual(i.page(at:0)?.string,i.page(at:1)?.string)
    }
}
