import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
import MadarQuran
@testable import MadarCommands

@Suite(.serialized) @MainActor struct QuranPersistenceTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-10-15T10:00:00Z") }
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MadarQuranPersistence-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: directory)
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight")], now: now)
        try context.save()
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory, transactionClock: { $0 })), directory)
    }
    private func repo(_ container: ModelContainer) throws -> QuranRepository {
        try QuranRepository(context: ModelContext(container), catalog: QuranResources.catalog())
    }
    private func envelope(_ name: String, _ payload: [String: MadarCore.JSONValue], at: Date? = nil) -> CommandEnvelope {
        CommandEnvelope(name: name, payload: .object(payload), issuedAt: at ?? now)
    }
    private func makeDraft(_ container: ModelContainer, kind: QuranSessionKind = .hifz, first: Int = 1, last: Int = 7, page: Int = 1) throws -> QuranDraftPayload {
        let key = try repo(container).currentDay(at: now)
        var draft = QuranSessionDraft(planID: nil, kind: kind, storedDay: key, startedAt: now,
            portions: [try QuranAyahRange(first: first, last: last)], page: page, ayahID: first)
        draft.coachStage = .blindRecitation; draft.blindPassedAyahs = kind == .hifz ? Set(first...last) : []
        draft.grades = [QuranDraftGrade(page: page, rating: .mastered)]
        return QuranDraftPayload(draft: draft)
    }
    private func save(_ value: QuranDraftPayload, bus: CommandBus, at: Date? = nil) async throws {
        let data = try JSONEncoder().encode(value).base64EncodedString()
        let result = try await bus.execute(envelope("quran.saveDraft", ["draft": .string(data)], at: at), now: at ?? now)
        #expect(result.status == .applied)
    }
    private func commit(_ draft: QuranDraftPayload, bus: CommandBus, at: Date? = nil) async throws -> CommandOutcome {
        let time = at ?? now.addingTimeInterval(60)
        return try await bus.execute(envelope("quran.commitSession", ["draftID": .string(draft.draft.id.uuidString)], at: time), now: time)
    }

    @Test func QuranDayUsesSelectedPrayerOffsetsBeforeFajr() throws {
        let (container, _, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        var offsets = try settings.value(for: "salah.offsets").object ?? [:]
        offsets["fajr"] = .number(10)
        _ = try settings.stage(["core.dayStart": .string("fajr"), "salah.offsets": .object(offsets)], now: now)
        try context.save()
        // §7.2 / J01 fixture: Riyadh Oct 9 Fajr 04:31; +10 min => 04:41.
        // At 04:35 the Quran day is still Oct 8, rather than the unadjusted Oct 9.
        let captured = try repo(container).currentDay(at: date("2026-10-09T04:35:00+03:00"))
        #expect(captured.dayKey == "2026-10-08" && captured.boundary == .fajr)
    }

    @Test func commitChildrenReceiptAndDraftTogetherReplayUndoLeavesNoCoverageScheduleOrStreak() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var draft = try makeDraft(container)
        draft.draft.mistakes = [QuranDraftMistake(key: QuranMistakeKey(ayahID: 3, wordIndex: nil), at: now, kind: .mistake)]
        try await save(draft, bus: bus)
        let result = try await commit(draft, bus: bus)
        #expect(result.status == .applied && result.undoToken != nil)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<HifzSession>()).filter { $0.deletedAt == nil }.count == 1)
        #expect(try context.fetch(FetchDescriptor<PageGrade>()).filter { $0.deletedAt == nil }.count == 1)
        #expect(try context.fetch(FetchDescriptor<MistakeEvent>()).filter { $0.deletedAt == nil }.count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionDraft>()).allSatisfy { $0.deletedAt != nil })
        let before = try repo(container).snapshot(at: now.addingTimeInterval(120))
        #expect(before.coverage.completedPages == [1]); #expect(before.memories[1]?.intervalDays == 3)
        #expect(try await commit(draft, bus: bus).status == .duplicate)
        let token = try #require(result.undoToken)
        #expect(try await bus.execute(envelope("system.undo", ["undoToken": .string(token.uuidString)], at: now.addingTimeInterval(180)), now: now.addingTimeInterval(180)).status == .applied)
        let after = try repo(container).snapshot(at: now.addingTimeInterval(240))
        #expect(after.coverage.coveredAyahs.isEmpty && after.pages.isEmpty && after.mistakes.isEmpty)
        #expect(QuranProgressEngine.streak(activities: after.activities, through: after.day.date).days == 0)
        #expect(try await commit(draft, bus: bus, at: now.addingTimeInterval(240)).status == .duplicate)
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(240)).sessions.isEmpty)
    }

    @Test func reopenPreservesDraftPositionDayAndTemporaryFactsThenCommitRemovesIt() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var draft = try makeDraft(container); draft.draft.ayahID = 4; draft.draft.blindPassedAyahs = [1, 2, 3]
        try await save(draft, bus: bus)
        let reopened = try MadarContainerFactory.makeLocal(at: directory)
        let value = try #require(try repo(reopened).draft(draft.draft.id))
        #expect(value.ayahID == 4 && value.coachStage == .blindRecitation && value.blindPassedAyahs == [1, 2, 3])
        #expect(value.storedDay == draft.draft.storedDay)
        let fresh = CommandBus(adapter: DurableCommandAdapter(container: reopened, lockDirectory: directory, transactionClock: { $0 }))
        #expect(try await commit(draft, bus: fresh).status == .applied)
        let snapshot = try repo(reopened).snapshot(at: now.addingTimeInterval(120))
        #expect(snapshot.drafts.isEmpty && snapshot.coverage.coveredAyahs == [1, 2, 3])
    }

    @Test func deleteAndUndoRestoreSessionChildrenAndScheduleButStaleUndoDoesNotOverwriteGrade() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeDraft(container); try await save(draft, bus: bus); let committed = try await commit(draft, bus: bus)
        let snapshot = try repo(container).snapshot(at: now.addingTimeInterval(120)), session = try #require(snapshot.sessions.first)
        let deleted = try await bus.execute(envelope("quran.deleteSession", ["sessionID": .string(session.id.uuidString)], at: now.addingTimeInterval(120)), now: now.addingTimeInterval(120))
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(180)).coverage.coveredAyahs.isEmpty)
        let token = try #require(deleted.undoToken)
        _ = try await bus.execute(envelope("system.undo", ["undoToken": .string(token.uuidString)], at: now.addingTimeInterval(180)), now: now.addingTimeInterval(180))
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(240)).coverage.completedPages == [1])
        _ = try await bus.execute(envelope("quran.editSessionGrade", ["sessionID": .string(session.id.uuidString), "page": .number(1), "grade": .string("needs")], at: now.addingTimeInterval(240)), now: now.addingTimeInterval(240))
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(300)).memories[1]?.intervalDays == 1)
        let staleToken = try #require(committed.undoToken)
        await #expect(throws: (any Error).self) { try await bus.execute(envelope("system.undo", ["undoToken": .string(staleToken.uuidString)], at: now.addingTimeInterval(300)), now: now.addingTimeInterval(300)) }
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(300)).coverage.completedPages == [1])
    }

    @Test func failedQiyamLinkRollsBackSessionChildrenAndRetainsDraft() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let hifz = try makeDraft(container); try await save(hifz, bus: bus); _ = try await commit(hifz, bus: bus)
        var qiyam = try makeDraft(container, kind: .qiyam)
        qiyam.nightKey = try GregorianDay("2026-10-14"); qiyam.rakats = 2
        let context = ModelContext(container), night = QiyamNight(); night.nightKey = "2026-10-14"; night.quranSessionID = UUID()
        context.insert(night); try context.save()
        try await save(qiyam, bus: bus, at: now.addingTimeInterval(120))
        await #expect(throws: (any Error).self) { try await commit(qiyam, bus: bus, at: now.addingTimeInterval(180)) }
        let snapshot = try repo(container).snapshot(at: now.addingTimeInterval(240))
        #expect(snapshot.sessions.count == 1 && snapshot.drafts.count == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PageGrade>()).filter { $0.deletedAt == nil }.count == 1)
    }

    @Test func discardCreatesNoSessionAndUnmemorizedFreeReviewCannotCommit() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeDraft(container, kind: .free); try await save(draft, bus: bus)
        await #expect(throws: (any Error).self) { try await commit(draft, bus: bus) }
        _ = try await bus.execute(envelope("quran.discardDraft", ["draftID": .string(draft.draft.id.uuidString)]), now: now)
        let snapshot = try repo(container).snapshot(at: now.addingTimeInterval(120))
        #expect(snapshot.sessions.isEmpty && snapshot.drafts.isEmpty && snapshot.coverage.coveredAyahs.isEmpty)
    }

    @Test func planVersioningKeepsHistoryAndRestDayUndoAndAppOnlyAuthorization() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let payload: [String: MadarCore.JSONValue] = ["startAyah": .number(149), "unit": .string("half"), "amount": .number(1),
            "rhythm": .string("balanced"), "restDay": .string("saturday"), "missPolicy": .string("ask")]
        let widget = CommandEnvelope(name: "quran.savePlan", payload: .object(payload), source: .widget, issuedAt: now)
        #expect(try await bus.execute(widget, now: now).status == .needsApp)
        let first = try await bus.execute(envelope("quran.savePlan", payload), now: now)
        #expect(first.undoToken != nil)
        let snapshot = try repo(container).snapshot(at: now)
        #expect(snapshot.plan?.plan.startAyah == 149 && snapshot.restDay == .saturday)
        let next = now.addingTimeInterval(30)
        _ = try await bus.execute(envelope("quran.savePlan", payload, at: next), now: next)
        #expect(try repo(container).snapshot(at: next).plan?.version == 2)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HifzPlan>()).count == 2)
        let token = try #require(first.undoToken)
        await #expect(throws: (any Error).self) { try await bus.execute(envelope("system.undo", ["undoToken": .string(token.uuidString)], at: next), now: next) }
    }
}

@Suite(.serialized) @MainActor struct QuranCycleResourceTests {
    @Test func weeklyGroupingUsesVerified1439AyahBoundariesAndCoversQuranOnce() throws {
        let catalog = try QuranResources.catalog(), segments = try catalog.manzilCycleSegments()
        // Source stations begin at 1:1, 5:1, 10:1, 17:1, 26:1, 37:1, 50:1.
        #expect(segments.map(\.ayahs.first) == [1, 670, 1365, 2030, 2933, 3789, 4631])
        #expect(segments.last?.ayahs.last == 6236)
        #expect(segments.reduce(0) { $0 + $1.ayahs.last - $1.ayahs.first + 1 } == 6236)
    }
}
