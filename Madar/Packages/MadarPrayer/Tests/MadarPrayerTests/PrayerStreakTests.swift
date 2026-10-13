import Foundation
import Testing
import MadarCore
@testable import MadarPrayer

/// Owner decision, 13 October 2026: three nested streaks counted up to yesterday; pending days neither count nor break;
/// a made-up qada repairs only the completion streak. Expected values are worked out by hand from that rule.
struct PrayerStreakTests {
    private func day(_ key: String, _ statuses: [PrayerDisplayStatus]) throws -> PrayerDaySummary {
        let gregorian = try GregorianDay(key)
        return PrayerDaySummary(day: gregorian, cells: zip(Prayer.allCases, statuses).map { prayer, status in
            PrayerCell(reference: PrayerReference(day: gregorian, prayer: prayer), status: status, heart: nil, time: nil, prayerTime: nil,
                       shortened: false, fridayKind: nil, pairID: nil, isFriday: false, canLog: false, canMarkMissed: false, canMakeUp: false)
        })
    }
    private func week(fajrOnThird: PrayerDisplayStatus) throws -> [PrayerDaySummary] {
        let j = PrayerDisplayStatus.jamaah
        return [
            try day("2026-10-01", [j, j, j, j, j]),
            try day("2026-10-02", [j, j, j, j, j]),
            try day("2026-10-03", [fajrOnThird, j, j, j, j]),
            try day("2026-10-04", [j, j, .alone, j, j]),
            try day("2026-10-05", [j, j, j, j, j]),
            try day("2026-10-06", [j, j, j, j, .pending]),
            try day("2026-10-07", [j, j, j, j, j]),
            try day("2026-10-08", [j, .pending, .future, .future, .future])
        ]
    }
    private func paidFajr() throws -> [PrayerQada] {
        [PrayerQada(id: UUID(), reference: PrayerReference(day: try GregorianDay("2026-10-03"), prayer: .fajr), madeUpAt: Date(), fridayKind: nil, isFriday: false)]
    }

    @Test func marksShowWhereEachStreakBrokeAndWhy() throws {
        let today = try GregorianDay("2026-10-08"), days = try week(fajrOnThird: .qada), qada = try paidFajr()
        let congregation = PrayerStreaks.marks(days, level: .congregation, qada: qada, before: today).map(\.mark)
        #expect(congregation == [.counted, .open, .counted, .brokeAlone, .outside, .outside, .outside])
        let onTime = PrayerStreaks.marks(days, level: .onTime, qada: qada, before: today).map(\.mark)
        #expect(onTime == [.counted, .open, .counted, .counted, .brokeQada, .outside, .outside])
        let completion = PrayerStreaks.marks(days, level: .completion, qada: qada, before: today).map(\.mark)
        #expect(completion == [.counted, .open, .counted, .counted, .counted, .counted, .counted])
        #expect(PrayerStreaks.length(days, level: .congregation, qada: qada, before: today) == 2)
        #expect(PrayerStreaks.length(days, level: .onTime, qada: qada, before: today) == 3)
        #expect(PrayerStreaks.length(days, level: .completion, qada: qada, before: today) == 6)
    }

    @Test func missedPrayerNotMadeUpBreaksCompletionToo() throws {
        let today = try GregorianDay("2026-10-08"), days = try week(fajrOnThird: .missed)
        let completion = PrayerStreaks.marks(days, level: .completion, qada: [], before: today).map(\.mark)
        #expect(completion == [.counted, .open, .counted, .counted, .brokeMissed, .outside, .outside])
        #expect(PrayerStreaks.length(days, level: .completion, qada: [], before: today) == 3)
    }
}
