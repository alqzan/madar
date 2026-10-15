import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar

@MainActor final class DiaryServiceIntegrationTests: XCTestCase {
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
        try await app.executeDiaryCommand("diary.addMargin", payload: ["text": .string("هامش واحد"), "targetDayKey": .string(previous.description)])
        XCTAssertTrue(try service.day(previous).lines.contains { $0.kind == "margin" && $0.text == "هامش واحد" })
        XCTAssertTrue(try service.home().todayPage.lines.contains { $0.kind == "margin" && $0.text.contains("هامش واحد") })
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MarginNote>()), 1)
        app.redactProtectedData()
        XCTAssertThrowsError(try service.home())
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

}
