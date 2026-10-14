import Foundation
import MadarCore
import MadarQuran
import XCTest

@MainActor
final class CoachAndMistakesTests: XCTestCase {
    private func day(_ value: String) throws -> GregorianDay { try GregorianDay(value) }
    private func instant(_ day: Int, hour: Int = 12) -> Date {
        let start = try! GregorianDay("2026-01-01")
        return start.adding(days: day - 1).date(in: .gmt).addingTimeInterval(Double(hour * 3_600))
    }

    func testLearningRevealsAreHintsAndOnlyBlindSlipsAffectTheGrade() {
        var tally = HifzCoachTally()
        XCTAssertEqual(tally.recordReveal(at: .repetition), .learningHint)
        XCTAssertEqual(tally.recordReveal(at: .lineStarts), .learningHint)
        XCTAssertEqual(tally.recordReveal(at: .promptedRecall), .learningHint)
        XCTAssertEqual(tally.learningHints, 3)
        XCTAssertEqual(tally.blindSlips, 0)
        XCTAssertEqual(tally.grade(ayatCount: 10), .mastered)

        XCTAssertEqual(tally.recordReveal(at: .blindRecitation), .blindSlip)
        XCTAssertEqual(tally.grade(ayatCount: 10), .good)
        tally.recordSlip(at: .promptedRecall)
        XCTAssertEqual(tally.blindSlips, 1)
        tally.recordSlip(at: .blindRecitation)
        tally.recordSlip(at: .blindRecitation)
        XCTAssertEqual(tally.blindSlips, 3)
        XCTAssertEqual(tally.grade(ayatCount: 10), .needsMastery)
    }

    func testGradeToleranceUsesBlindSlipCountOnly() {
        XCTAssertEqual(QuranMistakeEngine.mistakeTolerance(ayatCount: 10), 2)
        XCTAssertEqual(QuranMistakeEngine.gradeFromBlindSlips(0, ayatCount: 10), .mastered)
        XCTAssertEqual(QuranMistakeEngine.gradeFromBlindSlips(2, ayatCount: 10), .good)
        XCTAssertEqual(QuranMistakeEngine.gradeFromBlindSlips(3, ayatCount: 10), .needsMastery)
        XCTAssertEqual(QuranMistakeEngine.mistakeTolerance(ayatCount: 25), 5)
        XCTAssertEqual(QuranMistakeEngine.gradeFromBlindSlips(5, ayatCount: 25), .good)
        XCTAssertEqual(QuranMistakeEngine.gradeFromBlindSlips(6, ayatCount: 25), .needsMastery)
    }

    func testWholeAyahMistakeKeepsNilWordIndex() {
        let key = QuranMistakeKey(ayahID: 282, wordIndex: nil)
        XCTAssertNil(key.wordIndex)
        XCTAssertEqual(key.ayahID, 282)
    }

    func testTwoConsecutivePassesCloseAndDeletingOneSessionReopens() throws {
        let key = QuranMistakeKey(ayahID: 100, wordIndex: 4)
        let mistakeSession = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let firstPassSession = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let secondPassSession = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let events = [
            QuranMistakeEvent(key: key, sessionID: mistakeSession, at: instant(1), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: firstPassSession, at: instant(2), kind: .drillPass),
            QuranMistakeEvent(key: key, sessionID: secondPassSession, at: instant(3), kind: .drillPass),
        ]
        let sessions = [
            QuranMistakeSession(id: mistakeSession, dayKey: try day("2026-01-01")),
            QuranMistakeSession(id: firstPassSession, dayKey: try day("2026-01-02")),
            QuranMistakeSession(id: secondPassSession, dayKey: try day("2026-01-03")),
        ]

        let closed = try XCTUnwrap(QuranMistakeEngine.summaries(seeds: [], events: events, sessions: sessions).first)
        XCTAssertEqual(closed.hits, 1)
        XCTAssertEqual(closed.successStreak, 2)
        XCTAssertFalse(closed.isOpen)
        XCTAssertEqual(closed.closedAt, instant(3))

        let afterUndo = sessions.map { session in
            QuranMistakeSession(id: session.id, dayKey: session.dayKey, isDeleted: session.id == secondPassSession)
        }
        let reopenedByUndo = try XCTUnwrap(QuranMistakeEngine.summaries(seeds: [], events: events, sessions: afterUndo).first)
        XCTAssertEqual(reopenedByUndo.hits, 1)
        XCTAssertEqual(reopenedByUndo.successStreak, 1)
        XCTAssertTrue(reopenedByUndo.isOpen)
        XCTAssertNil(reopenedByUndo.closedAt)
    }

