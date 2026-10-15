import Foundation
import Testing
@testable import MadarCore

struct DiaryMemoryTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private func day(_ text: String) throws -> GregorianDay { try GregorianDay(text) }
    private func memory(_ text: String, hidden: Bool = false, dayOne: Bool = false) throws -> DiaryMemoryDay {
        try .init(day: day(text), hasWriting: true, dayOne: dayOne, hidden: hidden)
    }
    @Test func gregorianYearsAndLeapDayKeepOriginalDate() throws {
        let leap = try memory("2024-02-29")
        let result = DiaryMemories.select(days: [leap], today: try day("2025-02-28"), zone: zone)
        #expect(result.days == [leap.day]); #expect(result.match == .gregorian)
        let years = try [memory("2025-10-15"), memory("2023-10-15"), memory("2021-10-15")]
        #expect(DiaryMemories.select(days: years, today: try day("2026-10-15"), yearsBack: 3, zone: zone).days == [try day("2025-10-15"), try day("2023-10-15")])
    }
    @Test func hiddenImportedEmptyAndCurrentPagesAreIneligible() throws {
        let today = try day("2026-10-15")
        let rows = try [memory("2025-10-15", hidden: true), memory("2024-10-15", dayOne: true), memory("2026-10-15")]
        #expect(DiaryMemories.select(days: rows, today: today, includeDayOne: false, zone: zone).match == .firstDay)
        #expect(DiaryMemories.select(days: rows, today: today, zone: zone).days == [try day("2024-10-15")])
        #expect(DiaryMemories.select(days: [.init(day: try day("2025-10-15"), hasWriting: false)], today: today, zone: zone).days.isEmpty)
    }
    @Test func echoUsesFirstDistanceAndOlderTie() throws {
        let rows = try [memory("2026-10-07"), memory("2026-10-09"), memory("2026-09-15")]
        let result = DiaryMemories.select(days: rows, today: try day("2026-10-15"), zone: zone)
        #expect(result.match == .echo); #expect(result.days == [try day("2026-10-07")])
        #expect(DiaryMemories.select(days: rows, today: try day("2026-10-15"), noMemory: "todayPhoto", zone: zone).days.isEmpty)
    }
    @Test func hijriMonthEndAndAlternateCalendarFallback() throws {
        // Umm al-Qura: 30 Ramadan 1445 = 9 Apr 2024; Ramadan 1446 ends on 29 Mar 2025 (29 days).
        let old = try memory("2024-04-09")
        let result = DiaryMemories.select(days: [old], today: try day("2025-03-29"), match: .hijri, zone: zone)
        #expect(result.days == [old.day]); #expect(result.match == .hijri)
        let fallback = DiaryMemories.select(days: [old], today: try day("2025-03-29"), zone: zone)
        #expect(fallback.days == [old.day]); #expect(fallback.match == .hijri)
        let shifted = DiaryMemories.select(days: [old], today: try day("2025-03-29"), match: .hijri, zone: zone, hijriSource: .sighting, sightingOffset: -2)
        #expect(shifted.days.isEmpty)
    }
    @Test func fixedEchoesUseCalendarDistancesAndActualDays() throws {
        let rows = try [memory("2026-10-07"), memory("2026-10-09"), memory("2026-09-16"), memory("2026-07-15"), memory("2026-04-15"), memory("2025-10-15"), memory("2024-10-15", hidden: true), memory("2023-10-15", dayOne: true)]
        let result = DiaryMemories.echoes(days: rows, today: try day("2026-10-15"), includeDayOne: false, zone: zone)
        #expect(result.map(\.distance.rawValue) == ["1w", "1m", "3m", "6m", "1y", "2y", "3y"])
        #expect(result.map { $0.day?.description } == ["2026-10-07", "2026-09-16", "2026-07-15", "2026-04-15", "2025-10-15", nil, nil])
        #expect(result[1].target == (try day("2026-09-15")))
        let leap = DiaryMemories.echoes(days: [], today: try day("2024-03-31"), zone: zone)
        #expect(leap[1].target == (try day("2024-02-29")))
    }

}
