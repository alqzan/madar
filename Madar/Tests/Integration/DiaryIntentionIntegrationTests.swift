import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiaryIntentionIntegrationTests:XCTestCase {
    func testIntentionVisibleInDayArchiveSearchAndExportWithoutDuplicatingText() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"IntentionService-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root),service=AppDiaryService(app:app)
        app.authorizeProtectedData();let day=try service.currentDay();app.redactProtectedData();XCTAssertThrowsError(try service.intentions(day));app.authorizeProtectedData()
        try await service.saveIntention("أُنهي العمل",day:day);let rows=try service.intentions(day);XCTAssertEqual(rows.count,1);XCTAssertNil(rows[0].result)
        XCTAssertTrue(try service.day(day).lines.contains{$0.kind=="intention" && $0.text=="أُنهي العمل"})
        XCTAssertEqual(try service.archive().days.first{$0.day==day}?.writings,1)
        XCTAssertEqual(try service.searchIndex().documents.filter{$0.kind=="intention"}.count,1)
        XCTAssertEqual(try service.exportPages(.init()).flatMap(\.lines).filter{$0.text=="أُنهي العمل"}.count,1)
        try await service.setIntentionResult(rows[0].id,result:"done");XCTAssertEqual(try service.intentions(day).first?.result,"done")
        try await service.setIntentionResult(rows[0].id,result:nil);XCTAssertNil(try service.intentions(day).first?.result)
        let morning=ISO8601DateFormatter().date(from:day.description+"T07:00:00+03:00")!,evening=ISO8601DateFormatter().date(from:day.description+"T22:00:00+03:00")!
        XCTAssertFalse(AppDiaryService(app:app,clock:{morning}).intentionEvening(day));XCTAssertTrue(AppDiaryService(app:app,clock:{evening}).intentionEvening(day))
    }
}
