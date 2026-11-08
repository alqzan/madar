import Foundation
import SwiftData
import MadarData
import MadarCore
import MadarPrayer
import MadarQuran

public struct QuranPlanRecord: Sendable {
    public let plan: QuranPlan
    public let version: Int
    public let missPolicy: String
    public let activeFrom: Date
}
public struct QuranSessionFact: Sendable {
    public let id: UUID
    public let commitID: UUID?
    public let kind: QuranSessionKind
    public let dayKey: GregorianDay
    public let endedAt: Date
    public let ayahs: QuranAyahRange
    public let pages: [Int]
    public let grades: [QuranDraftGrade]
    public let mistakes: Int
}
public struct QuranDataSnapshot: Sendable {
    public let day: StoredDayKey
    public let plan: QuranPlanRecord?
    public let coverage: QuranCoverage
    public let sessions: [QuranSessionFact]
    public let pages: [QuranPlanningPage]
    public let memories: [Int: QuranPageMemory]
    public let completedOn: [Int: GregorianDay]
    public let activities: [QuranActivityDay]
    public let hifzLevel: QuranDayLevel
    public let reviewLevel: QuranDayLevel
    public let restDay: QuranRestDay
    public let forceNewHifz: Bool
    public let hifz: QuranDailyHifz?
    public let review: QuranDailyReview
    public let recentPages: [Int]
    public let partialRecent: [QuranPartialPage]
    public let allotments: [QuranDailyAllotment]
    public let recovery: QuranRecoveryPlan?
    public let mistakes: [QuranMistakeSpotSummary]
    public let drillBoard: QuranDrillBoard
    /// The plan's first Madar day under core.dayStart, and the habitual hifz level (the forecast ignores a one-day choice).
    public let planStartDay: GregorianDay?
    public let habitualHifzLevel: QuranDayLevel
    public let drafts: [QuranSessionDraft]
    public let lastTest: GregorianDay?
    public let testPages: [Int]
}

struct QuranPageHistoryIndex: Sendable {
    struct CompletionKey: Hashable {
        let page: Int
        let endedAt: Date
    }

    struct ReviewFact: Sendable {
        let sessionIndex: Int
        let session: QuranSessionFact
        let grade: QuranDraftGrade
    }

    struct CompletionFact: Sendable {
        let session: QuranSessionFact
        let rating: QuranReviewRating?
    }

    private(set) var completionSessions: [CompletionKey: CompletionFact] = [:]
    private(set) var reviewsByPage: [Int: [ReviewFact]] = [:]

    /// Input sessions are chronological. Keep the first matching hifz session and the last grade per page,
    /// matching the old sorted-session searches while paying the indexing cost once per snapshot.
    init(sessions: [QuranSessionFact]) {
        for (index, session) in sessions.enumerated() {
            if session.kind == .hifz {
                var firstGradeByPage: [Int: QuranReviewRating] = [:]
                for grade in session.grades where firstGradeByPage[grade.page] == nil {
                    firstGradeByPage[grade.page] = grade.rating
                }
                for page in session.pages {
                    let key = CompletionKey(page: page, endedAt: session.endedAt)
                    if completionSessions[key] == nil {
                        completionSessions[key] = CompletionFact(session: session, rating: firstGradeByPage[page])
                    }
                }
            }

            guard [.review, .free, .qiyam].contains(session.kind) else { continue }
            var lastGradeByPage: [Int: QuranDraftGrade] = [:]
            for grade in session.grades { lastGradeByPage[grade.page] = grade }
            for (page, grade) in lastGradeByPage {
                reviewsByPage[page, default: []].append(.init(sessionIndex: index, session: session, grade: grade))
            }
        }
    }
}

