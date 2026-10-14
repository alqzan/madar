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
    func testCoachLearningHintDoesNotWriteMistakeResumeAndCommitUsePersistedDraft() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .ayah, amount: 7, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        _ = try await service.session(draftID: started.id, action: .reveal(ayahID: 1, wordIndex: nil))
        let context = ModelContext(app.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MistakeEvent>()).count, 0)
        let reopened = AppQuranService(session: app)
        let resumed = try await reopened.resume(draftID: started.id)
        XCTAssertEqual(resumed.stage, .repetition)
        for _ in 0..<3 { _ = try await reopened.session(draftID: started.id, action: .advance) }
        _ = try await reopened.session(draftID: started.id, action: .mistake(ayahID: 3, wordIndex: nil))
        _ = try await reopened.session(draftID: started.id, action: .advance)
        _ = try await reopened.session(draftID: started.id, action: .commit)
        let result = try await reopened.load()
        XCTAssertEqual(result.coverageFraction, 1.0 / 604); XCTAssertNil(result.draft)
        let sessions = try ModelContext(app.container).fetch(FetchDescriptor<HifzSession>())
        XCTAssertEqual(sessions.filter { $0.deletedAt == nil }.count, 1)
        XCTAssertEqual(sessions.first?.mistakes, 1)
    }
}
