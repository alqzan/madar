import Foundation
import Testing
@testable import MadarCore

@Test func humanDateLabelsRespectOrderNumeralsAndSighting() throws {
    let zone = TimeZone(identifier: "Asia/Riyadh")!
    let instant = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00+03:00")!
    let value = DualDate(instant: instant, timeZone: zone)
    let hijri = value.labels()
    #expect(hijri.primary == "٢٨ ربيع الآخر ١٤٤٨ هـ")
    #expect(hijri.secondary == "٩ أكتوبر ٢٠٢٦ م")
    let gregorian = value.labels(firstCalendar: .gregorian, numerals: .western)
    #expect(gregorian.primary == "9 أكتوبر 2026 م")
    #expect(gregorian.secondary == "28 ربيع الآخر 1448 هـ")
    #expect(value.labels(weekday: true).primary == "الجمعة ٢٨ ربيع الآخر ١٤٤٨ هـ")
    #expect(value.labels(compact: true).secondary == "٩ أكتوبر")
    let shifted = DualDate(instant: instant, timeZone: zone, source: .sighting, sightingOffset: 1).labels()
    #expect(shifted.primary == "٢٩ ربيع الآخر ١٤٤٨ هـ")
    #expect(shifted.secondary == hijri.secondary)
}
