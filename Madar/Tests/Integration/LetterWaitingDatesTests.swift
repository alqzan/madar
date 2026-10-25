import XCTest
import MadarCore
import MadarData
import SwiftData
@testable import Madar

/// Both calendars always (owner, 15 Oct): a letter that opens on a Hijri day names its Gregorian day too.
@MainActor final class LetterWaitingDatesTests: XCTestCase {
    func testSealingHijriLetterUsesTheSameSightingCorrectionAsItsPickerAndWaitingDay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LetterSighting-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppDiaryService(app: app)
        let target = try GregorianDay("2030-01-10"), date = target.date(in: app.activePlace.timeZone).addingTimeInterval(12 * 3600)
        for (offset, key) in [(-1, "1451-09-05"), (1, "1451-09-07")] {
            try await app.applySettingsAndWait(["core.hijriSource": .string("sighting"), "core.hijriOffset": .number(Double(offset))])
            let display = service.letterPickerDate(date, by: service.letterPickerOffset)
            let calendar = service.letterPickerCalendar(hijri: true)
            XCTAssertEqual(calendar.component(.day, from: display), offset == -1 ? 5 : 7)
            XCTAssertEqual(service.letterPickerDate(display, by: -service.letterPickerOffset), date)
            try await service.sealLetter("رسالة التصحيح \(offset)", choice: .init(id: "hijri", title: "في تاريخ هجري", trigger: .hijriDate, target: nil), date: date)
            let row = try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<Letter>()).first { $0.text == "رسالة التصحيح \(offset)" })
            XCTAssertEqual(row.triggerValue, key)
            XCTAssertEqual(row.state, "sealed")
            XCTAssertEqual(service.hijriDay(key), target)
            XCTAssertTrue(service.waitingFor(.hijriDate, value: key, target: nil).contains("١٠ يناير ٢٠٣٠"))
        }
    }

    func testRetryingTheSameProjectIdentityDoesNotCreateAnotherProject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectSave-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let service = AppDiaryService(app: app), id = UUID()
        for _ in 0..<2 { try await service.saveProject(id, name: "مشروع واحد", intention: "على مهل", keyword: "مشروعي") }
        XCTAssertEqual(try service.projects().filter { $0.id == id }.count, 1)
        XCTAssertEqual(try ModelContext(app.container).fetchCount(FetchDescriptor<Project>()), 1)
    }

    func testHijriTriggerShowsBothCalendars() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LetterDates-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let service = AppDiaryService(app: app)
        // 1 Ramadan 1448 (Umm al-Qura): both calendar month names stay visible.
        let text = service.waitingFor(.hijriDate, value: "1448-09-01", target: nil)
        XCTAssertTrue(text.hasPrefix("تُفتح في "), text)
        XCTAssertTrue(text.contains("رمضان"), text)
        XCTAssertTrue(text.contains("فبراير"), text)
        XCTAssertEqual(service.waitingFor(.hijriDate, value: nil, target: nil), "تُفتح في يومها")
    }
}