public final class QuranRepository {
    public let context: ModelContext
    public let catalog: QuranResourceCatalog
    public let settings: SettingsStore
    public init(context: ModelContext, catalog: QuranResourceCatalog) throws {
        self.context = context; self.catalog = catalog; settings = try SettingsStore(context: context)
    }
    public func currentDay(at now: Date) throws -> StoredDayKey {
        let prayers = try PrayerRepository(context: context)
        let place = prayers.place(at: now), civil = GregorianDay.containing(now, in: place.timeZone)
        let options = prayers.activeTrip(at: now) == nil ? prayers.options : prayers.tripOptions
        let days = PrayerTimesEngine.calculate(day: civil, place: place, options: options).map { [$0] } ?? []
        return try MadarDay.resolve(instant: now, place: place,
            boundary: DayBoundary(rawValue: settings.value(for: "core.dayStart").string ?? "fajr") ?? .fajr,
            prayerDays: days, hijriSource: HijriSource(rawValue: settings.value(for: "core.hijriSource").string ?? "ummAlQura") ?? .ummAlQura,
            sightingOffset: Int(settings.value(for: "core.hijriOffset").number ?? 0))
    }
    public func draft(_ id: UUID) throws -> QuranSessionDraft? {
        let row = try context.fetch(FetchDescriptor<SessionDraft>()).first { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }
        guard let row else { return nil }
        let value = try JSONDecoder().decode(QuranDraftPayload.self, from: row.provisionalJSON).draft
        guard value.id == row.id, value.storedDay.dayKey == row.dayKey, value.kind.rawValue == row.kind else {
            throw DataError.invalidValue("Quran draft identity")
        }
        return value
    }
    /// Rebuild the pre-day cache at the same evaluation day, without changing stored facts.
    public func snapshot(at now: Date, excludingSessionDay: GregorianDay? = nil, sessionsThrough: Date? = nil, previewHifzLevel: QuranDayLevel? = nil) throws -> QuranDataSnapshot {
        let storedDay = try currentDay(at: now), today = storedDay.date
        let planRows = try context.fetch(FetchDescriptor<HifzPlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let active = planRows.filter { $0.activeFrom <= now && $0.supersededAt == nil }.max {
            $0.version == $1.version ? $0.id.uuidString < $1.id.uuidString : $0.version < $1.version
        }
        let plan: QuranPlanRecord? = try active.map { row in
            guard row.direction == "forward", let unit = QuranHifzUnit(rawValue: row.unit),
                  let rhythm = QuranReviewIntensity(rawValue: row.rhythm) else { throw DataError.invalidValue("Quran plan") }
            return QuranPlanRecord(plan: try QuranPlan(id: row.id, startAyah: row.startAyah, unit: unit, amount: row.amount, intensity: rhythm),
                version: row.version, missPolicy: row.missPolicy, activeFrom: row.activeFrom)
        }
        let cutoff = min(now, sessionsThrough ?? now)
        let sessionRows = try context.fetch(FetchDescriptor<HifzSession>()).filter {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.endedAt <= cutoff && $0.dayKey != excludingSessionDay?.description
        }
        let gradeRows = try context.fetch(FetchDescriptor<PageGrade>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let gradesBySession = Dictionary(grouping: gradeRows.compactMap { row -> PageGrade? in row.sessionID == nil ? nil : row }, by: { $0.sessionID! })
        var sessions: [QuranSessionFact] = try sessionRows.map { row -> QuranSessionFact in
            guard let kind = QuranSessionKind(rawValue: row.kind) else { throw DataError.invalidValue("Quran session kind") }
            let grades = try (gradesBySession[row.id] ?? []).map { grade -> QuranDraftGrade in
                guard (1...604).contains(grade.page), let rating = QuranReviewRating(storedRaw: grade.grade) else { throw DataError.invalidValue("Quran grade") }
                return QuranDraftGrade(page: grade.page, rating: rating, isTest: grade.role == "test")
            }
            let key = try GregorianDay(row.dayKey)
            let range = try QuranAyahRange(first: row.fromAyah, last: row.toAyah)
            return QuranSessionFact(id: row.id, commitID: row.commitID, kind: kind, dayKey: key,
                endedAt: row.endedAt, ayahs: range, pages: row.pages, grades: grades, mistakes: row.mistakes)
        }
        sessions.sort { $0.endedAt == $1.endedAt ? $0.id.uuidString < $1.id.uuidString : $0.endedAt < $1.endedAt }
        let pageHistory = QuranPageHistoryIndex(sessions: sessions)
        let coverage = try QuranCoverageEngine.summarize(sessions: sessions.map {
            QuranCoverageSession(id: $0.id.uuidString, kind: $0.kind, ayahs: $0.ayahs, endedAt: $0.endedAt)
        }, catalog: catalog)
        let activities: [QuranActivityDay] = sessions.map { fact in
            QuranActivityDay(dayKey: fact.dayKey, kind: fact.kind, gradedPages: Set(fact.grades.map(\.page)),
                hifzAyahs: fact.kind == .hifz ? Set(fact.ayahs.first...fact.ayahs.last) : [])
        }
        var memories: [Int: QuranPageMemory] = [:]
        var pages: [QuranPlanningPage] = [], completedOn: [Int: GregorianDay] = [:], intervals: [Int] = []
        for page in coverage.completedPages.sorted() {
            guard let completedAt = coverage.memorizedAt[page],
                  let completion = pageHistory.completionSessions[.init(page: page, endedAt: completedAt)] else {
                throw DataError.invalidValue("Quran completion provenance")
            }
            let completing = completion.session
            completedOn[page] = completing.dayKey
            var events = [QuranReviewEvent(pages: try QuranPageRange(first: page, last: page), day: completing.dayKey,
                rating: completion.rating ?? .good, occurredAt: Int64(completing.endedAt.timeIntervalSince1970 * 1000))]
            var lastGrade = events[0].rating
            for review in pageHistory.reviewsByPage[page] ?? [] where review.session.endedAt > completedAt {
                events.append(QuranReviewEvent(pages: try QuranPageRange(first: page, last: page), day: review.session.dayKey,
                    rating: review.grade.rating, occurredAt: Int64(review.session.endedAt.timeIntervalSince1970 * 1000), inputOrder: review.sessionIndex))
                lastGrade = review.grade.rating
            }
            let memory = QuranReviewEngine.memory(forPage: page, events: events, through: today, preset: plan?.plan.intensity.preset ?? .balanced)
            guard let last = memory.lastReviewed else { continue }
            intervals.append(memory.intervalDays); memories[page] = memory
            pages.append(try QuranPlanningPage(page: page, lastReviewed: last, nextDue: last.adding(days: memory.intervalDays), grade: lastGrade, today: today))
        }
        let dayState = try context.fetch(FetchDescriptor<QuranDayState>()).filter { $0.dayKey == today.description && $0.deletedAt == nil && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }
        let hifzLevel = try previewHifzLevel ?? QuranDayLevel(rawValue: dayState?.hifzLevel ?? settings.value(for: "quran.hifzLevel").string ?? "medium") ?? .medium
        let reviewLevel = try QuranDayLevel(rawValue: dayState?.reviewLevel ?? settings.value(for: "quran.reviewLevel").string ?? "medium") ?? .medium
        let restDay = try QuranRestDay(rawValue: settings.value(for: "quran.restDay").string ?? "friday") ?? .friday
        let allotments = try context.fetch(FetchDescriptor<QuranAllotment>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { row in
            guard let kind = QuranDailyAllotment.Kind(rawValue: row.kind), let origin = QuranDailyAllotment.Origin(rawValue: row.origin) else { throw DataError.invalidValue("Quran allotment") }
            return try QuranDailyAllotment(dayKey: GregorianDay(row.dayKey), kind: kind, amount: row.amount, pages: row.pages, origin: origin, originDayKey: GregorianDay(row.originDayKey))
        }
        let recoveryRow = try context.fetch(FetchDescriptor<RecoveryPlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.cancelledAt == nil }.max { $0.updatedAt < $1.updatedAt }
        let recovery = try recoveryRow.map { try QuranRecoveryPlan(startDayKey: GregorianDay($0.startDayKey), days: $0.days, pages: $0.pages) }
        let recentCount = switch plan?.plan.intensity ?? .balanced { case .light: 3; case .balanced: 5; case .intense: 8 }
        // «القريب» = the faces memorised most recently (completion time; ties → the higher face), so a filled gap counts as recent.
        let recent = coverage.completedPages.sorted {
            let l = coverage.memorizedAt[$0] ?? .distantPast, r = coverage.memorizedAt[$1] ?? .distantPast
            return l == r ? $0 < $1 : l < r
        }.suffix(recentCount).sorted()
        var reviewedOn: [Int: GregorianDay] = [:]
        for session in sessions where [.review, .free, .qiyam].contains(session.kind) {
            for grade in session.grades { reviewedOn[grade.page] = Swift.max(reviewedOn[grade.page] ?? session.dayKey, session.dayKey) }
        }
        let share = recovery?.share(on: today, reviewedOn: reviewedOn) ?? []
        let lastTest = sessions.filter { $0.grades.contains(where: \.isTest) }.map(\.dayKey).max()
        let frozen = dayState.map(\.testPages).flatMap { $0.isEmpty ? nil : $0 }
        let tests = QuranRecoveryEngine.testPages(on: today, lastTest: lastTest, frozen: frozen, pages: pages, recent: Set(recent),
            selectionIndex: QuranRecoveryEngine.daySelectionIndex(today))
        let completedToday = Set(sessions.filter { $0.dayKey == today && [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) })
        let raised = allotments.filter { $0.dayKey == today && $0.kind == .reviewExtra }.flatMap(\.pages)
        let mode = QuranReviewScheduleMode(rawValue: try settings.value(for: "quran.reviewSchedule").string ?? "spaced") ?? .spaced
        // core.dayStart governs the plan's first day too (a plan saved before Fajr belongs to the previous Madar day).
        let planStartDay = try plan.map { try currentDay(at: $0.activeFrom).date }
        let cycleStart = planStartDay ?? today
        let cycle = try QuranFixedCycleEngine.target(mode: mode, cycleStartDayKey: cycleStart, todayDayKey: today,
            juzSegments: catalog.juzCycleSegments(), manzilSegments: catalog.manzilCycleSegments())
        let cyclePages = cycle.map { target in
            pages.filter { page in catalog.ayahs(on: page.page).contains { (target.ayahs.first...target.ayahs.last).contains($0.id) } }.map(\.page)
        } ?? []
        let review = QuranDailyPlanEngine.review(pages: pages, recent: recent + cyclePages, level: reviewLevel,
            recovery: share, raised: raised, test: tests, completedToday: completedToday, serveDue: mode == .spaced)
        let dueCount = mode == .spaced ? pages.filter { $0.isDue && !recent.contains($0.page) }.count : cyclePages.filter { !recent.contains($0) }.count
        let need = QuranReviewEngine.need(recentCount: recent.count + coverage.partialRecentPortions.count,
            memorizedIntervals: intervals, dueCount: dueCount, recoveryShare: Double(share.count))
        // RQ3: a «يحتاج» grade turns the *next* day into «تثبيت»; today's own session does not relabel today.
        let previous = sessions.last { $0.kind == .hifz && $0.dayKey < today }
        let consolidation = previous?.grades.contains { $0.rating == .needsMastery } == true ? previous?.ayahs : nil
        let hifz = try plan.map { try QuranDailyPlanEngine.hifz(plan: $0.plan, day: today, restDay: restDay, level: hifzLevel,
            forceNewHifz: dayState?.forceNewHifz ?? false, balanceDecides: settings.value(for: "quran.balanceDecides") == .bool(true),
            consolidation: consolidation, savedHifzToday: sessions.contains { $0.kind == .hifz && $0.dayKey == today }, previousWird: previous?.ayahs,
            need: need, allotments: allotments, coverage: coverage, catalog: catalog) }
        let mistakeSessions = sessions.map { QuranMistakeSession(id: $0.id, dayKey: $0.dayKey) }
        let mistakeEvents = try context.fetch(FetchDescriptor<MistakeEvent>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.compactMap { row -> QuranMistakeEvent? in
            guard let kind = QuranMistakeEventKind(rawValue: row.kind) else { throw DataError.invalidValue("Quran mistake") }
            return QuranMistakeEvent(key: QuranMistakeKey(ayahID: row.ayahId, wordIndex: row.wordIndex), sessionID: row.sessionID, at: row.at, kind: kind)
        }
        let seeds = try context.fetch(FetchDescriptor<MistakeSpot>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map {
            QuranMistakeSpotSeed(key: QuranMistakeKey(ayahID: $0.ayahId, wordIndex: $0.wordIndex), legacyHits: $0.legacyHits,
                legacyLastDrillAt: $0.legacyLastDrillAt, legacyStreak: $0.legacyStreak)
        }
        let drafts = try context.fetch(FetchDescriptor<SessionDraft>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.compactMap { try draft($0.id) }
        return QuranDataSnapshot(day: storedDay, plan: plan, coverage: coverage, sessions: sessions, pages: pages, memories: memories, completedOn: completedOn,
            activities: activities, hifzLevel: hifzLevel, reviewLevel: reviewLevel, restDay: restDay, forceNewHifz: dayState?.forceNewHifz ?? false,
            hifz: hifz, review: review, recentPages: recent, partialRecent: coverage.partialRecentPortions.filter { !completedToday.contains($0.page) }, allotments: allotments, recovery: recovery,
            mistakes: QuranMistakeEngine.summaries(seeds: seeds, events: mistakeEvents, sessions: mistakeSessions),
            drillBoard: QuranMistakeEngine.drillBoard(seeds: seeds, events: mistakeEvents, sessions: mistakeSessions, dayKey: today, intensity: plan?.plan.intensity ?? .balanced),
            planStartDay: planStartDay, habitualHifzLevel: QuranDayLevel(rawValue: try settings.value(for: "quran.hifzLevel").string ?? "medium") ?? .medium, drafts: drafts, lastTest: lastTest, testPages: tests)
    }
}

public extension QuranReviewRating {
    init?(storedRaw: String) {
        switch storedRaw { case "mastered": self = .mastered; case "good": self = .good; case "needs": self = .needsMastery; default: return nil }
    }
    var storedRaw: String {
        switch self { case .mastered: "mastered"; case .good: "good"; case .needsMastery: "needs" }
    }
}
