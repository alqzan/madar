import Foundation
import Testing
@testable import MadarCore

/// B3-1: which step leads the lobby depends on the moment of the day. Fixture times are the spec's rules
/// (adhan + 30 min sanctity, Maghrib + 20), written by hand, not read back from the code.
private let midnight = Date(timeIntervalSince1970: 1_792_000_000)
private func at(_ hour: Int, _ minute: Int, day: Int = 0) -> Date { midnight.addingTimeInterval(TimeInterval(day * 86_400 + hour * 3600 + minute * 60)) }
private func prayerDay(_ offset: Int) throws -> PrayerDay {
    try PrayerDay(day: GregorianDay(year: 2026, month: 11, day: 10).adding(days: offset), place: .riyadh,
                  fajr: at(4, 45, day: offset), sunrise: at(6, 5, day: offset), dhuhr: at(11, 30, day: offset),
                  asr: at(14, 50, day: offset), maghrib: at(17, 20, day: offset), isha: at(18, 50, day: offset))
}
private func days() throws -> [PrayerDay] { try [prayerDay(-1), prayerDay(0), prayerDay(1)] }

@Test func nothingReachesTheLobbyInsideASanctityWindow() throws {
    let all = try days()
    #expect(LobbyMomentPlan.moment(at: at(4, 50), days: all) == .quiet)      // Fajr 04:45–05:15
    #expect(LobbyMomentPlan.moment(at: at(17, 39), days: all) == .quiet)     // Maghrib 17:20–17:40
    #expect(LobbyMomentPlan.moment(at: at(17, 40), days: all) != .quiet)     // window ended
}

@Test func theMomentFollowsTheDay() throws {
    let all = try days()
    #expect(LobbyMomentPlan.moment(at: at(5, 20), days: all) == .morning)
    #expect(LobbyMomentPlan.moment(at: at(6, 19), days: all) == .morning)    // sunrise 06:05 + 15
    #expect(LobbyMomentPlan.moment(at: at(6, 20), days: all) == .duha)
    #expect(LobbyMomentPlan.moment(at: at(10, 0), days: all) == .duha)
    #expect(LobbyMomentPlan.moment(at: at(11, 10), days: all) == .beforeAdhan(.dhuhr, minutes: 20))
    #expect(LobbyMomentPlan.moment(at: at(12, 10), days: all) == .general)
    #expect(LobbyMomentPlan.moment(at: at(16, 0), days: all) == .general)
    #expect(LobbyMomentPlan.moment(at: at(18, 30), days: all) == .beforeAdhan(.isha, minutes: 20))
    #expect(LobbyMomentPlan.moment(at: at(19, 30), days: all) == .evening)
    #expect(LobbyMomentPlan.moment(at: at(1, 0), days: all) == .evening)     // after midnight, before Fajr
    #expect(LobbyMomentPlan.moment(at: at(11, 0), days: all) == .duha)       // 30 min exactly before Dhuhr is not «within»
}

@Test func theLeadStepMovesFirstAndTheRestKeepTheirOrder() {
    let ids = ["prayer", "habit", "quran", "notes"]
    #expect(LobbyMomentPlan.order(ids, moment: .morning) == ["quran", "prayer", "habit", "notes"])
    #expect(LobbyMomentPlan.order(ids, moment: .duha) == ["habit", "prayer", "quran", "notes"])
    #expect(LobbyMomentPlan.order(ids, moment: .evening) == ["notes", "prayer", "habit", "quran"])
    #expect(LobbyMomentPlan.order(ids, moment: .general) == ids)
    #expect(LobbyMomentPlan.order(["quran", "habit"], moment: .evening) == ["quran", "habit"])   // the lead is absent
}

@Test func theNextPrayerLeadsBeforeAdhanAndFridayKahfFollowsTheLead() {
    #expect(LobbyMomentPlan.order(["prayer", "habit", "nextPrayer"], moment: .beforeAdhan(.asr, minutes: 12)) == ["nextPrayer", "prayer", "habit"])
    #expect(LobbyMomentPlan.order(["prayer", "kahf", "quran"], moment: .morning) == ["quran", "kahf", "prayer"])
    #expect(LobbyMomentPlan.order(["prayer", "kahf"], moment: .general) == ["kahf", "prayer"])
    #expect(LobbyMomentPlan.order(["prayer", "kahf", "notes"], moment: .quiet).isEmpty)
}
