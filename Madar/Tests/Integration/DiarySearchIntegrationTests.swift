import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiarySearchIntegrationTests:XCTestCase {
    func testLocalIndexGateSealedExclusionAndSources() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiarySearch-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root),service=AppDiaryService(app:app)
        XCTAssertThrowsError(try service.searchIndex());app.authorizeProtectedData()
        let context=ModelContext(container),project=Project(),entry=Entry(),sealed=Letter(),opened=Letter(),margin=MarginNote()
        project.name="البيت";context.insert(project);entry.ink="ghad";entry.text="بالصبر";entry.place="جدة";entry.projectID=project.id;entry.tags=["سفر","عائلة","سفر حول العالم"];entry.dayKey="2025-10-15";context.insert(entry)
        sealed.text="كلمةمغلقة";context.insert(sealed);opened.text="كلمةمفتوحة";opened.state="opened";context.insert(opened)
        margin.text="هامش محفوظ";margin.targetDayKey="2025-10-15";margin.writtenDayKey="2026-10-15";context.insert(margin);try context.save()
        let index=try service.searchIndex()
        XCTAssertFalse(index.documents.contains{$0.text=="كلمةمغلقة"});XCTAssertTrue(index.documents.contains{$0.kind=="letter" && $0.text=="كلمةمفتوحة"})
        XCTAssertEqual(index.documents.filter{index.parser.matches($0,chips:index.parser.parse("⌗البيت الصَّبر في جدة"))}.map(\.id),[entry.id.uuidString])
        XCTAssertEqual(index.documents.filter{index.parser.matches($0,chips:index.parser.parse("#سفر"))}.map(\.id),[entry.id.uuidString])
        XCTAssertEqual(index.documents.filter{index.parser.matches($0,chips:index.parser.parse("#سفر حول العالم"))}.map(\.id),[entry.id.uuidString])
        XCTAssertTrue(index.terms.contains { $0.0 == "#عائلة" && $0.1 == "#عائلة" && $0.2 == 1 })
        XCTAssertEqual(index.documents.filter{index.parser.matches($0,chips:index.parser.parse("لِغد"))}.map(\.id),[entry.id.uuidString])
        XCTAssertEqual(index.documents.first{$0.kind=="margin"}?.day.description,"2026-10-15")
    }
}
