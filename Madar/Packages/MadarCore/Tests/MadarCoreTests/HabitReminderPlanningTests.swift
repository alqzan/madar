import Foundation
import Testing
@testable import MadarCore

/// Owner, 17 Nov 2026 (ideas 4 and 9). Expected values are worked from the rule: 15 minutes, the median of the newest 14.
struct HabitReminderPlanningTests {
    let base = ISO8601DateFormatter().date(from: "2026-10-15T15:00:00Z")!
    func reminder(_ id: UUID, minutes: Double, day: String = "2026-10-15") -> NotificationCandidate {
        .init(id: "habits.\(day).\(id.uuidString)", room: .habits, dueAt: base.addingTimeInterval(minutes * 60), dayKey: day)
    }
    @Test func remindersWithinFifteenMinutesBecomeOne() throws {
        let a = UUID(), b = UUID(), c = UUID(), far = UUID()
        let other = NotificationCandidate(id: "quran.2026-10-15.wird", room: .quran, dueAt: base, dayKey: "2026-10-15")
        let result = RoomReminders.groupHabitReminders([reminder(a, minutes: 0), reminder(b, minutes: 15), reminder(c, minutes: 9), reminder(far, minutes: 16), other])
        // 0, 9 and 15 minutes are within 15 of the first; 16 is not.
        let group = try #require(result.first { RoomReminders.groupedHabitIDs($0.id) != nil })
        #expect(Set(try #require(RoomReminders.groupedHabitIDs(group.id))) == [a, b, c])
        #expect(group.dueAt == base.addingTimeInterval(15 * 60) && group.dayKey == "2026-10-15" && group.room == .habits)
        #expect(result.count == 3 && result.contains { $0.id == "habits.2026-10-15.\(far.uuidString)" } && result.contains(other))
    }
    @Test func aloneOrFarApartStaysSeparateAndFinalAlertsAreNeverGrouped() {
        let a = UUID(), b = UUID()
        let spread = [reminder(a, minutes: 0), reminder(b, minutes: 16)]
        #expect(RoomReminders.groupHabitReminders(spread) == spread)
        let final = NotificationCandidate(id: "habits.2026-10-15.final.\(a.uuidString)", room: .habits, dueAt: base, dayKey: "2026-10-15")
        let mixed = [reminder(b, minutes: 0), final]
        #expect(RoomReminders.groupHabitReminders(mixed) == mixed)
        #expect(RoomReminders.groupedHabitIDs("habits.2026-10-15.\(a.uuidString)") == nil)
    }
    @Test func differentDaysAreNotGrouped() {
        let a = UUID(), b = UUID()
        let two = [reminder(a, minutes: 0, day: "2026-10-15"), reminder(b, minutes: 5, day: "2026-10-16")]
        #expect(RoomReminders.groupHabitReminders(two).count == 2)
    }
    @Test func learnedMinuteIsTheMedianOfTheNewestFourteen() throws {
        let zone = ActivePlace.riyadh.timeZone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! }
        // Three times 07:50, 08:00, 08:10: median 08:00 = 480.
        #expect(RoomReminders.learnedHabitMinute(eventTimes: [at(1, 8, 10), at(2, 7, 50), at(3, 8, 0)], timeZone: zone) == 480)
        // Two are too few.
        #expect(RoomReminders.learnedHabitMinute(eventTimes: [at(1, 8, 10), at(2, 7, 50)], timeZone: zone) == nil)
        // Even count: 08:00 and 09:00 around the middle → 08:30 = 510.
        #expect(RoomReminders.learnedHabitMinute(eventTimes: [at(1, 7, 0), at(2, 8, 0), at(3, 9, 0), at(4, 22, 0)], timeZone: zone) == 510)
        // Only the newest 14 count: 14 days at 20:00 are newer than 5 old ones at 06:00.
        let newest = (11...24).map { at($0, 20, 0) }, old = (1...5).map { at($0, 6, 0) }
        #expect(RoomReminders.learnedHabitMinute(eventTimes: old + newest, timeZone: zone) == 1200)
        let start = try #require(RoomReminders.habitLearnedStart(minute: 480, on: try GregorianDay("2026-10-16"), timeZone: zone))
        #expect(start == at(16, 8, 0))
    }
}
