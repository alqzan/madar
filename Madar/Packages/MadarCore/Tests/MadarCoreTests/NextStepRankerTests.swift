import Foundation
import Testing
@testable import MadarCore

/// T13: ten cases, each with its expected order worked out by hand in the comment above it (hours counted from `t0`).
struct NextStepRankerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }
    func item(_ id: String, _ hours: Double) -> NextStepInput.Item { .init(id: id, title: id, at: at(hours)) }
    func ids(_ input: NextStepInput) -> [String] { NextStepRanker.rank(input).map(\.id) }

    // 1. Nothing is due: no suggestion.
    @Test func emptyDayGivesNothing() { #expect(ids(.init(now: t0)).isEmpty) }
    // 2. Adhan in 10 min (<= 20): the prayer is «الآن».
    @Test func prayerInTenMinutesIsNow() {
        let steps = NextStepRanker.rank(.init(now: t0, nextPrayer: .init(id: "asr", title: "العصر", at: t0.addingTimeInterval(600))))
        #expect(steps.map(\.band) == [.now])
    }
    // 3. Adhan in 3 h: «اليوم», not «الآن».
    @Test func prayerInThreeHoursIsToday() {
        #expect(NextStepRanker.rank(.init(now: t0, nextPrayer: item("asr", 3))).first?.band == .today)
    }
    // 4. Inside the sanctity window only the prayer is returned, whatever else is due (Dhuhr adhan at t0-5min, window 30 min).
    @Test func insideTheWindowOnlyThePrayer() {
        let window = SanctityWindow(prayer: .dhuhr, adhan: t0.addingTimeInterval(-300))
        let input = NextStepInput(now: t0, openWindow: window, wirdPagesLeft: 5, obligations: [item("rent", -1)], habitsDue: [item("h", 0)], dayPageEmpty: true)
        #expect(ids(input) == ["prayer.window"])
    }
    // 5. An obligation overdue by 1 h is «الآن».
    @Test func overdueObligationIsNow() { #expect(NextStepRanker.rank(.init(now: t0, obligations: [item("rent", -1)])).first?.band == .now) }
    // 6. Obligation due in 30 h: «قريبًا»; in 60 h: not shown (48 h horizon).
    @Test func obligationHorizonIs48Hours() {
        #expect(NextStepRanker.rank(.init(now: t0, obligations: [item("a", 30)])).first?.band == .soon)
        #expect(NextStepRanker.rank(.init(now: t0, obligations: [item("b", 60)])).isEmpty)
    }
    // 7. Bands order first (now < today < soon), then by time: overdue rent (-1h, now), prayer 3h (today), obligation 30h (soon).
    @Test func bandsThenTime() {
        let input = NextStepInput(now: t0, nextPrayer: item("asr", 3), obligations: [item("loan", 30), item("rent", -1)])
        #expect(ids(input) == ["obligation.rent", "prayer.asr", "obligation.loan"])
    }
    // 8. Salary in 20 h and a trip in 40 h enter the order: salary today, trip soon.
    @Test func salaryAndTripsEnterTheRanking() {
        let steps = NextStepRanker.rank(.init(now: t0, salary: item("pay", 20), trips: [item("riyadh", 40)]))
        #expect(steps.map(\.id) == ["salary.pay", "trip.riyadh"]); #expect(steps.map(\.band) == [.today, .soon])
    }
    // 9. Today's undated items follow the dated ones in the same band: prayer 3h first, then wird, habit (dated 0h goes before undated wird), page.
    @Test func datedBeforeUndatedInABand() {
        let input = NextStepInput(now: t0, nextPrayer: item("asr", 3), wirdPagesLeft: 4, habitsDue: [item("water", 1)], dayPageEmpty: true)
        #expect(ids(input) == ["habit.water", "prayer.asr", "wird", "diary.page"])
    }
    // 10. A finished wird (0 pages left) and a written page add nothing.
    @Test func finishedWirdAndWrittenPageAddNothing() { #expect(ids(.init(now: t0, wirdPagesLeft: 0, dayPageEmpty: false)).isEmpty) }
}
