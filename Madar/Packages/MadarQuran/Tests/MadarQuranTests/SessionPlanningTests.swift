import XCTest
import MadarCore
@testable import MadarQuran

final class SessionPlanningTests: XCTestCase {
    private func date(_ key: String) -> Date { ISO8601DateFormatter().date(from: key)! }
    private func storedDay() throws -> StoredDayKey {
        try MadarDay.resolve(instant: date("2026-10-15T10:00:00Z"), place: .riyadh, boundary: .midnight, prayerDays: [])
    }
    private func draft(_ kind: QuranSessionKind = .hifz) throws -> QuranSessionDraft {
        QuranSessionDraft(planID: UUID(), kind: kind, storedDay: try storedDay(),
            startedAt: date("2026-10-15T10:00:00Z"), portions: [try QuranAyahRange(first: 1, last: 7)], page: 1, ayahID: 1)
    }
    private func coverage(_ saved: Bool = false) throws -> QuranCoverage {
        let facts = saved ? [QuranCoverageSession(id: "saved", kind: .hifz,
            ayahs: try QuranAyahRange(first: 1, last: 7), endedAt: date("2026-10-14T10:00:00Z"))] : []
        return try QuranCoverageEngine.summarize(sessions: facts, catalog: QuranResourceCatalog.bundled())
    }
    private func commit(_ draft: QuranSessionDraft, saved: Bool = false, ids: Set<UUID> = []) throws -> QuranSessionCommit? {
        try QuranSessionEngine.prepareCommit(draft: draft, endedAt: date("2026-10-15T11:00:00Z"),
            alreadyCommitted: ids, coverage: coverage(saved), catalog: QuranResourceCatalog.bundled())
    }

