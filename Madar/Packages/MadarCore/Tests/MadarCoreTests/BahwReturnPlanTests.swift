import Foundation
import Testing
@testable import MadarCore

@Test func firstVisitAndShortGapsDoNotCreateReturnPlan() throws {
    let day = try GregorianDay(year: 2026, month: 10, day: 26)
    let first = BahwReturnPlanEngine.recordVisit(on: day, state: nil)
    #expect(first.lastVisitedDay == day)
    #expect(first.plan == nil)

    let sameDay = BahwReturnPlanEngine.recordVisit(on: day, state: first)
    #expect(sameDay.plan == nil)

    let nextDay = BahwReturnPlanEngine.recordVisit(on: day.adding(days: 1), state: sameDay)
    let twoDaysLater = BahwReturnPlanEngine.recordVisit(on: day.adding(days: 2), state: nextDay)
    #expect(twoDaysLater.plan == nil)
}

@Test func threeDayAbsenceCreatesAndPersistsThreeDayLightPlan() throws {
    let lastVisit = try GregorianDay(year: 2026, month: 10, day: 26)
    let returned = lastVisit.adding(days: 3)
    let resumed = BahwReturnPlanEngine.recordVisit(
        on: returned,
        state: BahwReturnVisitState(lastVisitedDay: lastVisit)
    )

    let plan = try #require(resumed.plan)
    #expect(plan.days == [returned, returned.adding(days: 1), returned.adding(days: 2)])
    #expect(plan.quranGoal == .halfWird)
    #expect(plan.habitsPerDay == 1)
    #expect(BahwReturnPlanEngine.dayNumber(on: returned, state: resumed) == 1)

    let encoded = try JSONEncoder().encode(resumed)
    let reopened = try JSONDecoder().decode(BahwReturnVisitState.self, from: encoded)
    #expect(reopened == resumed)
    #expect(BahwReturnPlanEngine.dayNumber(on: returned.adding(days: 1), state: reopened) == 2)
    #expect(BahwReturnPlanEngine.dayNumber(on: returned.adding(days: 2), state: reopened) == 3)
}

@Test func planExpiresAfterItsThirdDayAndCanRestartAfterAnotherAbsence() throws {
    let start = try GregorianDay(year: 2026, month: 10, day: 26)
    let first = BahwReturnPlanEngine.recordVisit(
        on: start,
        state: BahwReturnVisitState(lastVisitedDay: start.adding(days: -3))
    )
    let second = BahwReturnPlanEngine.recordVisit(on: start.adding(days: 1), state: first)
    let third = BahwReturnPlanEngine.recordVisit(on: start.adding(days: 2), state: second)
    let afterPlan = BahwReturnPlanEngine.recordVisit(on: start.adding(days: 3), state: third)
    #expect(afterPlan.plan == nil)

    let returnedAgain = BahwReturnPlanEngine.recordVisit(on: start.adding(days: 6), state: afterPlan)
    #expect(returnedAgain.plan?.days.first == start.adding(days: 6))
    #expect(BahwReturnPlanEngine.dayNumber(on: start.adding(days: 6), state: returnedAgain) == 1)
}
