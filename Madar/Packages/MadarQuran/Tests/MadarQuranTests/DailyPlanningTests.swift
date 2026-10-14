import XCTest
import MadarCore
@testable import MadarQuran

final class DailyPlanningTests: XCTestCase {
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key) }
    private func page(_ n: Int, last: String = "2026-10-10", due: String = "2026-10-17",
                      grade: QuranReviewRating = .mastered, today: String = "2026-10-17") throws -> QuranPlanningPage {
        try QuranPlanningPage(page: n, lastReviewed: day(last), nextDue: day(due), grade: grade, today: day(today))
    }
    private func coverage() throws -> QuranCoverage {
        try QuranCoverageEngine.summarize(sessions: [], pages: [])
    }

    // Independent expectations from Q05's worked Thu–Tue example and the official page endpoints.
    func testWorkedWeekLevelsRestSpreadAndConsolidation() throws {
        let catalog = try QuranResourceCatalog.bundled()
        let plan = try QuranPlan(id: UUID(), startAyah: 2057)
        let empty = try coverage(), quiet = QuranReviewNeed(steadyNeed: 10, todayNeed: 10)
        func hifz(_ key: String, level: QuranDayLevel = .medium, extras: [QuranDailyAllotment] = [],
                  consolidate: QuranAyahRange? = nil) throws -> QuranDailyHifz {
            try QuranDailyPlanEngine.hifz(plan: plan, day: day(key), level: level,
                consolidation: consolidate, need: quiet, allotments: extras, coverage: empty, catalog: catalog)
        }
        let thursday = try hifz("2026-10-15", level: .deep)
        XCTAssertEqual(thursday.amount, 1.5); XCTAssertEqual(thursday.portion?.last, 2073)
        XCTAssertEqual(try hifz("2026-10-16").balance, .rest)
        XCTAssertEqual(try hifz("2026-10-16").amount, 0)
        let extra = try QuranDailyPlanEngine.missedDayAllotments(originDay: day("2026-10-17"),
            resolvingOn: day("2026-10-18"), choice: .spread, missedAmount: 1, restDay: .friday)
        XCTAssertEqual(extra.map(\.dayKey.description), ["2026-10-18", "2026-10-19", "2026-10-20"])
        XCTAssertEqual(try hifz("2026-10-18", extras: extra).amount, 4.0 / 3, accuracy: 1e-10)
        let previous = try QuranAyahRange(first: 2057, last: 2067)
        let monday = try hifz("2026-10-19", extras: extra, consolidate: previous)
        XCTAssertEqual(monday.amount, 0); XCTAssertEqual(monday.portion, previous)
        XCTAssertEqual(try hifz("2026-10-20", extras: extra).amount, 4.0 / 3, accuracy: 1e-10)
        XCTAssertEqual(try hifz("2026-10-21", extras: extra).amount, 1, "Monday's target is not a debt")
    }

    func testAllLevelsAndRestOverrideAndHalfAfterExtras() throws {
        XCTAssertEqual(QuranDayLevel.allCases.map(\.hifzFactor), [0.5, 1, 1.5, 2])
        XCTAssertEqual(QuranDayLevel.allCases.map(\.reviewMinimum), [4, 8, 12, 22])
        let c = try QuranResourceCatalog.bundled(), p = try QuranPlan(id: UUID())
        let d = try day("2026-10-16"), empty = try coverage()
        let extra = try QuranDailyAllotment(dayKey: d, kind: .hifzExtra, amount: 1, origin: .missPolicy, originDayKey: d.adding(days: -1))
        let need = QuranReviewNeed(steadyNeed: 1, todayNeed: 3)
        let forced = try QuranDailyPlanEngine.hifz(plan: p, day: d, forceNewHifz: true,
            consolidation: QuranAyahRange(first: 1, last: 7), need: need, allotments: [extra], coverage: empty, catalog: c)
        XCTAssertEqual(forced.amount, 2); XCTAssertEqual(forced.balance, .full)
        let half = try QuranDailyPlanEngine.hifz(plan: p, day: d, restDay: .none, need: need,
            allotments: [extra, extra], coverage: empty, catalog: c)
        XCTAssertEqual(half.amount, 1); XCTAssertEqual(half.balance, .half)
        let saved = try QuranDailyPlanEngine.hifz(plan: p, day: d, restDay: .none, savedHifzToday: true,
            need: need, coverage: empty, catalog: c)
        XCTAssertEqual(saved.balance, .full)
    }

    func testAllotmentSkipsRestDayAndSurvivesSerializationWithoutDuplication() throws {
        let values = try QuranDailyPlanEngine.missedDayAllotments(originDay: day("2026-10-14"),
            resolvingOn: day("2026-10-15"), choice: .spread, missedAmount: 1, restDay: .friday)
        XCTAssertEqual(values.map(\.dayKey.description), ["2026-10-15", "2026-10-17", "2026-10-18"])
        let restored = try JSONDecoder().decode([QuranDailyAllotment].self, from: JSONEncoder().encode(values))
        XCTAssertEqual(restored, values)
        XCTAssertEqual(QuranDailyPlanEngine.uniqueAllotments(values + restored).count, 3)
        let double = try QuranDailyPlanEngine.missedDayAllotments(originDay: day("2026-10-15"),
            resolvingOn: day("2026-10-16"), choice: .double, missedAmount: 1, restDay: .friday)
        XCTAssertEqual(double.first?.dayKey.description, "2026-10-17"); XCTAssertEqual(double.first?.amount, 1)
        for choice in [QuranMissedDayChoice.skip, .postpone] {
            XCTAssertTrue(try QuranDailyPlanEngine.missedDayAllotments(originDay: day("2026-10-15"),
                resolvingOn: day("2026-10-16"), choice: choice, missedAmount: 1, restDay: .friday).isEmpty)
        }
    }

    func testGapPortionStopsBeforeLaterSavedFactsAndBridgeUsesOnlyMemorizedAyahs() throws {
        let c = try QuranResourceCatalog.bundled(), p = try QuranPlan(id: UUID(), unit: .ayah, amount: 100)
        let sessions = [QuranCoverageSession(id: "a", kind: .hifz, ayahs: try QuranAyahRange(first: 1, last: 50), endedAt: Date()),
                        QuranCoverageSession(id: "c", kind: .hifz, ayahs: try QuranAyahRange(first: 101, last: 150), endedAt: Date())]
        let coverage = try QuranCoverageEngine.summarize(sessions: sessions, catalog: c)
        let result = try QuranDailyPlanEngine.hifz(plan: p, day: day("2026-10-15"),
            need: QuranReviewNeed(steadyNeed: 10, todayNeed: 10), coverage: coverage, catalog: c)
        XCTAssertEqual(result.portion, try QuranAyahRange(first: 51, last: 100))
        XCTAssertEqual(result.bridge, try QuranAyahRange(first: 48, last: 50))
    }

    func testReviewServesAllDueAboveMinimumAndOrdersWeakestAfterRecentWithTestLast() throws {
        let pages = try (1...30).map { try page($0, grade: $0 == 9 ? .needsMastery : .mastered) }
        let result = QuranDailyPlanEngine.review(pages: pages, recent: [2, 1], level: .simple,
            recovery: [5], raised: [6, 5], test: [30], completedToday: [4])
        XCTAssertEqual(Array(result.regularPages.prefix(3)), [1, 2, 5], "The merged 5...29 run contains weakest face 9")
        XCTAssertEqual(result.allPages.count, 29, "All due pages survive the four-page minimum")
        XCTAssertEqual(result.testPages, [30]); XCTAssertEqual(result.allPages.last, 30)
        XCTAssertEqual(Set(result.allPages).count, result.allPages.count)
        XCTAssertFalse(result.allPages.contains(4))
    }

    func testReviewMinimumFillExtrasAndRunsDoNotMergeTestIntoRegular() throws {
        let pages = try (1...12).map { try page($0, due: "2026-10-30") }
        let result = QuranDailyPlanEngine.review(pages: pages, recent: [1, 2], level: .simple,
            recovery: [8], raised: [9], test: [10])
        XCTAssertEqual(result.regularPages, [1, 2, 3, 4, 8, 9])
        XCTAssertEqual(result.runs, [try QuranPageRange(first: 1, last: 4),
                                    try QuranPageRange(first: 8, last: 9), try QuranPageRange(first: 10, last: 10)])
    }

    func testStrengthGoldenValuesAndSingleFarDefinition() throws {
        XCTAssertEqual(try page(1, today: "2026-10-10").strength, 100)
        XCTAssertEqual(try page(1).strength, 71)
        XCTAssertEqual(try page(1, grade: .good).strength, 60)
        XCTAssertEqual(try page(1, grade: .needsMastery).strength, 42)
        XCTAssertEqual(try page(1, grade: .good, today: "2026-10-24").strength, 43)
        XCTAssertFalse(try page(1, last: "2026-08-01", due: "2026-10-24").isFar,
                       "A healthy long interval is not far merely because it is older than 30 days")
        XCTAssertTrue(try page(1, today: "2026-10-24").isFar, "Overdue by a full interval")
        XCTAssertTrue(try page(1, grade: .needsMastery).isFar)
        XCTAssertNil(QuranProgressEngine.meanStrength([]))
        XCTAssertEqual(try QuranProgressEngine.meanStrength([page(604)]), 71)
    }

    func testRecoveryCeilingRemainingDaysAndUndoReopensTarget() throws {
        let plan = try QuranRecoveryPlan(startDayKey: day("2026-10-10"), days: 5, pages: Array(1...11))
        XCTAssertEqual(plan.share(on: try day("2026-10-10"), reviewedOn: [:]), [1, 2, 3])
        XCTAssertEqual(plan.share(on: try day("2026-10-11"), reviewedOn: [1: try day("2026-10-10"), 2: try day("2026-10-10"), 3: try day("2026-10-10")]), [4, 5])
        XCTAssertEqual(plan.share(on: try day("2026-10-15"), reviewedOn: [:]), Array(1...11))
        XCTAssertTrue(plan.share(on: try day("2026-10-09"), reviewedOn: [:]).isEmpty)
        let done = try Dictionary(uniqueKeysWithValues: (1...11).map { ($0, try day("2026-10-10")) })
        XCTAssertTrue(plan.share(on: try day("2026-10-11"), reviewedOn: done).isEmpty)
        XCTAssertEqual(plan.share(on: try day("2026-10-11"), reviewedOn: done.filter { $0.key != 2 }), [2])
        XCTAssertThrowsError(try QuranRecoveryPlan(startDayKey: day("2026-10-10"), days: 6, pages: [1]))
    }

    func testRecoverySelectionAndRaiseOnlyUseFarPages() throws {
        let pages = try (1...7).map { try page($0, last: "2026-10-01", due: "2026-10-08", today: "2026-10-17") }
        let healthy = try page(8, last: "2026-10-16", due: "2026-12-01")
        let recovery = try QuranRecoveryPlan.starting(on: day("2026-10-17"), days: 7, candidates: pages + [healthy])
        XCTAssertEqual(recovery.pages, Array(1...7))
        let raise = try QuranRecoveryEngine.raise(on: day("2026-10-17"), pages: pages + [healthy])
        XCTAssertEqual(raise.pages, [1, 2, 3, 4, 5]); XCTAssertEqual(raise.dayKey.description, "2026-10-18")
    }

    func testPeriodicTestFrozenSelectionAndCompletionAcrossRestart() throws {
        let d = try day("2026-10-17"), pages = try (1...5).map { try page($0) }
        XCTAssertEqual(QuranRecoveryEngine.testPages(on: d, lastTest: d.adding(days: -3), frozen: [4], pages: pages, recent: []), [4])
        XCTAssertEqual(QuranRecoveryEngine.testPages(on: d, lastTest: d, frozen: [4], pages: pages, recent: []), [])
        XCTAssertEqual(QuranRecoveryEngine.testPages(on: d, lastTest: d.adding(days: -2), frozen: nil, pages: pages, recent: []), [])
        XCTAssertEqual(QuranRecoveryEngine.testPages(on: d, lastTest: nil, frozen: nil, pages: pages, recent: [1, 2]), [3])
    }

    func testStudyStreakRestDoesNotCountGraceDoesNotCountAndTwoMissesBreak() throws {
        func activity(_ key: String, kind: QuranSessionKind = .hifz, deleted: Bool = false) throws -> QuranActivityDay {
            QuranActivityDay(dayKey: try day(key), kind: kind, gradedPages: [1], hifzAyahs: [1], isDeleted: deleted)
        }
        let facts = try [activity("2026-10-15"), activity("2026-10-16", kind: .review), activity("2026-10-18")]
        XCTAssertEqual(QuranProgressEngine.streak(activities: facts, through: try day("2026-10-18")), QuranStudyStreak(days: 2, inGrace: false))
        XCTAssertEqual(QuranProgressEngine.streak(activities: facts, through: try day("2026-10-20")), QuranStudyStreak(days: 2, inGrace: true))
        XCTAssertEqual(QuranProgressEngine.streak(activities: facts, through: try day("2026-10-21")).days, 0)
        XCTAssertEqual(QuranProgressEngine.streak(activities: try [activity("2026-10-18", kind: .drill), activity("2026-10-19", deleted: true)], through: try day("2026-10-20")).days, 0)
        XCTAssertFalse(QuranActivityDay(dayKey: try day("2026-10-18"), kind: .free).countsForStreak)
        XCTAssertTrue(try activity("2026-10-18", kind: .qiyam).countsForReviewHabit)
        XCTAssertFalse(try activity("2026-10-18").countsForReviewHabit)
    }

    func testPaceUses28DaysIncludingMissedDaysAndMinimumFiveDaysFiftyAyahs() throws {
        let today = try day("2026-10-28")
        let activities = try (1...5).map { i in QuranActivityDay(dayKey: try day(String(format: "2026-10-%02d", i)), kind: .hifz, hifzAyahs: Set((i * 10 - 9)...(i * 10))) }
        let completed = try Dictionary(uniqueKeysWithValues: (1...24).map { ($0, try day("2026-10-10")) })
        let result = QuranProgressEngine.pace(activities: activities, completedOn: completed, through: today)
        XCTAssertEqual(result.windowStart.description, "2026-10-01")
        XCTAssertEqual(result.hifzDays, 24); XCTAssertEqual(result.pagesPerHifzDay, 1)
        XCTAssertNil(QuranProgressEngine.pace(activities: Array(activities.prefix(4)), completedOn: completed, through: today).pagesPerHifzDay)
        XCTAssertEqual(QuranProgressEngine.pace(activities: activities, completedOn: completed, through: try day("2026-11-01")).windowStart.description, "2026-10-05")
    }

    func testForecastWalksCalendarRestAndAllotmentsAndCompleteState() throws {
        let start = try day("2026-10-10")
        XCTAssertEqual(QuranProgressEngine.forecast(remainingPages: 320, dailyPages: 1, startingOn: start, restDay: .friday), .estimated(try day("2027-10-17")))
        XCTAssertEqual(QuranProgressEngine.forecast(remainingPages: 320, dailyPages: 1, startingOn: start, restDay: .none), .estimated(try day("2027-08-25")))
        XCTAssertEqual(QuranProgressEngine.forecast(remainingPages: 0, dailyPages: 1, startingOn: start, restDay: .friday), .complete)
        XCTAssertEqual(QuranProgressEngine.forecast(remainingPages: 1, dailyPages: 0, startingOn: start, restDay: .none), .unavailable)
    }

    func testEightRakatsWithThreeSavedPagesRecordsEachOnce() throws {
        let pages = try [page(1, due: "2026-10-30"), page(2, due: "2026-10-16"), page(3, due: "2026-10-20")]
        let result = try QuranQiyamEngine.assignment(rakats: 8, pages: pages + pages)
        XCTAssertEqual(result.pageByRakah, [2, 3, 1, nil, nil, nil, nil, nil])
        XCTAssertEqual(result.pagesToRecord, [2, 3, 1])
        XCTAssertTrue(try QuranQiyamEngine.assignment(rakats: 8, pages: []).pageByRakah.isEmpty)
        XCTAssertThrowsError(try QuranQiyamEngine.assignment(rakats: 3, pages: pages))
    }
}

