import Foundation
import Testing
@testable import MadarCore

/// B2-4: «جماعة | وحدي» sit on the open prayer's card. They never appear inside the sanctity window
/// (adhan + 30 min, Maghrib + 20), after the prayer's time ended, or for a prayer that needs more than one tap.
struct PrayerQuickLogTests {
    private let adhan = Date(timeIntervalSince1970: 1_792_000_000)
    private let next = Date(timeIntervalSince1970: 1_792_000_000 + 3 * 3600)
    private func at(_ minutes: Double) -> Date { adhan.addingTimeInterval(minutes * 60) }
    private func offered(_ prayer: Prayer = .asr, minutes: Double, pending: Bool = true, canLog: Bool = true, friday: Bool = false, nextAdhan: Date? = nil) -> Bool {
        PrayerQuickLog.isOffered(prayer: prayer, adhan: adhan, nextAdhan: nextAdhan ?? next, isPending: pending, canLog: canLog, isFridayNoon: friday, now: at(minutes))
    }

    @Test func notBeforeTheAdhanAndNotInsideTheSanctityWindow() {
        #expect(!offered(minutes: -1))
        #expect(!offered(minutes: 0))          // adhan itself
        #expect(!offered(minutes: 29.9))
        #expect(offered(minutes: 30))          // the window ends at adhan + 30
    }
    @Test func maghribWindowIsTwentyMinutes() {
        #expect(!offered(.maghrib, minutes: 19.9))
        #expect(offered(.maghrib, minutes: 20))
    }
    @Test func notAfterTheNextAdhan() {
        #expect(offered(minutes: 179))
        #expect(!offered(minutes: 180))
    }
    @Test func noNextAdhanMeansTheWindowStaysOpen() {
        #expect(PrayerQuickLog.isOffered(prayer: .isha, adhan: adhan, nextAdhan: nil, isPending: true, canLog: true, isFridayNoon: false, now: at(240)))
    }
    @Test func onlyAPendingLoggablePrayerThatNeedsOneTap() {
        #expect(!offered(minutes: 60, pending: false))
        #expect(!offered(minutes: 60, canLog: false))
        #expect(!offered(.dhuhr, minutes: 60, friday: true))   // Friday noon asks «جمعة أم ظهر» first
    }

    /// Batch 3: «ينتهي وقتها بعد …» is shown only where the next adhan really ends the prayer's time:
    /// Dhuhr→Asr, Asr→Maghrib, Maghrib→Isha. Fajr ends at sunrise and Isha at midnight, neither of which the next adhan is.
    @Test func timeLeftIsTheGapToTheNextAdhanOnlyWhereThatEndsTheTime() {
        #expect(PrayerQuickLog.timeLeft(prayer: .asr, nextAdhan: next, now: at(90)) == 5400.0)
        #expect(PrayerQuickLog.timeLeft(prayer: .dhuhr, nextAdhan: next, now: at(60)) == 7200.0)
        #expect(PrayerQuickLog.timeLeft(prayer: .maghrib, nextAdhan: next, now: at(30)) == 9000.0)
        #expect(PrayerQuickLog.timeLeft(prayer: .fajr, nextAdhan: next, now: at(60)) == nil)
        #expect(PrayerQuickLog.timeLeft(prayer: .isha, nextAdhan: next, now: at(60)) == nil)
        #expect(PrayerQuickLog.timeLeft(prayer: .asr, nextAdhan: nil, now: at(60)) == nil)
        #expect(PrayerQuickLog.timeLeft(prayer: .asr, nextAdhan: next, now: at(180)) == nil)
    }
}
