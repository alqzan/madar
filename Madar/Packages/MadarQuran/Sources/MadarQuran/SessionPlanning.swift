import Foundation
import MadarCore

public struct QuranDraftGrade: Codable, Equatable, Sendable {
    public let page: Int
    public let rating: QuranReviewRating
    public let isTest: Bool
    public init(page: Int, rating: QuranReviewRating, isTest: Bool = false) {
        self.page = page; self.rating = rating; self.isTest = isTest
    }
}
public struct QuranDraftMistake: Codable, Equatable, Sendable {
    public let key: QuranMistakeKey
    public let at: Date
    public let kind: QuranMistakeEventKind
    public init(key: QuranMistakeKey, at: Date, kind: QuranMistakeEventKind) {
        self.key = key; self.at = at; self.kind = kind
    }
}

/// Serializable device-local state. Learning hints never enter `mistakes`.
public struct QuranSessionDraft: Codable, Sendable {
    public let id: UUID
    public let planID: UUID?
    public let kind: QuranSessionKind
    public let storedDay: StoredDayKey
    public let startedAt: Date
    public let portions: [QuranAyahRange]
    public var page: Int
    public var ayahID: Int
    public var coachStage: HifzCoachStage
    public var blindPassedAyahs: Set<Int>
    public var grades: [QuranDraftGrade]
    public var mistakes: [QuranDraftMistake]

    public init(id: UUID = UUID(), planID: UUID?, kind: QuranSessionKind,
                storedDay: StoredDayKey, startedAt: Date, portions: [QuranAyahRange], page: Int, ayahID: Int) {
        self.id = id; self.planID = planID; self.kind = kind; self.storedDay = storedDay
        self.startedAt = startedAt; self.portions = portions; self.page = page; self.ayahID = ayahID
        coachStage = .repetition; blindPassedAyahs = []; grades = []; mistakes = []
    }
}

/// The app adapter persists this whole batch in one save, rebuilds projections, then removes the draft.
/// This engine owns eligibility; it does not open a store or claim a database transaction.
public struct QuranSessionCommit: Sendable {
    public let commitID: UUID
    public let planID: UUID?
    public let kind: QuranSessionKind
    public let storedDay: StoredDayKey
    public let endedAt: Date
    public let ayahs: QuranAyahRange
    public let pages: [Int]
    public let grades: [QuranDraftGrade]
    public let mistakes: [QuranDraftMistake]
}
public enum QuranSessionEngine {
    /// Already committed ids include tombstones: retry can never revive an undone session.
    /// Discarding writes nothing; an unfinished draft commits only blind-passed hifz or graded review.
    public static func prepareCommit(
        draft: QuranSessionDraft, endedAt: Date, alreadyCommitted: Set<UUID>,
        coverage: QuranCoverage, catalog: QuranResourceCatalog
    ) throws -> QuranSessionCommit? {
        if alreadyCommitted.contains(draft.id) { return nil }
        guard !draft.portions.isEmpty, endedAt.timeIntervalSince1970.isFinite,
              draft.startedAt.timeIntervalSince1970.isFinite, endedAt >= draft.startedAt,
              (1...604).contains(draft.page), (1...6236).contains(draft.ayahID),
              TimeZone(identifier: draft.storedDay.timeZoneID) != nil else {
            throw QuranPlanError.invalidSession
        }
        let plannedAyahs = Set(draft.portions.flatMap { Array($0.first...$0.last) })
        guard draft.blindPassedAyahs.isSubset(of: plannedAyahs), plannedAyahs.contains(draft.ayahID) else {
            throw QuranPlanError.invalidSession
        }
        let plannedPages = Set(try draft.portions.flatMap { try QuranPortionEngine.pages(for: $0, catalog: catalog).map(\.page) })
        guard plannedPages.contains(draft.page), draft.grades.allSatisfy({ plannedPages.contains($0.page) }) else {
            throw QuranPlanError.invalidSession
        }
        for event in draft.mistakes {
            guard plannedAyahs.contains(event.key.ayahID), event.at >= draft.startedAt, event.at <= endedAt,
                  event.at.timeIntervalSince1970.isFinite, let ayah = catalog.ayah(id: event.key.ayahID) else {
                throw QuranPlanError.invalidSession
            }
            if let index = event.key.wordIndex, !(0..<ayah.wordTokens.count).contains(index) {
                throw QuranPlanError.invalidSession
            }
        }
        var gradesByPage: [Int: QuranDraftGrade] = [:]
        for grade in draft.grades { gradesByPage[grade.page] = grade }
        var grades = gradesByPage.values.sorted { $0.page < $1.page }
        var committedAyahs = Set<Int>()
        switch draft.kind {
        case .hifz:
            // One stored range: accept the consecutive passed prefix, never bridge an unpassed ayah.
            guard let first = plannedAyahs.min(), draft.blindPassedAyahs.contains(first) else { return nil }
            var last = first
            while last < 6236 && plannedAyahs.contains(last + 1) && draft.blindPassedAyahs.contains(last + 1) { last += 1 }
            committedAyahs = Set(first...last)
            let committedPages = Set(try QuranPortionEngine.pages(for: QuranAyahRange(first: first, last: last), catalog: catalog).map(\.page))
            grades.removeAll { !committedPages.contains($0.page) }
        case .review, .free, .qiyam:
            if draft.kind == .free || draft.kind == .qiyam {
                grades.removeAll { !coverage.completedPages.contains($0.page) }
            } else {
                // RQ5: recent review may cover memorized ayahs on an incomplete face.
                grades.removeAll { grade in
                    !catalog.ayahs(on: grade.page).contains {
                        plannedAyahs.contains($0.id) && coverage.coveredAyahs.contains($0.id)
                    }
                }
            }
            guard !grades.isEmpty else { return nil }
            for grade in grades {
                let ayahs = catalog.ayahs(on: grade.page).map(\.id)
                committedAyahs.formUnion(ayahs.filter { plannedAyahs.contains($0) && coverage.coveredAyahs.contains($0) })
            }
        case .drill:
            guard !draft.mistakes.isEmpty else { return nil }
            grades = []
            committedAyahs = Set(draft.mistakes.map(\.key.ayahID))
        }
        guard let first = committedAyahs.min(), let last = committedAyahs.max() else { return nil }
        let mistakes = draft.mistakes.filter { committedAyahs.contains($0.key.ayahID) }
        let pages = draft.kind == .hifz || draft.kind == .drill
            ? try QuranPortionEngine.pages(for: QuranAyahRange(first: first, last: last), catalog: catalog).map(\.page)
            : grades.map(\.page)
        return QuranSessionCommit(commitID: draft.id, planID: draft.planID, kind: draft.kind,
            storedDay: draft.storedDay, endedAt: endedAt, ayahs: try QuranAyahRange(first: first, last: last),
            pages: pages, grades: grades, mistakes: mistakes)
    }
}
