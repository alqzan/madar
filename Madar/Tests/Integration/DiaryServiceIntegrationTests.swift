import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import UIKit
@testable import Madar

@MainActor final class DiaryServiceIntegrationTests: XCTestCase {
    func testLibraryPhotoKeepsOnlyASmallDecodableCopy() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1920, height: 1080), format: format).jpegData(withCompressionQuality: 0.9) { canvas in
            UIColor.systemBlue.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        }
        let copy = try XCTUnwrap(DiaryPhotoLibrary.smallCopy(of: source))
        let thumbnail = try XCTUnwrap(UIImage(data: copy)?.cgImage)
        XCTAssertEqual(thumbnail.width, 640); XCTAssertEqual(thumbnail.height, 360)
        XCTAssertLessThan(copy.count, source.count)
        XCTAssertEqual(UIImage(data: source)?.cgImage?.width, 1920, "The original stays intact")
        XCTAssertNil(DiaryPhotoLibrary.smallCopy(of: Data("not an image".utf8)))
    }

    func testGateAppendMarginAndClosedSourceSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryService-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        let now = Date(), today = GregorianDay.containing(now, in: app.activePlace.timeZone)
        let service = AppDiaryService(app: app, clock: { now })
        XCTAssertThrowsError(try service.home(), "A room service must not read behind the lock")
        app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight")])
        try await app.executeDiaryCommand("diary.appendLine", payload: ["text": .string("كتبت اليوم"), "day": .string("today")])
        XCTAssertEqual(try service.home().todayPage.lines.filter { $0.kind == "normal" }.map(\.text), ["كتبت اليوم"])
        let context = ModelContext(container), previous = today.adding(days: -1)
        let page = DayPage(); page.dayKey = previous.description; context.insert(page)
        let prayer = PrayerLog(); prayer.dayKey = previous.description; prayer.prayer = "fajr"; prayer.status = "jamaah"; context.insert(prayer)
        try context.save()
        try await app.executeDiaryCommand("diary.freezeDay", payload: ["dayKey": .string(previous.description)])
        prayer.status = "alone"; try context.save()
        let frozen = try service.day(previous)
        XCTAssertTrue(frozen.lines.contains { $0.text == "صلّيت الفجر جماعة" })
        XCTAssertFalse(frozen.lines.contains { $0.text == "صلّيت الفجر وحدي" })
        let unrelated = MarginNote(); unrelated.targetDayKey = "2024-01-01"; unrelated.writtenDayKey = "2024-01-02"; unrelated.text = "هامش بعيد"; context.insert(unrelated)
        let deleted = MarginNote(); deleted.targetDayKey = previous.description; deleted.writtenDayKey = today.description; deleted.text = "هامش محذوف"; deleted.deletedAt = now; context.insert(deleted)
        try context.save()
        try await app.executeDiaryCommand("diary.addMargin", payload: ["text": .string("هامش واحد"), "targetDayKey": .string(previous.description)])
        let marginPage = try service.day(previous)
        XCTAssertTrue(marginPage.lines.contains { $0.kind == "margin" && $0.text == "هامش واحد" })
        XCTAssertFalse(marginPage.lines.contains { $0.text.contains("هامش بعيد") || $0.text.contains("هامش محذوف") })
        XCTAssertEqual(marginPage.marginDays.count, 1)
        XCTAssertTrue(try service.home().todayPage.lines.contains { $0.kind == "margin" && $0.text.contains("هامش واحد") })
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MarginNote>()), 3)
        app.redactProtectedData()
        XCTAssertThrowsError(try service.home())
    }

    func testProjectLinesGroupOnceAndKeepTheirDateOrder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryProjects-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let context = ModelContext(container), first = Project(), second = Project()
        first.name = "العمل"; first.createdAt = Date(timeIntervalSince1970: 1)
        second.name = "العائلة"; second.createdAt = Date(timeIntervalSince1970: 2)
        context.insert(first); context.insert(second)

        func entry(_ project: Project, day: String, text: String, secondOfDay: TimeInterval) {
            let row = Entry(); row.projectID = project.id; row.dayKey = day; row.text = text
            row.eventAt = Date(timeIntervalSince1970: secondOfDay); context.insert(row)
        }
        entry(first, day: "2026-10-02", text: "السطر الأحدث", secondOfDay: 2)
        entry(second, day: "2026-10-03", text: "سطر العائلة", secondOfDay: 3)
        entry(first, day: "2026-10-01", text: "السطر الأقدم", secondOfDay: 1)
        let unlinked = Entry(); unlinked.dayKey = "2026-10-04"; unlinked.text = "بلا مشروع"; context.insert(unlinked)
        try context.save()

        let cards = try AppDiaryService(app: app).projects()
        XCTAssertEqual(cards.map(\.name), ["العمل", "العائلة"])
        XCTAssertEqual(cards[0].lines.map(\.text), ["السطر الأقدم", "السطر الأحدث"])
        XCTAssertEqual(cards[1].lines.map(\.text), ["سطر العائلة"])
    }
    func testHomeOffMainMatchesTheCurrentDiarySnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryHomeOffMain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let now = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00+03:00")!
        let today = GregorianDay.containing(now, in: app.activePlace.timeZone), context = ModelContext(container)
        let yesterday = today.adding(days: -1)
        var yesterdayEntry: Entry?
        for (day, text, offset) in [(today, "سطر اليوم", 0.0), (today.adding(days: -1), "سطر أمس", -86_400.0)] {
            let entry = Entry(); entry.dayKey = day.description; entry.text = text; entry.ink = "normal"
            entry.eventAt = now.addingTimeInterval(offset); context.insert(entry)
            if day == yesterday { yesterdayEntry = entry }
        }
        let prayer = PrayerLog(); prayer.dayKey = today.description; prayer.prayer = "fajr"; prayer.status = "jamaah"; prayer.eventAt = now; context.insert(prayer)
        let media = Media(); media.kind = "photo"; media.contentType = "image/jpeg"; media.data = Data([0xFF, 0xD8, 0xFF]); media.sourceID = "photos:synthetic"
        context.insert(media); yesterdayEntry?.attachmentMediaIDs = [media.id]
        let page = DayPage(); page.dayKey = yesterday.description; page.photoMediaID = media.id; context.insert(page)
        let margin = MarginNote(); margin.targetDayKey = yesterday.description; margin.writtenDayKey = today.description
        margin.text = "ردّ اليوم"; margin.writtenAt = now; context.insert(margin)
        let frozen = DeviceSetting(); frozen.key = "sys.diaryAutoLines." + today.adding(days: -1).description
        frozen.valueJSON = try JSONEncoder().encode([DiaryAutoLine(id: "frozen.line", at: now.addingTimeInterval(-86_400), text: "سطر محفوظ", kind: "habits")])
        frozen.createdAt = now; frozen.updatedAt = now; context.insert(frozen)
        try context.save()
        let service = AppDiaryService(app: app, clock: { now })
        let synchronous = try service.home(), background = try await service.homeOffMain()
        XCTAssertEqual(background.today, synchronous.today)
        XCTAssertEqual(background.selection.days, synchronous.selection.days)
        XCTAssertEqual(background.days.map(\.id), synchronous.days.map(\.id))
        XCTAssertEqual(background.days.map { $0.lines.map(\.text) }, synchronous.days.map { $0.lines.map(\.text) })
        let yesterdayPage = try XCTUnwrap(background.days.first(where: { $0.id == yesterday.description }))
        XCTAssertTrue(yesterdayPage.lines.contains(where: { $0.text == "سطر محفوظ" }))
        XCTAssertEqual(yesterdayPage.photo, media.data)
        XCTAssertEqual(yesterdayPage.photoID, media.id)
        XCTAssertEqual(yesterdayPage.media.first?.assetID, "synthetic")
        XCTAssertTrue(background.todayPage.lines.contains(where: { $0.text.contains("ردّ اليوم") }))
        XCTAssertEqual(background.todayPage.lines.map(\.text), synchronous.todayPage.lines.map(\.text))
    }
    func testWelcomePersistsLocallyWithoutDiaryFacts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryWelcome-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let service = AppDiaryService(app: app)
        XCTAssertFalse(try service.hasWelcomed())
        try await app.executeDiaryCommand("diary.completeWelcome", payload: [:])
        try await app.executeDiaryCommand("diary.completeWelcome", payload: [:])
        XCTAssertTrue(try AppDiaryService(app: app).hasWelcomed())
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == "sys.diaryWelcomeSeen" }.count, 1)
    }

    func testRestoredDiarySkipsWelcomeWithoutWritingOrReadingBehindTheLock() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryRestoredWelcome-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root), service = AppDiaryService(app: app)
        XCTAssertThrowsError(try service.hasWelcomed())
        app.authorizeProtectedData()
        let context = ModelContext(container)
        let removed = Entry(); removed.deletedAt = .now; context.insert(removed)
        let merged = Entry(); merged.mergedInto = removed.id; context.insert(merged)
        try context.save()
        XCTAssertFalse(try service.hasWelcomed(), "Tombstones and merged rows are not a restored diary")
        let restored = Entry(); restored.dayKey = "2024-03-11"; restored.dayPolicy = "legacy@0"; restored.source = "dayOne"; restored.text = "نص مستورد"; context.insert(restored)
        try context.save()
        let settings = app.values
        XCTAssertTrue(try service.hasWelcomed())
        XCTAssertEqual(app.values, settings)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == "sys.diaryWelcomeSeen" }.count, 0)
        XCTAssertEqual(restored.dayKey, "2024-03-11")
        XCTAssertEqual(restored.dayPolicy, "legacy@0")
        app.redactProtectedData()
        XCTAssertThrowsError(try service.hasWelcomed())
    }

}
