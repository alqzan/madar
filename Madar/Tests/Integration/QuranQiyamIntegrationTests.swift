import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar
@MainActor final class QuranQiyamIntegrationTests:XCTestCase {
    private func fixture() throws -> (AppSession,AppQuranService) {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranQiyam-\(UUID())"),container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight")])
        let row=HifzSession();row.fromAyah=1;row.toAyah=7;row.pages=[1];row.dayKey="2026-10-14";row.endedAt=Date().addingTimeInterval(-86400);context.insert(row);try context.save()
        let app=try AppSession(container:container,groupDirectory:root);return(app,AppQuranService(session:app))
    }
    func testEightRakahOneSavedFaceResumesAndRecordsOnceAtomically() async throws {
        let (app,service)=try fixture()
        let preview=try service.qiyamBoard(rakaat:8);XCTAssertEqual(preview.assignments.compactMap(\.page),[1]);XCTAssertEqual(preview.assignments.filter {$0.page == nil}.count,7)
        var state=try await service.start(kind:.qiyam,stepID:nil,range:nil,rakaat:8,spotID:nil)
        _ = try await service.session(draftID:state.id,action:.advance)
        let resumed=try await AppQuranService(session:app).resume(draftID:state.id);XCTAssertEqual(resumed.qiyam?.completed,1);XCTAssertNil(resumed.qiyam?.assignments[1].page)
        do {_ = try await service.session(draftID:state.id,action:.commit);XCTFail("planned eight must not record after one") } catch {}
        for _ in 1..<8 {_ = try await service.session(draftID:state.id,action:.advance)}
        state=try await service.resume(draftID:state.id);XCTAssertTrue(state.qiyam?.finished == true);XCTAssertEqual(state.grades.count,1)
        _ = try await service.session(draftID:state.id,action:.grade(page:1,grade:.mastered))
        _ = try await service.session(draftID:state.id,action:.commit)
        let context=ModelContext(app.container),night=try XCTUnwrap(context.fetch(FetchDescriptor<QiyamNight>()).first)
        XCTAssertEqual(night.rakaat,8);XCTAssertNotNil(night.quranSessionID)
        XCTAssertEqual(try service.snapshot().sessions.filter {$0.kind == .qiyam}.flatMap(\.pages),[1])
        XCTAssertNotNil(try service.qiyamBoard(rakaat:2).unavailable)
        let token=try XCTUnwrap(app.undoToken);_ = try await app.executeQuranCommand("system.undo",payload:["undoToken":.string(token.id.uuidString)])
        XCTAssertTrue(try service.snapshot().sessions.allSatisfy {$0.kind != .qiyam})
        XCTAssertFalse(try ModelContext(app.container).fetch(FetchDescriptor<QiyamNight>()).contains {$0.deletedAt == nil && $0.quranSessionID != nil})
    }
    func testExistingPrayerNightSurvivesWirdAndUndo() async throws {
        let (app,service)=try fixture(),preview=try await service.qiyamPreview(rakaat:2)
        let context=ModelContext(app.container),prior=QiyamNight();prior.nightKey=preview.nightKey;prior.rakaat=6;prior.witr=true;context.insert(prior);try context.save()
        let state=try await service.start(kind:.qiyam,stepID:nil,range:nil,rakaat:2,spotID:nil)
        for _ in 0..<2 {_ = try await service.session(draftID:state.id,action:.advance)}
        _ = try await service.session(draftID:state.id,action:.commit)
        let changed=try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<QiyamNight>()).first)
        XCTAssertEqual(changed.rakaat,6);XCTAssertTrue(changed.witr);XCTAssertNotNil(changed.quranSessionID)
        let token=try XCTUnwrap(app.undoToken);_ = try await app.executeQuranCommand("system.undo",payload:["undoToken":.string(token.id.uuidString)])
        let restored=try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<QiyamNight>()).first)
        XCTAssertNil(restored.deletedAt);XCTAssertNil(restored.quranSessionID);XCTAssertEqual(restored.rakaat,6);XCTAssertTrue(restored.witr)
    }
    func testPartialConfirmationRecordsActualRakahAndKeepsCoverage() async throws {
        let (app,service)=try fixture(),started=try await service.start(kind:.qiyam,stepID:nil,range:nil,rakaat:8,spotID:nil)
        _ = try await service.session(draftID:started.id,action:.advance)
        _ = try await service.session(draftID:started.id,action:.commitPartial)
        let night=try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<QiyamNight>()).first)
        XCTAssertEqual(night.rakaat,1);XCTAssertEqual(try service.snapshot().coverage.completedPages,[1])
        app.open(URL(string:"madar://quran/session/qiyam")!);XCTAssertEqual(app.selectedTab,"quran");XCTAssertEqual(app.quranRoute?.path,["session","qiyam"])
    }
}
