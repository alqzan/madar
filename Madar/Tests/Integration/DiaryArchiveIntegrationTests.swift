import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar

@MainActor final class DiaryArchiveIntegrationTests: XCTestCase {
    func testCalendarDatesLeapMonthAndSightingOffset() throws {
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        let gregorian = DiaryCalendarGrid(first: .gregorian, zone: zone, offset: 2, weekStart: 7)
        let days = gregorian.days(year: 2024, month: 2)
        XCTAssertEqual(days.count, 29); XCTAssertEqual(days.last?.description, "2024-02-29"); XCTAssertEqual(gregorian.leading(days), 5)
        let hijri = DiaryCalendarGrid(first: .hijri, zone: zone, offset: 0, weekStart: 7)
        let shifted = DiaryCalendarGrid(first: .hijri, zone: zone, offset: 2, weekStart: 1)
        XCTAssertEqual(hijri.days(year: 1445, month: 9).first?.description, "2024-03-11")
        XCTAssertEqual(shifted.days(year: 1445, month: 9).first?.description, "2024-03-09")
        XCTAssertEqual(shifted.parts(try GregorianDay("2024-03-09")).day, 1)
    }
    func testArchiveGateWrittenMarginAndSealedLetterExclusion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryArchive-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        let service = AppDiaryService(app: app); XCTAssertThrowsError(try service.archive()); app.authorizeProtectedData()
        let context = ModelContext(container), entry = Entry(), note = MarginNote(), letter = Letter()
        entry.dayKey = "2024-02-29"; entry.text = "يوم محفوظ"; context.insert(entry)
        note.targetDayKey = entry.dayKey; note.writtenDayKey = "2026-10-15"; note.text = "هامش اليوم"; context.insert(note)
        letter.text = "سر مغلق"; letter.state = "sealed"; context.insert(letter); try context.save()
        let archive = try service.archive()
        XCTAssertEqual(archive.days.map(\.day.description), ["2026-10-15","2024-02-29"])
        XCTAssertEqual(archive.days.map(\.excerpt), ["هامش اليوم","يوم محفوظ"])
        XCTAssertEqual(archive.days.map(\.writings), [1,1]); XCTAssertFalse(archive.days.contains { $0.excerpt.contains("سر") })
    }
}