    func testResumeKeepsPositionStageTemporaryFactsAndOriginalDay() throws {
        var value = try draft()
        value.ayahID = 3; value.coachStage = .blindRecitation; value.blindPassedAyahs = [1, 2]
        value.grades = [QuranDraftGrade(page: 1, rating: .good)]
        value.mistakes = [QuranDraftMistake(key: QuranMistakeKey(ayahID: 2, wordIndex: nil), at: date("2026-10-15T10:30:00Z"), kind: .mistake)]
        let reopened = try JSONDecoder().decode(QuranSessionDraft.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(reopened.id, value.id); XCTAssertEqual(reopened.storedDay, value.storedDay)
        XCTAssertEqual(reopened.ayahID, 3); XCTAssertEqual(reopened.coachStage, .blindRecitation)
        XCTAssertEqual(reopened.blindPassedAyahs, [1, 2]); XCTAssertEqual(reopened.grades, value.grades)
        XCTAssertEqual(reopened.mistakes, value.mistakes)
    }

    func testPartialCommitOnlyIncludesConsecutiveBlindPassedAyahsAndTheirMistakes() throws {
        var value = try draft()
        value.blindPassedAyahs = [1, 2, 4, 5]
        value.grades = [QuranDraftGrade(page: 1, rating: .good)]
        value.mistakes = [1, 4].map { QuranDraftMistake(key: QuranMistakeKey(ayahID: $0, wordIndex: nil),
            at: date("2026-10-15T10:30:00Z"), kind: .mistake) }
        let result = try XCTUnwrap(commit(value))
        XCTAssertEqual(result.ayahs, try QuranAyahRange(first: 1, last: 2))
        XCTAssertEqual(result.mistakes.map(\.key.ayahID), [1])
        XCTAssertEqual(result.commitID, value.id); XCTAssertEqual(result.storedDay, value.storedDay)
        XCTAssertNil(try commit(value, ids: [value.id]), "Retry, including an undone commit, cannot write or revive facts")
    }

    func testFreeOutsideCoverageIsReadOnlyAndDrillDoesNotWriteGrades() throws {
        var free = try draft(.free); free.grades = [QuranDraftGrade(page: 1, rating: .mastered)]
        XCTAssertNil(try commit(free))
        let recorded = try XCTUnwrap(commit(free, saved: true))
        XCTAssertEqual(recorded.grades.count, 1)
        var drill = try draft(.drill); drill.grades = free.grades
        drill.mistakes = [QuranDraftMistake(key: QuranMistakeKey(ayahID: 1, wordIndex: nil),
            at: date("2026-10-15T10:30:00Z"), kind: .drillPass)]
        XCTAssertTrue(try XCTUnwrap(commit(drill)).grades.isEmpty)
        XCTAssertNil(try commit(draft()), "Learning steps without blind passed ayahs create no hifz")
    }

    func testLastPageRatingWinsAndInvalidWordOrOutOfSessionFactsAreRejected() throws {
        var value = try draft(.review)
        value.grades = [QuranDraftGrade(page: 1, rating: .good), QuranDraftGrade(page: 1, rating: .needsMastery, isTest: true)]
        let result = try XCTUnwrap(commit(value, saved: true))
        XCTAssertEqual(result.grades, [QuranDraftGrade(page: 1, rating: .needsMastery, isTest: true)])
        value.mistakes = [QuranDraftMistake(key: QuranMistakeKey(ayahID: 1, wordIndex: 999), at: date("2026-10-15T10:30:00Z"), kind: .mistake)]
        XCTAssertThrowsError(try commit(value, saved: true))
        value.mistakes = []; value.grades = [QuranDraftGrade(page: 604, rating: .good)]
        XCTAssertThrowsError(try commit(value, saved: true))
    }

    func testPartialRecentReviewRecordsOnlyMemorizedAyahsWithoutCompletingFace() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let saved = QuranCoverageSession(id: "partial", kind: .hifz,
            ayahs: try QuranAyahRange(first: 149, last: 150), endedAt: date("2026-10-14T10:00:00Z"))
        let coverage = try QuranCoverageEngine.summarize(sessions: [saved], catalog: catalog)
        var value = QuranSessionDraft(planID: UUID(), kind: .review, storedDay: try storedDay(),
            startedAt: date("2026-10-15T10:00:00Z"), portions: [try QuranAyahRange(first: 149, last: 152)], page: 22, ayahID: 149)
        value.grades = [QuranDraftGrade(page: 22, rating: .good)]
        let result = try XCTUnwrap(QuranSessionEngine.prepareCommit(draft: value, endedAt: date("2026-10-15T11:00:00Z"),
            alreadyCommitted: [], coverage: coverage, catalog: catalog))
        XCTAssertEqual(result.ayahs, try QuranAyahRange(first: 149, last: 150))
        XCTAssertEqual(result.pages, [22]); XCTAssertFalse(coverage.completedPages.contains(22))
    }

    func testMadarDayBeforeAndAtFajrStoredDraftNeverMovesOnBoundaryChange() throws {
        let civil = try GregorianDay("2026-10-15"), fajr = date("2026-10-15T02:00:00Z"), maghrib = date("2026-10-15T15:00:00Z")
        let prayers = [PrayerDay(day: civil, place: .riyadh, fajr: fajr, sunrise: fajr,
            dhuhr: maghrib, asr: maghrib, maghrib: maghrib, isha: maghrib)]
        let before = try MadarDay.resolve(instant: fajr.addingTimeInterval(-1), place: .riyadh, prayerDays: prayers)
        let after = try MadarDay.resolve(instant: fajr, place: .riyadh, prayerDays: prayers)
        XCTAssertEqual(before.dayKey, "2026-10-14"); XCTAssertEqual(after.dayKey, "2026-10-15")
        var value = QuranSessionDraft(planID: UUID(), kind: .hifz, storedDay: before, startedAt: fajr.addingTimeInterval(-1),
            portions: [try QuranAyahRange(first: 1, last: 7)], page: 1, ayahID: 1)
        value.blindPassedAyahs = [1, 2]
        let reopened = try JSONDecoder().decode(QuranSessionDraft.self, from: JSONEncoder().encode(value))
        let changed = try MadarDay.resolve(instant: fajr, place: .riyadh, boundary: .midnight, prayerDays: [])
        XCTAssertEqual(changed.dayKey, "2026-10-15")
        let result = try XCTUnwrap(commit(reopened))
        XCTAssertEqual(result.storedDay.dayKey, "2026-10-14")
        XCTAssertEqual(result.storedDay.boundary, .fajr)
    }
}
