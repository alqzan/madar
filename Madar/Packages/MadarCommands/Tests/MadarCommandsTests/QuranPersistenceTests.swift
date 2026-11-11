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

    @Test func pageHistoryIndexGroupsLargeChronologicalHistoryByPage() throws {
        let day = try GregorianDay("2026-10-15")
        let base = date("2026-10-15T10:00:00Z")
        let ayahs = try QuranAyahRange(first: 1, last: 7)
        func id(_ value: Int) -> UUID {
            UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
        }

        var sessions: [QuranSessionFact] = (1...604).map { page in
            QuranSessionFact(id: id(page), commitID: nil, kind: .hifz, dayKey: day,
                endedAt: base.addingTimeInterval(Double(page)), ayahs: ayahs, pages: [page],
                grades: [QuranDraftGrade(page: page, rating: .good)], mistakes: 0)
        }
        sessions.append(contentsOf: (0..<10_000).map { index in
            let page = index % 604 + 1
            let rating: QuranReviewRating = index.isMultiple(of: 2) ? .good : .needsMastery
            return QuranSessionFact(id: id(1_000 + index), commitID: nil, kind: .review, dayKey: day,
                endedAt: base.addingTimeInterval(Double(1_000 + index)), ayahs: ayahs, pages: [page],
                grades: [QuranDraftGrade(page: page, rating: rating)], mistakes: 0)
        })
        sessions.sort { $0.endedAt < $1.endedAt }

        let index = QuranPageHistoryIndex(sessions: sessions)
        #expect(index.completionSessions.count == 604)
        #expect(index.reviewsByPage.values.reduce(0) { $0 + $1.count } == 10_000)
        #expect(index.reviewsByPage[1]?.first?.sessionIndex == 604)
        #expect(index.reviewsByPage[1]?.last?.sessionIndex == 10_268)
        #expect(index.reviewsByPage[1]?.last?.grade.rating == .good)
    }

    @Test func pageHistoryIndexKeepsFirstCompletionAndLastGradeWithinEachSession() throws {
        let day = try GregorianDay("2026-10-15")
        let base = date("2026-10-15T10:00:00Z")
        let ayahs = try QuranAyahRange(first: 1, last: 7)
        func id(_ value: Int) -> UUID {
            UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
        }

        let firstCompletion = QuranSessionFact(id: id(1), commitID: nil, kind: .hifz, dayKey: day,
            endedAt: base, ayahs: ayahs, pages: [1],
            grades: [QuranDraftGrade(page: 1, rating: .good), QuranDraftGrade(page: 1, rating: .mastered)], mistakes: 0)
        let tiedCompletion = QuranSessionFact(id: id(2), commitID: nil, kind: .hifz, dayKey: day,
            endedAt: base, ayahs: ayahs, pages: [1],
            grades: [QuranDraftGrade(page: 1, rating: .needsMastery)], mistakes: 0)
        let review = QuranSessionFact(id: id(3), commitID: nil, kind: .review, dayKey: day,
            endedAt: base.addingTimeInterval(1), ayahs: ayahs, pages: [1],
            grades: [QuranDraftGrade(page: 1, rating: .good), QuranDraftGrade(page: 1, rating: .needsMastery)], mistakes: 0)

        let index = QuranPageHistoryIndex(sessions: [firstCompletion, tiedCompletion, review])
        let completion = index.completionSessions[.init(page: 1, endedAt: base)]
        #expect(completion?.session.id == id(1))
        #expect(completion?.rating == .good)
        #expect(index.reviewsByPage[1]?.count == 1)
        #expect(index.reviewsByPage[1]?.first?.sessionIndex == 2)
        #expect(index.reviewsByPage[1]?.first?.grade.rating == .needsMastery)
    }

    private func envelope(_ name: String, _ payload: [String: MadarCore.JSONValue], at: Date? = nil) -> CommandEnvelope {
        CommandEnvelope(name: name, payload: .object(payload), issuedAt: at ?? now)
    }
    private func makeDraft(_ container: ModelContainer, kind: QuranSessionKind = .hifz, first: Int = 1, last: Int = 7, page: Int = 1, at: Date? = nil) throws -> QuranDraftPayload {
        let key = try repo(container).currentDay(at: at ?? now)
        var draft = QuranSessionDraft(planID: nil, kind: kind, storedDay: key, startedAt: at ?? now,
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

    @Test func savingADraftNeverReadsTheWholeHistoryButAnUndoableCommandStillDoes() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeDraft(container)
        let before = QuranMutationHandler.historyReads
        try await save(draft, bus: bus)
        #expect(QuranMutationHandler.historyReads == before, "A draft save has no inverse, so it needs no full-history read")
        let planned = QuranMutationHandler.historyReads
        #expect(try await bus.execute(envelope("quran.savePlan", planPayload), now: now).status == .applied)
        #expect(QuranMutationHandler.historyReads > planned, "An undoable command still captures its before-state")
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

    private let planPayload: [String: MadarCore.JSONValue] = ["startAyah": .number(1), "unit": .string("page"), "amount": .number(1), "rhythm": .string("balanced"), "restDay": .string("none"), "missPolicy": .string("ask")]

    @Test func planStartDayFollowsDayStartAndForecastLevelIsHabitual() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("fajr")], now: now); try context.save()
        // §7.2/J01 Riyadh Fajr 04:31 on 9 Oct: a plan saved at 03:00 belongs to the Madar day of 8 Oct.
        let saved = date("2026-10-09T03:00:00+03:00")
        #expect(try await bus.execute(envelope("quran.savePlan", planPayload, at: saved), now: saved).status == .applied)
        let later = date("2026-10-10T12:00:00+03:00")
        #expect(try repo(container).snapshot(at: later).planStartDay == GregorianDay("2026-10-08"))
        // §7.4 forecast uses quran.hifzLevel; a one-day «عميق» changes today only.
        #expect(try await bus.execute(envelope("quran.setTodayLevel", ["kind": .string("hifz"), "level": .string("deep")], at: later), now: later).status == .applied)
        let snapshot = try repo(container).snapshot(at: later.addingTimeInterval(1))
        #expect(snapshot.hifzLevel == .deep && snapshot.habitualHifzLevel == .medium)
    }

    /// B2-7: editing the amount of the same plan is not starting over; only a different starting ayah begins a new plan.
    @Test func resavingTheSamePlanKeepsItsStartDayButANewStartAyahRestarts() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = date("2026-10-05T12:00:00+03:00"), second = date("2026-10-09T12:00:00+03:00"), third = date("2026-10-12T12:00:00+03:00")
        #expect(try await bus.execute(envelope("quran.savePlan", planPayload, at: first), now: first).status == .applied)
        var edited = planPayload; edited["amount"] = .number(2)
        #expect(try await bus.execute(envelope("quran.savePlan", edited, at: second), now: second).status == .applied)
        #expect(try repo(container).snapshot(at: second.addingTimeInterval(1)).planStartDay == GregorianDay("2026-10-05"))
        var elsewhere = planPayload; elsewhere["startAyah"] = .number(500)
        #expect(try await bus.execute(envelope("quran.savePlan", elsewhere, at: third), now: third).status == .applied)
        #expect(try repo(container).snapshot(at: third.addingTimeInterval(1)).planStartDay == GregorianDay("2026-10-12"))
    }

    /// B2-7 rule: a day already passed stays judged by the plan version that was active on it; the new amount applies from the change day.
    @Test func changingTheAmountDoesNotRejudgeDaysAlreadyPassed() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        func at(_ day: String) -> Date { date("2026-10-\(day)T12:00:00+03:00") }
        var planA = planPayload; planA["amount"] = .number(1)
        #expect(try await bus.execute(envelope("quran.savePlan", planA, at: at("05")), now: at("05")).status == .applied)
        // Followed under A on 5, 6 and 8 Oct; 7 Oct was missed.
        let catalog = try QuranResources.catalog()
        for (day, page) in [("05", 1), ("06", 2), ("08", 3)] {
            let draft = try makeDraft(container, first: catalog.ayahs(on: page).first!.id, last: catalog.ayahs(on: page).last!.id, page: page, at: at(day))
            try await save(draft, bus: bus, at: at(day))
            #expect(try await commit(draft, bus: bus, at: at(day).addingTimeInterval(60)).status == .applied)
        }
        var planB = planA; planB["amount"] = .number(3)
        #expect(try await bus.execute(envelope("quran.savePlan", planB, at: at("09")), now: at("09")).status == .applied)
        let after = at("09").addingTimeInterval(3600)
        let snapshot = try repo(container).snapshot(at: after)
        // The plan continues: day one is still 5 Oct, version 2 carries amount B, nothing was created for the days already done.
        #expect(snapshot.planStartDay == (try GregorianDay("2026-10-05")))
        #expect(snapshot.plan?.plan.amount == 3 && snapshot.plan?.version == 2)
        #expect(snapshot.allotments.isEmpty)
        #expect(Set(snapshot.sessions.map { $0.dayKey.description }) == ["2026-10-05", "2026-10-06", "2026-10-08"])
        let rows = try ModelContext(container).fetch(FetchDescriptor<HifzPlan>()).sorted { $0.version < $1.version }
        #expect(rows.map(\.version) == [1, 2] && rows[0].supersededAt == at("09") && rows[1].supersededAt == nil)
        // The missed 7 Oct was a one-page day under A: settling it owes one page, not B's three.
        let resolved = try await bus.execute(envelope("quran.resolveMissedDay", ["dayKey": .string("2026-10-07"), "choice": .string("double")], at: after), now: after)
        #expect(resolved.status == .applied)
        let owed = try repo(container).snapshot(at: after.addingTimeInterval(1)).allotments.filter { $0.origin == .missPolicy }
        #expect(owed.count == 1 && owed[0].amount == 1 && owed[0].originDayKey.description == "2026-10-07")
    }

    @Test func needsGradeTurnsTheNextDayIntoConsolidationNotToday() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let planAt = now.addingTimeInterval(-3 * 86400)
        #expect(try await bus.execute(envelope("quran.savePlan", planPayload, at: planAt), now: planAt).status == .applied)
        var draft = try makeDraft(container)
        draft.draft.grades = [QuranDraftGrade(page: 1, rating: .needsMastery)]
        try await save(draft, bus: bus)
        #expect(try await commit(draft, bus: bus).status == .applied)
        // RQ3 / §7.4: «يحتاج» stops new hifz the next day; the day it was graded keeps its own label.
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(120)).hifz?.balance != .consolidation)
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(86400)).hifz?.balance == .consolidation)
    }

    @Test func recentFacesAreTheMostRecentlyMemorisedNotTheHighest() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try QuranResources.catalog()
        func memorise(_ pages: ClosedRange<Int>, at time: Date) async throws {
            var value = try makeDraft(container, first: catalog.ayahs(on: pages.lowerBound).first!.id, last: catalog.ayahs(on: pages.upperBound).last!.id, page: pages.lowerBound, at: time)
            value.draft.grades = pages.map { QuranDraftGrade(page: $0, rating: .mastered) }
            try await save(value, bus: bus, at: time)
            #expect(try await commit(value, bus: bus, at: time.addingTimeInterval(60)).status == .applied)
        }
        // Faces 10–20 first, then the gap 2–3 filled later: with no plan the rhythm is balanced (five recent faces).
        try await memorise(10...20, at: now.addingTimeInterval(-3 * 86400))
        try await memorise(2...3, at: now.addingTimeInterval(-86400))
        let recent = try repo(container).snapshot(at: now).recentPages
        #expect(recent == [2, 3, 18, 19, 20])
    }

    @Test func undoneDayChoiceAndMissedDayCanBeChosenAgain() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        func undo(_ result: CommandOutcome, at time: Date) async throws {
            let token = try #require(result.undoToken)
            #expect(try await bus.execute(envelope("system.undo", ["undoToken": .string(token.uuidString)], at: time), now: time).status == .applied)
        }
        // A tombstoned day choice must not lock today's level (undo leaves the day usable).
        let first = try await bus.execute(envelope("quran.setTodayLevel", ["kind": .string("hifz"), "level": .string("deep")]), now: now)
        #expect(first.status == .applied)
        try await undo(first, at: now.addingTimeInterval(10))
        #expect(try repo(container).snapshot(at: now.addingTimeInterval(20)).hifzLevel != .deep)
        let again = now.addingTimeInterval(30)
        #expect(try await bus.execute(envelope("quran.setTodayLevel", ["kind": .string("review"), "level": .string("max")], at: again), now: again).status == .applied)
        let revived = try repo(container).snapshot(at: again.addingTimeInterval(1))
        #expect(revived.reviewLevel == .max && revived.hifzLevel != .deep)
        // The dedupe pass after an import must not re-delete the revived row.
        let mergeContext = ModelContext(container)
        _ = try RowMerger(context: mergeContext).run(); try mergeContext.save()
        #expect(try repo(container).snapshot(at: again.addingTimeInterval(2)).reviewLevel == .max)
        // A missed-day choice that was undone can be chosen again.
        let planAt = now.addingTimeInterval(-5 * 86400)
        let plan: [String: MadarCore.JSONValue] = ["startAyah": .number(1), "unit": .string("page"), "amount": .number(1), "rhythm": .string("balanced"), "restDay": .string("none"), "missPolicy": .string("ask")]
        #expect(try await bus.execute(envelope("quran.savePlan", plan, at: planAt), now: planAt).status == .applied)
        let missed = try repo(container).currentDay(at: now).date.adding(days: -1).description
        let resolve = envelope("quran.resolveMissedDay", ["dayKey": .string(missed), "choice": .string("double")], at: again.addingTimeInterval(60))
        let resolved = try await bus.execute(resolve, now: again.addingTimeInterval(60))
        #expect(resolved.status == .applied)
        try await undo(resolved, at: again.addingTimeInterval(70))
        #expect(try repo(container).snapshot(at: again.addingTimeInterval(80)).allotments.isEmpty)
        let redo = try await bus.execute(envelope("quran.resolveMissedDay", ["dayKey": .string(missed), "choice": .string("double")], at: again.addingTimeInterval(90)), now: again.addingTimeInterval(90))
        #expect(redo.status == .applied)
        #expect(!(try repo(container).snapshot(at: again.addingTimeInterval(100)).allotments.isEmpty))
        let merge = ModelContext(container); _ = try RowMerger(context: merge).run(); try merge.save()
        #expect(!(try repo(container).snapshot(at: again.addingTimeInterval(110)).allotments.isEmpty))
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

    @Test func unreadableDraftDoesNotBlockQuranSnapshotOrEraseSavedBytes() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeDraft(container)
        try await save(draft, bus: bus)
        let corrupted = Data("{malformed".utf8)
        let context = ModelContext(container)
        let row = try #require(context.fetch(FetchDescriptor<SessionDraft>()).first)
        row.provisionalJSON = corrupted
        try context.save()

        let snapshot = try repo(container).snapshot(at: now)
        #expect(snapshot.drafts.isEmpty)
        #expect(snapshot.unreadableDraftCount == 1)
        let preserved = try #require(ModelContext(container).fetch(FetchDescriptor<SessionDraft>()).first)
        #expect(preserved.provisionalJSON == corrupted)
        #expect(preserved.deletedAt == nil)
    }

    /// Audit (11 Nov 2026): an unreadable stored row (an unknown session kind, grade or allotment origin) is skipped and counted, as drafts
    /// are; the Quran snapshot and the habits linked to it still read, and the row stays stored as it is.
    @Test func unreadableQuranRowsAreSkippedAndCountedWithoutBlockingTheRoomOrHabits() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try makeDraft(container)
        try await save(draft, bus: bus)
        #expect(try await commit(draft, bus: bus).status == .applied)
        let context = ModelContext(container)
        let good = try #require(context.fetch(FetchDescriptor<HifzSession>()).first)
        let badSession = HifzSession(); badSession.kind = "futureKind"; badSession.dayKey = good.dayKey; badSession.fromAyah = 1; badSession.toAyah = 7
        badSession.endedAt = good.endedAt; badSession.pages = [1]; context.insert(badSession)
        let badGrade = PageGrade(); badGrade.sessionID = good.id; badGrade.page = 2; badGrade.grade = "futureGrade"; context.insert(badGrade)
        let badAllotment = QuranAllotment(); badAllotment.dayKey = good.dayKey; badAllotment.kind = "hifzExtra"; badAllotment.origin = "futureOrigin"
        badAllotment.originDayKey = good.dayKey; badAllotment.amount = 1; context.insert(badAllotment)
        try context.save()
        let later = good.endedAt.addingTimeInterval(60)
        let snapshot = try repo(container).snapshot(at: later)
        #expect(snapshot.unreadableRowCount == 3)
        #expect(snapshot.sessions.map(\.id) == [good.id] && snapshot.allotments.isEmpty)
        #expect(snapshot.sessions.first?.grades.contains { $0.page == 2 } == false)
        // A habit linked to the Quran still reads.
        let habit = UUID(); var rule = HabitRule(effectiveFrom: try GregorianDay(good.dayKey)); rule.measure = .count; rule.unit = "وجه"
        let payload: [String: MadarCore.JSONValue] = ["id": .string(habit.uuidString), "name": .string("المراجعة"), "source": .string("review"),
            "rule": try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))]
        let saved = try await bus.execute(envelope("habit.save", payload, at: later), now: later)
        #expect(saved.status == .applied, "\(saved.reason ?? "")")
        #expect(try HabitRepository(context: ModelContext(container)).readings(at: later).contains { $0.id == habit })
        // Nothing was changed or deleted.
        #expect(try ModelContext(container).fetch(FetchDescriptor<HifzSession>()).contains { $0.kind == "futureKind" && $0.deletedAt == nil })
    }

    /// D8 (owner, 11 Nov 2026): a bookmark has a name and a page; saving the same id renames it, delete leaves a tombstone,
    /// and the list is in page order. A page outside 1...604 or an empty name is refused.
    @Test func namedMushafBookmarksSaveRenameDeleteAndRefuseBadInput() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID(), second = UUID()
        func save(_ id: UUID, _ page: Double, _ name: String, _ offset: TimeInterval) async throws -> CommandOutcome {
            try await bus.execute(envelope("quran.saveBookmark", ["id": .string(id.uuidString), "page": .number(page), "name": .string(name)], at: now.addingTimeInterval(offset)), now: now.addingTimeInterval(offset))
        }
        #expect(try await save(first, 300, "  الكهف ", 1).status == .applied)
        #expect(try await save(second, 12, "المراجعة", 2).status == .applied)
        #expect(try repo(container).bookmarks().map { [$0.name, String($0.page)] } == [["المراجعة", "12"], ["الكهف", "300"]])
        #expect(try await save(first, 301, "الكهف ٢", 3).status == .applied)
        #expect(try repo(container).bookmarks().last.map { [$0.name, String($0.page)] } == ["الكهف ٢", "301"])
        for bad in [(605.0, "x"), (0.0, "x"), (10.0, "   "), (10.5, "x"), (10.0, String(repeating: "ا", count: 41))] {
            let result = try? await save(UUID(), bad.0, bad.1, 4)
            #expect(result == nil || result?.status != .applied)
        }
        #expect(try repo(container).bookmarks().count == 2)
        let deleted = try await bus.execute(envelope("quran.deleteBookmark", ["id": .string(second.uuidString)], at: now.addingTimeInterval(5)), now: now.addingTimeInterval(5))
        #expect(deleted.status == .applied)
        #expect(try repo(container).bookmarks().map(\.id) == [first])
        let rows = try ModelContext(container).fetch(FetchDescriptor<MushafBookmark>())
        #expect(rows.count == 2 && rows.first { $0.id == second }?.deletedAt != nil)
    }

    @Test func discardUnreadableDraftsPreservesBytesAndHealthyDrafts() async throws {
        let (container, bus, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let broken = try makeDraft(container)
        try await save(broken, bus: bus)
        let corrupted = Data("{malformed".utf8)
        let context = ModelContext(container)
        let brokenRow = try #require(context.fetch(FetchDescriptor<SessionDraft>()).first)
        brokenRow.provisionalJSON = corrupted
        try context.save()

        let healthy = try makeDraft(container)
        try await save(healthy, bus: bus)
        #expect(try repo(container).snapshot(at: now).unreadableDraftCount == 1)

        let result = try await bus.execute(envelope("quran.discardUnreadableDrafts", [:]), now: now.addingTimeInterval(1))
        #expect(result.status == .applied)
        let snapshot = try repo(container).snapshot(at: now.addingTimeInterval(2))
        #expect(snapshot.unreadableDraftCount == 0)
        #expect(snapshot.drafts.map(\.id) == [healthy.draft.id])

        let rows = try ModelContext(container).fetch(FetchDescriptor<SessionDraft>())
        let preserved = try #require(rows.first { $0.id == broken.draft.id })
        #expect(preserved.provisionalJSON == corrupted)
        #expect(preserved.deletedAt != nil)
        #expect(rows.first { $0.id == healthy.draft.id }?.deletedAt == nil)
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
        let updated = try repo(container).snapshot(at: now.addingTimeInterval(300))
        #expect(updated.memories[1]?.intervalDays == 1)
        #expect(updated.pages.first { $0.page == 1 }?.grade == .needsMastery)
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
