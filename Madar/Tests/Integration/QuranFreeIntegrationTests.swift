import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar
@MainActor final class QuranFreeIntegrationTests:XCTestCase {
    func testFreeSessionCommitsRecordedSlipWithoutPageGrade() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranFreeSlip-\(UUID())")
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight")])
        let saved=HifzSession();saved.fromAyah=1;saved.toAyah=7;saved.pages=[1];saved.dayKey="2026-10-14";saved.endedAt=Date().addingTimeInterval(-86400)
        context.insert(saved);try context.save()
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app)
        let started=try await service.start(kind:.free,stepID:nil,range:.init(fromPage:1,toPage:1),rakaat:nil,spotID:nil)
        _ = try await service.session(draftID:started.id,action:.mistake(ayahID:2,wordIndex:1))
        _ = try await service.session(draftID:started.id,action:.commitPartial)

        let verificationContext=ModelContext(container)
        let free=try XCTUnwrap(try verificationContext.fetch(FetchDescriptor<HifzSession>()).first { $0.kind == "free" })
        XCTAssertEqual(free.fromAyah,2);XCTAssertEqual(free.toAyah,2);XCTAssertTrue(free.pages.isEmpty);XCTAssertEqual(free.mistakes,1)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<PageGrade>()).filter { $0.sessionID == free.id }.isEmpty)
        let events=try verificationContext.fetch(FetchDescriptor<MistakeEvent>()).filter { $0.sessionID == free.id }
        XCTAssertEqual(events.count,1);XCTAssertEqual(events.first?.ayahId,2);XCTAssertEqual(events.first?.wordIndex,1)
    }

    /// B1-2: a tap inside a session builds the Quran snapshot once, however many checks the action makes.
    func testOneSessionActionBuildsOneSnapshot() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranOneSnapshot-\(UUID())")
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight")])
        let saved=HifzSession();saved.fromAyah=1;saved.toAyah=7;saved.pages=[1];saved.dayKey="2026-10-14";saved.endedAt=Date().addingTimeInterval(-86400)
        context.insert(saved);try context.save()
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app)
        let started=try await service.start(kind:.free,stepID:nil,range:.init(fromPage:1,toPage:1),rakaat:nil,spotID:nil)
        let before=service.snapshotReads
        _ = try await service.session(draftID:started.id,action:.mistake(ayahID:2,wordIndex:1))
        XCTAssertEqual(service.snapshotReads-before,1)
        let beforeGrade=service.snapshotReads
        _ = try await service.session(draftID:started.id,action:.advance)
        XCTAssertEqual(service.snapshotReads-beforeGrade,1)
    }

    func testMixedRangeGradesOnlySavedFacesAndFinishesAfterLastPage() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranFree-\(UUID())")
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight")])
        let row=HifzSession();row.fromAyah=1;row.toAyah=7;row.pages=[1];row.dayKey="2026-10-14";row.endedAt=Date().addingTimeInterval(-86400);context.insert(row);try context.save()
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app)
        let started=try await service.start(kind:.free,stepID:nil,range:.init(fromPage:1,toPage:2),rakaat:nil,spotID:nil)
        _ = try await service.session(draftID:started.id,action:.advance)
        var state=try await service.resume(draftID:started.id);XCTAssertEqual(state.stage,.grading);XCTAssertEqual(state.primaryTitle,"تابع")
        _ = try await service.session(draftID:started.id,action:.grade(page:1,grade:.good))
        _ = try await service.session(draftID:started.id,action:.advance)
        state=try await service.resume(draftID:started.id);XCTAssertEqual(state.page?.page,2);XCTAssertTrue(state.grades.isEmpty)
        do { _ = try await service.session(draftID:started.id,action:.grade(page:2,grade:.mastered));XCTFail("unmemorized grade accepted") } catch { }
        _ = try await service.session(draftID:started.id,action:.advance)
        _ = try await service.session(draftID:started.id,action:.commit)
        let snapshot=try service.snapshot();XCTAssertEqual(snapshot.coverage.completedPages,[1]);XCTAssertEqual(snapshot.sessions.filter { $0.kind == .free }.flatMap(\.pages),[1])
        let reading=try await service.start(kind:.free,stepID:nil,range:.init(fromPage:2,toPage:2),rakaat:nil,spotID:nil)
        _ = try await service.session(draftID:reading.id,action:.advance)
        state=try await service.resume(draftID:reading.id);XCTAssertEqual(state.primaryTitle,"أغلق القراءة")
        _ = try await service.session(draftID:reading.id,action:.discard)
        XCTAssertEqual(try service.snapshot().sessions.count,2)
    }
}
