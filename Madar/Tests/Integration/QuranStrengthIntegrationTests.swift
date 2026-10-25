import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar
@MainActor final class QuranStrengthIntegrationTests:XCTestCase {
    func testFarProjectionRaiseDedupeRecoveryCancelAndUndo() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranStrength-\(UUID())"),container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight")])
        let catalog=try QuranResources.catalog()
        let row=HifzSession();row.fromAyah=1;row.toAyah=catalog.ayahs(on:2).last!.id;row.pages=[1,2];row.dayKey="2026-08-01";row.endedAt=ISO8601DateFormatter().date(from:"2026-08-01T12:00:00+03:00")!;context.insert(row);try context.save()
        // Reads and writes use the app clock; a separately frozen projection day cannot observe today's commands.
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app)
        var board=try service.strengthBoard();XCTAssertEqual(board.far,2);XCTAssertEqual(board.parts.count,1);XCTAssertEqual(board.parts[0].projected,85);XCTAssertEqual(board.options.map(\.daily),[1,1,1]);XCTAssertNil(board.active)
        XCTAssertEqual(try service.snapshot().sessions.count,1)
        try await service.perform(.raisePages(juz:1));try await service.perform(.raisePages(juz:1))
        XCTAssertEqual(try service.snapshot().allotments.filter {$0.origin == .raise}.count,1)
        XCTAssertTrue(try service.strengthBoard().parts[0].scheduled)
        try await service.perform(.createRecovery(days:7));board=try service.strengthBoard();XCTAssertEqual(board.remaining,2);XCTAssertEqual(board.activeShare,1)
        try await service.perform(.cancelRecovery);XCTAssertNil(try service.strengthBoard().active)
        let token=try XCTUnwrap(app.undoToken)
        _ = try await app.executeQuranCommand("system.undo",payload:["undoToken":.string(token.id.uuidString)])
        XCTAssertNotNil(try service.strengthBoard().active);XCTAssertEqual(try service.snapshot().sessions.count,1)
    }
}
