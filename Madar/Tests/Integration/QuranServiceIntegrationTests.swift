import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarCommands
@testable import Madar

@MainActor final class QuranServiceIntegrationTests: XCTestCase {
    private func fixture() throws -> (AppSession, AppQuranService, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarQuranService-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight")]); try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        return (app, AppQuranService(session: app), root)
    }
    func testEmptyThenRealPlanLevelsAndResourcesUseDomainValues() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let empty = try await service.load()
        XCTAssertNil(empty.plan); XCTAssertEqual(empty.coverageFraction, 0); XCTAssertTrue(empty.availableTools.isEmpty)
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .half, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let planned = try await service.load()
        XCTAssertEqual(planned.plan?.nextAyah, 149); XCTAssertEqual(planned.steps.first(where: { $0.id == "hifz" })?.range?.fromPage, 22)
        try await service.perform(.setTodayLevel(kind: .hifz, level: .deep))
        let updated = try await service.load()
        XCTAssertEqual(updated.hifzLevel, .deep)
        let page = try await service.page(22)
        XCTAssertEqual(page.lines.count, 15); XCTAssertFalse(page.postScriptName.isEmpty); XCTAssertFalse(page.lines[0].glyphs.isEmpty)
        XCTAssertNotNil(app.undoToken)
    }
    func testPartialHifzCommitContainsOnlyThePageBlindRecited() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .page, amount: 2, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        try await learnPage(service, id: started.id)
        _ = try await service.session(draftID: started.id, action: .advance)
        _ = try await service.session(draftID: started.id, action: .commitPartial)
        let session = try XCTUnwrap(ModelContext(app.container).fetch(FetchDescriptor<HifzSession>()).first)
        XCTAssertEqual(session.fromAyah, 149); XCTAssertEqual(session.toAyah, 152)
        XCTAssertEqual(session.pages, [22])
    }

    func testCoachLearningHintDoesNotWriteMistakeResumeAndCommitUsePersistedDraft() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .ayah, amount: 7, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        _ = try await service.session(draftID: started.id, action: .reveal(ayahID: 1, wordIndex: nil))
        let context = ModelContext(app.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MistakeEvent>()).count, 0)
        XCTAssertEqual(try service.savedDraft(started.id).coach?.learningHints, 1)
        let reopened = AppQuranService(session: app)
        let resumed = try await reopened.resume(draftID: started.id)
        XCTAssertEqual(resumed.stage, .repetition)
        _ = try await reopened.session(draftID: started.id, action: .advance)
        XCTAssertEqual(try reopened.savedDraft(started.id).coach?.repetitions, 1)
        try await learnPage(reopened, id: started.id)
        _ = try await reopened.session(draftID: started.id, action: .reveal(ayahID: 3, wordIndex: nil))
        _ = try await reopened.session(draftID: started.id, action: .reveal(ayahID: 3, wordIndex: nil))
        _ = try await reopened.session(draftID: started.id, action: .advance)
        _ = try await reopened.session(draftID: started.id, action: .commit)
        let result = try await reopened.load()
        XCTAssertEqual(result.coverageFraction, 1.0 / 604); XCTAssertNil(result.draft)
        XCTAssertEqual(result.history.weekSummary, ["أول يوم"])
        XCTAssertEqual(result.recentDays.count, 1)
        let nextDay = AppQuranService(session: app, clock: { service.clock().addingTimeInterval(86_400) })
        let tomorrow = try await nextDay.load()
        XCTAssertTrue(tomorrow.history.weekSummary.first?.contains("١ من ٢ أيام الحفظ") == true)
        let sessions = try ModelContext(app.container).fetch(FetchDescriptor<HifzSession>())
        XCTAssertEqual(sessions.filter { $0.deletedAt == nil }.count, 1)
        XCTAssertEqual(sessions.first?.mistakes, 1)
    }
    func testMethodsAndEmptyPartialExitPreserveFacts() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .ayah, amount: 1, rhythm: .light, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        _ = try await service.session(draftID: started.id, action: .changeMethod("link"))
        let linked = try await service.resume(draftID: started.id)
        XCTAssertNotNil(linked.coach?.referenceText)
        _ = try await service.session(draftID: started.id, action: .commitPartial)
        XCTAssertEqual(try ModelContext(app.container).fetchCount(FetchDescriptor<HifzSession>()), 0)
        let after = try await service.load(); XCTAssertNil(after.draft)
    }
    func testCoachKeepsItsOriginalIntensityWhenPlanChanges() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .ayah, amount: 7, rhythm: .light, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .ayah, amount: 7, rhythm: .intense, restDay: "none", missPolicy: "ask")))
        let resumed = try await AppQuranService(session: app).resume(draftID: started.id)
        XCTAssertEqual(resumed.coach?.target, 3)
        for _ in 0..<3 { _ = try await service.session(draftID: started.id, action: .advance) }
        let after = try await service.resume(draftID: started.id)
        XCTAssertEqual(after.stage, .lineStarts)
    }
    func testPastDayCoachOnlyAllowsSavingCompletedWorkOrDiscarding() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .ayah, amount: 7, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        let tomorrow = AppQuranService(session: app, clock: { service.clock().addingTimeInterval(86_400) })
        let resumed = try await tomorrow.resume(draftID: started.id)
        XCTAssertEqual(resumed.coach?.pastDay, true)
        do {
            _ = try await tomorrow.session(draftID: started.id, action: .advance)
            XCTFail("An old-day draft must not continue on another day")
        } catch { XCTAssertEqual(error as? DataError, .invalidValue("احفظ ما تمّ من الجلسة السابقة أو تجاهلها")) }
        _ = try await tomorrow.session(draftID: started.id, action: .commitPartial)
        XCTAssertEqual(try ModelContext(app.container).fetchCount(FetchDescriptor<HifzSession>()), 0)
        let after = try await tomorrow.load(); XCTAssertNil(after.draft)
    }
    private func learnPage(_ service: AppQuranService, id: UUID) async throws {
        var state = try await service.resume(draftID: id)
        for _ in 0..<100 {
            if state.stage == .covered { return }
            guard case .active(let next) = try await service.session(draftID: id, action: .advance) else { XCTFail("Learning must not commit"); return }
            state = next
        }
        XCTFail("The page never reached blind recitation")
    }
}
