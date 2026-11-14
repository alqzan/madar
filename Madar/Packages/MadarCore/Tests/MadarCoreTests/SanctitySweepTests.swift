import Foundation
import Testing
@testable import MadarCore

/// Review T01 / T14 item 1: every room, every prayer and three offsets (at adhan, +1 s, +29:59) is scheduled outside every window.
/// Expected rule from the spec: adhan to +30 min (+20 for Maghrib), nothing reaches the user inside it.
struct SanctitySweepTests {
    @Test func noRoomRequestLandsInsideAnyWindow() throws {
        let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
        let offsets: [TimeInterval] = [0, 1, 29 * 60 + 59]
        var inputs: [NotificationCandidate] = []
        for room in [Room.quran, .habits, .notes, .mal, .mihbara] {
            for prayer in Prayer.allCases {
                for (index, offset) in offsets.enumerated() {
                    inputs.append(NotificationCandidate(id: "\(room.rawValue).\(prayer.rawValue).\(index)", room: room,
                                                        dueAt: day.time(for: prayer).addingTimeInterval(offset), dayKey: day.day.description))
                }
            }
        }
        let plan = NotificationArbiter.plan(candidates: inputs, prayerDays: [day], now: day.fajr.addingTimeInterval(-3600),
                                            timeZone: day.place.timeZone, policy: .init(dailyBudget: 500, staleNudgeEnabled: false))
        #expect(!plan.scheduled.isEmpty)
        for item in plan.scheduled {
            #expect(!day.sanctityWindows.contains { $0.contains(item.dueAt) }, "\(item.id) lands inside a window")
        }
    }
}