    func testNewErrorAfterClosureMarksTheSpotAsReturnedAndDrillFailureResetsSuccesses() throws {
        let key = QuranMistakeKey(ayahID: 100, wordIndex: nil)
        let ids = (1...5).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let events = [
            QuranMistakeEvent(key: key, sessionID: ids[0], at: instant(1), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: ids[1], at: instant(2), kind: .drillPass),
            QuranMistakeEvent(key: key, sessionID: ids[2], at: instant(3), kind: .drillPass),
            QuranMistakeEvent(key: key, sessionID: ids[3], at: instant(4), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: ids[4], at: instant(5), kind: .drillPass),
            QuranMistakeEvent(key: key, sessionID: ids[4], at: instant(5, hour: 13), kind: .drillFail, inputOrder: 1),
        ]
        let sessions = try ids.enumerated().map { index, id in
            QuranMistakeSession(id: id, dayKey: try day(String(format: "2026-01-%02d", index + 1)))
        }
        let summary = try XCTUnwrap(QuranMistakeEngine.summaries(seeds: [], events: events, sessions: sessions).first)
        XCTAssertEqual(summary.hits, 2)
        XCTAssertEqual(summary.successStreak, 0)
        XCTAssertTrue(summary.isOpen)
        XCTAssertTrue(summary.returnedAfterClosure)
        XCTAssertEqual(summary.reopenedAt, instant(4))
        XCTAssertEqual(summary.lastDrillAt, instant(5, hour: 13))
    }

    func testTodayCountUsesStoredSessionDayAndIgnoresDeletedOrNonMistakeEvents() throws {
        let key = QuranMistakeKey(ayahID: 7, wordIndex: 0)
        let todayID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let yesterdayID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let events = [
            QuranMistakeEvent(key: key, sessionID: todayID, at: instant(1), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: yesterdayID, at: instant(1), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: deletedID, at: instant(1), kind: .mistake),
            QuranMistakeEvent(key: key, sessionID: todayID, at: instant(1), kind: .drillFail),
            QuranMistakeEvent(key: key, sessionID: nil, at: instant(1), kind: .mistake),
        ]
        let sessions = [
            QuranMistakeSession(id: todayID, dayKey: try day("2026-01-01")),
            QuranMistakeSession(id: yesterdayID, dayKey: try day("2025-12-31")),
            QuranMistakeSession(id: deletedID, dayKey: try day("2026-01-01"), isDeleted: true),
        ]
        XCTAssertEqual(QuranMistakeEngine.mistakesToday(events: events, sessions: sessions, dayKey: try day("2026-01-01")), 1)
    }

    func testReturnedSpotsRankFirstThenHitsAndDailyIntensityLimits() throws {
        let returnedKey = QuranMistakeKey(ayahID: 1, wordIndex: nil)
        let frequentKey = QuranMistakeKey(ayahID: 2, wordIndex: nil)
        let ordinaryKey = QuranMistakeKey(ayahID: 3, wordIndex: nil)
        var events: [QuranMistakeEvent] = []
        var sessions: [QuranMistakeSession] = []
        var idCounter = 1
        func append(_ key: QuranMistakeKey, _ kind: QuranMistakeEventKind, _ dayNumber: Int) throws {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", idCounter))!
            idCounter += 1
            events.append(QuranMistakeEvent(key: key, sessionID: id, at: instant(dayNumber), kind: kind))
            sessions.append(QuranMistakeSession(id: id, dayKey: try day(String(format: "2026-01-%02d", dayNumber))))
        }
        try append(returnedKey, .mistake, 1)
        try append(returnedKey, .drillPass, 2)
        try append(returnedKey, .drillPass, 3)
        try append(returnedKey, .mistake, 4)
        try append(frequentKey, .mistake, 1)
        try append(frequentKey, .mistake, 2)
        try append(frequentKey, .mistake, 3)
        try append(ordinaryKey, .mistake, 5)
        try append(ordinaryKey, .mistake, 6)
        let otherKeys = (4...10).map { QuranMistakeKey(ayahID: $0, wordIndex: nil) }
        for key in otherKeys { try append(key, .mistake, 6) }

        let open = QuranMistakeEngine.openSpots(seeds: [], events: events, sessions: sessions)
        XCTAssertEqual(Array(open.prefix(3).map(\.key)), [returnedKey, frequentKey, ordinaryKey])
        XCTAssertTrue(open[0].returnedAfterClosure)
        XCTAssertEqual(open[1].hits, 3)

        XCTAssertEqual(QuranMistakeEngine.drillsForToday(openSpots: open, alreadyDrilledToday: [], intensity: .light).count, 3)
        XCTAssertEqual(QuranMistakeEngine.drillsForToday(openSpots: open, alreadyDrilledToday: [], intensity: .balanced).count, 5)
        XCTAssertEqual(QuranMistakeEngine.drillsForToday(openSpots: open, alreadyDrilledToday: [], intensity: .intense).count, 8)
        XCTAssertEqual(QuranReviewIntensity.light.preset.drillsPerDay, 3)
        XCTAssertEqual(QuranReviewIntensity.balanced.preset.drillsPerDay, 5)
        XCTAssertEqual(QuranReviewIntensity.intense.preset.drillsPerDay, 8)
        XCTAssertEqual(QuranMistakeEngine.drillsForToday(openSpots: open, alreadyDrilledToday: [returnedKey, frequentKey], intensity: .balanced).count, 3)
    }

