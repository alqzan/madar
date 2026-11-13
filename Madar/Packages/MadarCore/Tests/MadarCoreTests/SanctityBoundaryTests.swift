import Foundation
import Testing
@testable import MadarCore

/// Review T14 items 3: window edges, expected values by hand from the rule (adhan to +30 min, Maghrib +20).
struct SanctityBoundaryTests {
    private let adhan = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dhuhrWindowIsThirtyMinutesHalfOpen() {
        let w = SanctityWindow(prayer: .dhuhr, adhan: adhan)
        #expect(w.contains(adhan))                                      // at adhan: inside
        #expect(w.contains(adhan.addingTimeInterval(30 * 60 - 1)))      // 29:59: inside
        #expect(!w.contains(adhan.addingTimeInterval(30 * 60)))         // +30:00: outside
        #expect(!w.contains(adhan.addingTimeInterval(-1)))              // before adhan: outside
    }

    @Test func maghribWindowIsTwentyMinutes() {
        let w = SanctityWindow(prayer: .maghrib, adhan: adhan)
        #expect(w.contains(adhan.addingTimeInterval(20 * 60 - 1)))
        #expect(!w.contains(adhan.addingTimeInterval(20 * 60)))
    }

    @Test func ishaWindowIsThirtyMinutes() {
        let w = SanctityWindow(prayer: .isha, adhan: adhan)
        #expect(w.end == adhan.addingTimeInterval(30 * 60))
    }
}
