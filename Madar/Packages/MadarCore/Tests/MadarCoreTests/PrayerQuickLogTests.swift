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

/// The lobby ask: latest pending prayer, silent inside any sanctity window (adhan + 30, Maghrib + 20).
struct PrayerLobbyAskTests {
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    private func entry(_ prayer: Prayer, _ minutes: Double?, pending: Bool = true, canLog: Bool = true, friday: Bool = false) -> PrayerLobbyAsk.Entry {
        .init(prayer: prayer, adhan: minutes.map(at), isPending: pending, canLog: canLog, isFridayNoon: friday)
    }
    @Test func silentInsideTheWindowOfAnyPrayer() {
        let list = [entry(.fajr, -600), entry(.dhuhr, 0)]
        #expect(PrayerLobbyAsk.choose(list, now: at(29)) == nil)
        #expect(PrayerLobbyAsk.choose(list, now: at(31)) == .dhuhr)
    }
    @Test func maghribWindowIsTwenty() {
        let list = [entry(.asr, -300), entry(.maghrib, 0)]
        #expect(PrayerLobbyAsk.choose(list, now: at(19)) == nil)
        #expect(PrayerLobbyAsk.choose(list, now: at(21)) == .maghrib)
    }
    @Test func fridayNoonIsSkipped() {
        let list = [entry(.fajr, -600), entry(.dhuhr, -120, friday: true)]
        #expect(PrayerLobbyAsk.choose(list, now: at(0)) == .fajr)
    }
    @Test func latestPendingIsChosen() {
        let list = [entry(.fajr, -600), entry(.dhuhr, -400), entry(.asr, -200)]
        #expect(PrayerLobbyAsk.choose(list, now: at(0)) == .asr)
    }
    @Test func loggedAndFuturePrayersAreNotAsked() {
        let list = [entry(.fajr, -600), entry(.dhuhr, -400, pending: false), entry(.asr, 60)]
        #expect(PrayerLobbyAsk.choose(list, now: at(0)) == .fajr)
        #expect(PrayerLobbyAsk.choose([entry(.fajr, -600, pending: false)], now: at(0)) == nil)
    }
}
