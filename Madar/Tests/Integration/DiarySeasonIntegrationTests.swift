import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiarySeasonIntegrationTests:XCTestCase {
    func testAbsenceAndWeekAreReadOnlyWithActualStoredDates() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiarySeason-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root)
        app.authorizeProtectedData();let now=ISO8601DateFormatter().date(from:"2026-10-16T16:00:00+03:00")!,service=AppDiaryService(app:app,clock:{now}),day=try GregorianDay("2026-10-16"),context=ModelContext(container)
        for key in ["2026-10-09","2026-10-11"] {let row=Entry();row.dayKey=key;row.text="كتابة محفوظة";context.insert(row)};try context.save()
        XCTAssertEqual(try service.returnAfterAbsence(day)?.description,"2026-10-11")
        XCTAssertEqual(try service.weekDays(ending:day).map(\.day.description),["2026-10-11"])
        XCTAssertTrue(try service.appearance(day)?.weekAvailable==true);XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()),2)
        let current=Entry();current.dayKey=day.description;current.text="بدأت من اليوم";context.insert(current);try context.save();XCTAssertNil(try service.returnAfterAbsence(day))
    }
}