final class QuranDailyCompletionTests: XCTestCase {
    func testCompletingTheMinimumDoesNotGenerateAnotherWirdAndRecoveryShareDoesNotRefill() throws {
        let today = try GregorianDay("2026-10-15")
        let pages = try (1...30).map { try QuranPlanningPage(page: $0, lastReviewed: today, nextDue: today.adding(days: 7), today: today) }
        let review = QuranDailyPlanEngine.review(pages: pages, recent: [1, 2, 3], level: .medium, completedToday: Set(1...8))
        XCTAssertTrue(review.allPages.isEmpty)
        let recovery = try QuranRecoveryPlan(startDayKey: today, days: 5, pages: Array(1...11))
        XCTAssertEqual(recovery.share(on: today, reviewedOn: [:]), [1, 2, 3])
        XCTAssertTrue(recovery.share(on: today, reviewedOn: [1: today, 2: today, 3: today]).isEmpty)
        XCTAssertEqual(recovery.share(on: today, reviewedOn: [1: today]), [2, 3])
    }

    // §7.4 smart test: random among the top max(1, ceil(n/3)) by dormancy; the pick is stable within a day.
    func testDayTestPickIsRandomWithinTheTopThirdAndStableForTheDay() throws {
        let start = try GregorianDay("2026-10-01")
        let pages = try (1...9).map { try QuranPlanningPage(page: $0, lastReviewed: start.adding(days: -$0), nextDue: start, grade: .good, today: start) }
        var picks = Set<Int>()
        for offset in 0..<30 {
            let day = start.adding(days: offset)
            let index = QuranRecoveryEngine.daySelectionIndex(day)
            XCTAssertEqual(index, QuranRecoveryEngine.daySelectionIndex(day))
            let pick = QuranRecoveryEngine.testPages(on: day, lastTest: nil, frozen: nil, pages: pages, recent: [], selectionIndex: index)
            XCTAssertEqual(pick.count, 1)
            XCTAssertTrue([9, 8, 7].contains(pick[0]), "top third by dormancy: \(pick)")
            picks.formUnion(pick)
        }
        XCTAssertGreaterThan(picks.count, 1, "never random")
    }
}
