import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarCommands
@testable import Madar

/// Owner 22 Nov 2026: a wird starts as «اقرأ ثم قيّم»: the passage is read, one grade covers every page, and the commit records
/// the same shape «أتممته كاملًا» records. The ayah-by-ayah coach stays one tap away.
@MainActor final class QuranReadGradeIntegrationTests: XCTestCase {
    private func fixture() throws -> (AppSession, AppQuranService, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarQuranReadGrade-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight")]); try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        return (app, AppQuranService(session: app), root)
    }
    func testReadGradeAppliesOneGradeToEveryPageAndCommitsWholePassage() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .page, amount: 2, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        guard case .active(let state) = try await service.session(draftID: started.id, action: .changeMethod("readGrade")) else { return XCTFail("session must stay active") }
        XCTAssertEqual(state.method, "readGrade")
        XCTAssertEqual(state.stage, .grading)
        XCTAssertTrue(state.verses.allSatisfy { !$0.hidden }, "the whole passage is visible")
        guard case .active(let graded) = try await service.session(draftID: started.id, action: .grade(page: state.page?.page ?? 22, grade: .mastered)) else { return XCTFail() }
        let pending = try service.savedDraft(started.id)
        XCTAssertEqual(pending.readGradeRating, .mastered)
        XCTAssertTrue(pending.draft.grades.isEmpty)
        XCTAssertTrue(pending.draft.blindPassedAyahs.isEmpty)
        let context = ModelContext(app.container)
        for action in [QuranUISessionAction.commit, .commitPartial] {
            do {
                _ = try await service.session(draftID: started.id, action: action)
                XCTFail("The first of two pages cannot record the passage")
            } catch DataError.invalidValue { }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HifzSession>()), 0)
        XCTAssertEqual(graded.primaryTitle, "الوجه التالي", "the commit waits on the last page")
        let readingDay = pending.draft.storedDay.dayKey
        let tomorrow = AppQuranService(session: app, clock: { pending.draft.startedAt.addingTimeInterval(86_400) })
        let resumed = try await tomorrow.resume(draftID: started.id)
        XCTAssertTrue(resumed.coach?.pastDay == true)
        _ = try await tomorrow.session(draftID: started.id, action: .advance)
        let last = try await tomorrow.resume(draftID: started.id)
        XCTAssertEqual(last.primaryTitle, "أنهِ وسجّل")
        _ = try await tomorrow.session(draftID: started.id, action: .commit)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<HifzSession>()).first)
        XCTAssertEqual(session.pages, [22, 23]); XCTAssertEqual(session.fromAyah, 149)
        XCTAssertEqual(session.dayKey, readingDay)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PageGrade>()).map(\.page)), [22, 23])
        XCTAssertTrue(try context.fetch(FetchDescriptor<PageGrade>()).allSatisfy { $0.grade == "mastered" })
        XCTAssertEqual(session.mistakes, 0)
    }
    func testSwitchingBackToTheCoachRestartsItLikeToday() async throws {
        // The service holds its session unowned: keep the session alive for the whole test.
        let (app, service, root) = try fixture(); defer { withExtendedLifetime(app) { try? FileManager.default.removeItem(at: root) } }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .page, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let started = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        XCTAssertEqual(started.method, "coach", "a bare start is still the coach")
        _ = try await service.session(draftID: started.id, action: .changeMethod("readGrade"))
        guard case .active(let back) = try await service.session(draftID: started.id, action: .changeMethod("coach")) else { return XCTFail() }
        XCTAssertEqual(back.method, "coach"); XCTAssertEqual(back.stage, .repetition)
        let draft = try service.savedDraft(started.id)
        XCTAssertTrue(draft.draft.grades.isEmpty); XCTAssertTrue(draft.draft.blindPassedAyahs.isEmpty)
        XCTAssertEqual(draft.draft.ayahID, 149); XCTAssertEqual(draft.coach?.repetitions, 0)
    }
}
