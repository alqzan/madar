import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

@MainActor final class DateLabelsIntegrationTests: XCTestCase {
    func testSharedDatesChangeAppearanceWithoutChangingStoredDay() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DateLabels-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let entry = Entry(); entry.dayKey = "2026-10-09"; entry.text = "يوم محفوظ"; context.insert(entry); try context.save()
        let app = try AppSession(container: container, groupDirectory: root), day = try GregorianDay("2026-10-09")
        app.authorizeProtectedData()
        XCTAssertEqual(app.dateLabels(day).primary, "٢٨ ربيع الآخر ١٤٤٨ هـ")
        XCTAssertEqual(AppDiaryService(app: app).bothDates(day), "٢٨ ربيع الآخر ١٤٤٨ هـ، ٩ أكتوبر ٢٠٢٦ م")
        _ = try SettingsStore(context: context).stage(["core.firstCalendar": .string("gregorian"), "core.numerals": .string("western"), "core.hijriSource": .string("sighting"), "core.hijriOffset": .number(1)])
        try context.save(); try app.reload()
        XCTAssertEqual(app.dateLabels(day).primary, "9 أكتوبر 2026 م")
        XCTAssertEqual(app.dateLabels(day).secondary, "29 ربيع الآخر 1448 هـ")
        XCTAssertEqual(entry.dayKey, "2026-10-09")
        XCTAssertEqual(entry.text, "يوم محفوظ")
    }
}