    // §7.4: today's mistakes = mistake events of today's sessions; drills 3/5/8 by intensity;
    // order: returned-after-closure first, then most hits, then most recent; a spot drilled today is not offered again.
    func testDrillBoardSharesTheDailyAllowanceAndSplitsTodayFromMine() throws {
        let today = try day("2026-01-10"), yesterday = try day("2026-01-09")
        let old = UUID(), todayHifz = UUID(), todayDrill = UUID()
        let sessions = [QuranMistakeSession(id: old, dayKey: yesterday), QuranMistakeSession(id: todayHifz, dayKey: today), QuranMistakeSession(id: todayDrill, dayKey: today)]
        let a = QuranMistakeKey(ayahID: 10, wordIndex: 2), b = QuranMistakeKey(ayahID: 20, wordIndex: nil)
        let c = QuranMistakeKey(ayahID: 30, wordIndex: 1), d = QuranMistakeKey(ayahID: 40, wordIndex: 0), e = QuranMistakeKey(ayahID: 50, wordIndex: 3)
        var events: [QuranMistakeEvent] = []
        // a: three old hits; b: one old hit and one today; c: one today; d: one old hit, drilled today; e: closed then returned.
        for hour in 1...3 { events.append(QuranMistakeEvent(key: a, sessionID: old, at: instant(9, hour: hour), kind: .mistake)) }
        events.append(QuranMistakeEvent(key: b, sessionID: old, at: instant(9, hour: 4), kind: .mistake))
        events.append(QuranMistakeEvent(key: b, sessionID: todayHifz, at: instant(10, hour: 1), kind: .mistake))
        events.append(QuranMistakeEvent(key: c, sessionID: todayHifz, at: instant(10, hour: 2), kind: .mistake))
        events.append(QuranMistakeEvent(key: d, sessionID: old, at: instant(9, hour: 5), kind: .mistake))
        events.append(QuranMistakeEvent(key: d, sessionID: todayDrill, at: instant(10, hour: 3), kind: .drillPass))
        events.append(QuranMistakeEvent(key: e, sessionID: old, at: instant(8, hour: 1), kind: .mistake))
        events.append(QuranMistakeEvent(key: e, sessionID: old, at: instant(8, hour: 2), kind: .drillPass))
        events.append(QuranMistakeEvent(key: e, sessionID: old, at: instant(8, hour: 3), kind: .drillPass))
        events.append(QuranMistakeEvent(key: e, sessionID: old, at: instant(9, hour: 6), kind: .mistake))

        let light = QuranMistakeEngine.drillBoard(seeds: [], events: events, sessions: sessions, dayKey: today, intensity: .light)
        XCTAssertEqual(light.todayMistakes, 2)          // b and c, from today's hifz session
        XCTAssertEqual(light.openCount, 5)
        XCTAssertEqual(light.drilledToday, 1)           // d
        XCTAssertEqual(light.dailyAllowance, 3)
        // 3 − 1 drilled = 2 left: e (returned) first, then a (3 hits); d is not offered again today.
        XCTAssertEqual(light.mineQueue.map(\.key), [e, a])
        // Today's tab: b (2 hits) before c (1 hit), within the same allowance.
        XCTAssertEqual(light.todayQueue.map(\.key), [b, c])

        let intense = QuranMistakeEngine.drillBoard(seeds: [], events: events, sessions: sessions, dayKey: today, intensity: .intense)
        XCTAssertEqual(intense.dailyAllowance, 8)
        XCTAssertEqual(intense.mineQueue.map(\.key), [e, a, b, c])
    }
}
