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
    /// §7.4 «لو فاتك يوم»: a plan policy of «وزّعه» is applied without asking (+⅓ face over three days, RQ6); «اسألني» shows the card.
    func testMissedDayPolicyIsAppliedOnceWithoutAsking() async throws {
        for policy in ["spread", "ask"] {
            let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .page, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: policy)))
            let context = ModelContext(app.container)
            let plan = try XCTUnwrap(context.fetch(FetchDescriptor<HifzPlan>()).first)
            plan.activeFrom = plan.activeFrom.addingTimeInterval(-3 * 86400); try context.save()
            let state = try await service.load()
            let missed = try ModelContext(app.container).fetch(FetchDescriptor<QuranAllotment>()).filter { $0.origin == "missPolicy" && $0.deletedAt == nil }
            if policy == "spread" {
                XCTAssertNil(state.missedDayKey)
                XCTAssertEqual(missed.count, 3)
                for row in missed { XCTAssertEqual(row.amount, 1.0 / 3, accuracy: 0.0001) }
                _ = try await service.load()
                XCTAssertEqual(try ModelContext(app.container).fetch(FetchDescriptor<QuranAllotment>()).filter { $0.origin == "missPolicy" }.count, 3, "applied once")
            } else {
                XCTAssertNotNil(state.missedDayKey); XCTAssertTrue(missed.isEmpty)
            }
        }
    }
    /// §7.4: a word slip keeps its wordIndex, counts once, and becomes a word spot for «مواضع الخطأ».
    func testWordSlipInReviewIsStoredOnceAndBecomesAWordDrillSpot() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .page, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let hifz = try await service.start(kind: .hifz, stepID: "hifz", range: nil, rakaat: nil, spotID: nil)
        try await learnPage(service, id: hifz.id)
        _ = try await service.session(draftID: hifz.id, action: .mistake(ayahID: 2, wordIndex: 1))
        _ = try await service.session(draftID: hifz.id, action: .mistake(ayahID: 2, wordIndex: 1))
        let state = try await service.resume(draftID: hifz.id)
        XCTAssertTrue(state.coach?.flaggedWords.contains(QuranUICoach.wordKey(2, 1)) == true)
        _ = try await service.session(draftID: hifz.id, action: .advance)
        _ = try await service.session(draftID: hifz.id, action: .commitPartial)
        let events = try ModelContext(app.container).fetch(FetchDescriptor<MistakeEvent>()).filter { $0.deletedAt == nil }
        XCTAssertEqual(events.map(\.wordIndex), [1], "one slip on the exact word")
        let board = try service.drillBoard()
        XCTAssertEqual(board.today, ["2:1"])
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
    func testReviewRevealsDoNotPenalizeAndPartialExitOnlyCommitsTheRatedPage() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await seedTwoPages(service)
        let review = AppQuranService(session: app, clock: service.clock)
        var state = try await review.start(kind: .review, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        // With only two memorized pages, the old-test fallback selects page 1 last.
        XCTAssertEqual(state.coach?.pages, [2, 1])
        XCTAssertEqual(state.coach?.review, true)
        _ = try await review.session(draftID: state.id, action: .mistake(ayahID: 8, wordIndex: nil))
        for _ in 0..<5 {
            guard case .active(let next) = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Reveal must keep the draft") }
            state = next
        }
        XCTAssertEqual(try review.savedDraft(state.id).draft.mistakes.count, 1)
        XCTAssertEqual(state.primaryTitle, "قيّم هذا الوجه")
        guard case .active(let graded) = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Rate before moving") }
        XCTAssertEqual(graded.stage, .grading); XCTAssertEqual(graded.page?.page, 2)
        XCTAssertEqual(graded.grades.first?.grade, .good)
        _ = try await review.session(draftID: state.id, action: .grade(page: 2, grade: .needs))
        guard case .active(let second) = try await review.session(draftID: state.id, action: .advance) else { return XCTFail("Next page must stay active") }
        XCTAssertEqual(second.page?.page, 1); XCTAssertEqual(second.stage, .review)
        XCTAssertEqual(second.coach?.revealedAyahs, [])
        let resumed = try await AppQuranService(session: app, clock: review.clock).resume(draftID: state.id)
        XCTAssertEqual(resumed.page?.page, 1)
        _ = try await review.session(draftID: state.id, action: .commitPartial)
        let rows = try ModelContext(app.container).fetch(FetchDescriptor<HifzSession>()).filter { $0.kind == "review" }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.pages, [2])
        XCTAssertEqual(rows.first?.mistakes, 1)
        let coverage = try await review.load(); XCTAssertEqual(coverage.coverageFraction, 2.0 / 604)
    }
    private func seedTwoPages(_ service: AppQuranService) async throws {
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 1, unit: .page, amount: 2, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let start = try await service.start(kind: .hifz, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        _ = try await service.session(draftID: start.id, action: .changeMethod("completeAyah"))
        for page in 1...2 {
            try await learnPage(service, id: start.id)
            _ = try await service.session(draftID: start.id, action: .advance)
            if page == 1 { _ = try await service.session(draftID: start.id, action: .advance) }
        }
        _ = try await service.session(draftID: start.id, action: .commit)
    }
    func testReviewFullCommitWaitsForTheFinalPageRating() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await seedTwoPages(service)
        let review = AppQuranService(session: app, clock: service.clock)
        var state = try await review.start(kind: .review, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        let sections = try review.savedDraft(state.id).reviewSections
        for page in [2, 1] {
            for _ in 0..<(page == 1 ? 7 : 5) {
                guard case .active(let next) = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Reveal must stay active") }; state = next
            }
            guard case .active(let graded) = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Grade must stay active") }; state = graded
            XCTAssertEqual(state.stage, .grading)
            if page == 2 {
                XCTAssertEqual(state.primaryTitle, "تابع")
                guard case .active(let next) = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Page one cannot complete the session") }; state = next
            }
        }
        XCTAssertEqual(state.primaryTitle, "أنهِ وسجّل")
        XCTAssertEqual(try review.savedDraft(state.id).reviewSections, sections)
        guard case .completed = try await review.session(draftID: state.id, action: state.primaryAction) else { return XCTFail("Final rating should commit") }
        let rows = try ModelContext(app.container).fetch(FetchDescriptor<HifzSession>()).filter { $0.kind == "review" }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.pages, [1, 2]); XCTAssertEqual(rows.first?.mistakes, 0)
    }
    func testReviewedPartialFaceDoesNotReappearInTodaysQueueOrCompleteCoverage() async throws {
        let (app, service, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await service.perform(.savePlan(QuranUIPlanInput(startAyah: 149, unit: .ayah, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: "ask")))
        let start = try await service.start(kind: .hifz, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        _ = try await service.session(draftID: start.id, action: .changeMethod("completeAyah"))
        try await learnPage(service, id: start.id)
        _ = try await service.session(draftID: start.id, action: .advance)
        _ = try await service.session(draftID: start.id, action: .commit)
        let review = try await service.start(kind: .review, stepID: nil, range: nil, rakaat: nil, spotID: nil)
        XCTAssertEqual(review.coach?.plannedAyahs, [149])
        _ = try await service.session(draftID: review.id, action: review.primaryAction)
        _ = try await service.session(draftID: review.id, action: .advance)
        _ = try await service.session(draftID: review.id, action: .commit)
        let result = try await service.load()
        XCTAssertFalse(result.steps.contains { $0.kind == .review && !$0.completed })
        XCTAssertEqual(result.coverageFraction, 0)
        XCTAssertEqual(try ModelContext(app.container).fetch(FetchDescriptor<HifzSession>()).filter { $0.kind == "review" }.first?.pages, [22])
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
