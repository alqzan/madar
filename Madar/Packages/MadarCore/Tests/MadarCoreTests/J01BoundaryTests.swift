import Foundation
import Testing
@testable import MadarCore

private struct J01Fixtures: Decodable {
    let fixtureVersion: Int
    let source: String
    let cases: [Case]
    struct Case: Decodable {
        let id: String
        let instant: String
        let zone: String
        let civilDay: String
        let boundary: DayBoundary
        let fajr: String?
        let maghrib: String?
        let expectedKey: String
    }
}

@Test("J01 frozen boundary and DST attribution does not use engine output")
func test_J01_frozenBeforeAtAfterAndDST() throws {
    let url = try #require(Bundle.module.url(forResource: "j01-boundaries-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try JSONDecoder().decode(J01Fixtures.self, from: Data(contentsOf: url))
    #expect(fixture.fixtureVersion == 1)
    #expect(!fixture.source.isEmpty)
    #expect(fixture.cases.count == 17)
    let iso = ISO8601DateFormatter()
    for row in fixture.cases {
        let instant = try #require(iso.date(from: row.instant))
        let place = try ActivePlace(latitude: row.zone == "Europe/London" ? 51.5074 : 24.7136,
                                    longitude: row.zone == "Europe/London" ? -0.1278 : 46.6753,
                                    timeZoneID: row.zone)
        let civil = try GregorianDay(row.civilDay)
        #expect(GregorianDay.containing(instant, in: place.timeZone) == civil, "\(row.id)")
        var prayerDays: [PrayerDay] = []
        if let fajrText = row.fajr, let maghribText = row.maghrib {
            let fajr = try #require(iso.date(from: fajrText))
            let maghrib = try #require(iso.date(from: maghribText))
            // Non-boundary clocks are irrelevant to attribution; no astronomical calculation is called.
            prayerDays = [PrayerDay(day: civil, place: place, fajr: fajr, sunrise: fajr,
                                   dhuhr: maghrib, asr: maghrib, maghrib: maghrib, isha: maghrib)]
        }
        let stored = try MadarDay.resolve(instant: instant, place: place, boundary: row.boundary, prayerDays: prayerDays)
        #expect(stored.dayKey == row.expectedKey, "\(row.id)")
        #expect(stored.timeZoneID == row.zone)
        if row.boundary == .fajr {
            #expect(try MadarDay.prayerDay(instant: instant, place: place, prayerDays: prayerDays) == stored)
        }
        let bytes = try JSONEncoder().encode(stored)
        // A later boundary/zone choice produces another value, never rewrites the stored historical value.
        let otherPlace = try ActivePlace(latitude: 40.7128, longitude: -74.0060, timeZoneID: "America/New_York")
        _ = try MadarDay.resolve(instant: instant, place: otherPlace, boundary: .midnight, prayerDays: [])
        let reopened = try JSONDecoder().decode(StoredDayKey.self, from: bytes)
        #expect(reopened == stored)
    }
}
