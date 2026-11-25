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
        let firstPreview = try await service.yearbookPreview(.init())
        XCTAssertTrue(firstPreview.yearIndex.years.contains(2024))
        let pages = try await service.yearbookPreview(.init(year: 2024), cachedYearIndex: firstPreview.yearIndex).pages
        XCTAssertEqual(pages.map(\.day.description),["2024-03-11","2024-04-11","2024-04-12"]);XCTAssertTrue(pages.first?.lines.contains{$0.text=="BOOK-MARGIN"}==true)
        XCTAssertEqual(pages.last?.media.map(\.id), [photo.id])
        let withoutPhotos = try await service.yearbookPreview(.init(year: 2024, margins: false, sources: false, photos: false)).pages
        XCTAssertEqual(withoutPhotos.map(\.day.description), ["2024-03-11", "2024-04-11"])
        XCTAssertFalse(withoutPhotos.flatMap(\.lines).contains{$0.kind=="margin"})
        let empty = try await service.yearbookPreview(.init(year: 2020))
        XCTAssertTrue(empty.pages.isEmpty)
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

    func testYearIndexReusesSameRevisionAndRefreshesAfterArchiveChangeAndNewYear() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryBook-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let formatter = ISO8601DateFormatter()
        var now = try XCTUnwrap(formatter.date(from: "2026-12-31T12:00:00+03:00"))
        let service = AppDiaryService(app: app, clock: { now })
        let context = ModelContext(container)

        let old = Entry()
        old.dayKey = "2024-03-11"
        old.text = "OLDER-YEAR"
        context.insert(old)
        try context.save()
        let initial = try await service.yearbookPreview(.init(year: 2024))
        XCTAssertEqual(initial.yearIndex.years, [2026, 2024])

        // A write has landed, but the session has not published its new revision yet.
        old.deletedAt = now
        old.deletionBarrierAt = now
        let addition = Entry()
        addition.dayKey = "2025-04-11"
        addition.text = "NEWLY-ADDED-YEAR"
        context.insert(addition)
        try context.save()
        let optionsOnly = try await service.yearbookPreview(.init(year: 2024, photos: false), cachedYearIndex: initial.yearIndex)
        XCTAssertEqual(optionsOnly.yearIndex.years, [2026, 2024])

        try app.reload()
        let updated = try await service.yearbookPreview(.init(year: 2025), cachedYearIndex: optionsOnly.yearIndex)
        XCTAssertEqual(updated.yearIndex.years, [2026, 2025])
        XCTAssertEqual(updated.pages.map(\.day.description), ["2025-04-11"])

        now = try XCTUnwrap(formatter.date(from: "2027-01-01T12:00:00+03:00"))
        let nextYear = try await service.yearbookPreview(.init(), cachedYearIndex: updated.yearIndex)
        XCTAssertEqual(nextYear.yearIndex.years, [2027, 2025])
    }
}
