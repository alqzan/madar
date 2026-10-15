import Foundation
import Testing
import MadarCore
@testable import MadarInbox

struct NotificationBudgetTests {
    private func clock(_ time: String) -> Date { ISO8601DateFormatter().date(from: "2026-10-09T\(time):00+03:00")! }
    private func fixture(budget: Int = 4, enabled: Bool = true, quiet: Int? = nil, boundary: DayBoundary = .fajr) throws -> (NotificationBudgetStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarBudget-\(UUID())")
        let store = NotificationBudgetStore(directory: root)
        let day = try GregorianDay("2026-10-09")
        let prayers = (0..<3).map { offset in
            let date = day.adding(days: offset)
            let base = date.date(in: ActivePlace.riyadh.timeZone)
            // §13 Riyadh golden clock values, independent of the engine's output.
            return PrayerDay(day: date, place: .riyadh, fajr: base.addingTimeInterval(4*3600+31*60), sunrise: base.addingTimeInterval(5*3600+48*60),
                dhuhr: base.addingTimeInterval(11*3600+41*60), asr: base.addingTimeInterval(15*3600+2*60),
                maghrib: base.addingTimeInterval(17*3600+32*60), isha: base.addingTimeInterval(19*3600+2*60))
        }
        try store.publish(.init(generatedAt: clock("00:00"), validUntil: clock("23:59"), activityEnabled: enabled,
            remindersEnabled: true, dailyBudget: budget, quietFromMinutes: quiet, dayBoundary: boundary, prayerDays: prayers))
        return (store, root)
    }
    @Test func sanctityClampsStartAndRepeatDoesNotSpendTwice() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let result = try store.reservePrayerActivity(id: "activity.one", now: clock("04:40"))
        #expect(result.reservation.scheduledAt == clock("05:01"))
        #expect(result.prayer == .dhuhr)
        #expect(result.prayerAt == clock("11:41"))
        #expect(result.reservation.dayKey == "2026-10-09")
        #expect(throws: NotificationBudgetError.duplicate) { try store.reservePrayerActivity(id: "activity.two", now: clock("04:41")) }
        #expect(try store.reservations().count == 1)
    }
    @Test func roomAndActivityShareFourSlotsAcrossIndependentClients() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for n in 0..<3 { try store.reserve(.init(id: "quran.\(n)", dayKey: "2026-10-09", scheduledAt: clock("15:32")), now: clock("04:40")) }
        _ = try NotificationBudgetStore(directory: root).reservePrayerActivity(id: "activity.one", now: clock("04:40"))
        #expect(throws: NotificationBudgetError.full) { try store.reserve(.init(id: "quran.extra", dayKey: "2026-10-09", scheduledAt: clock("16:00")), now: clock("04:40")) }
        #expect(try store.reservations().count == 4)
    }
    @Test func cancellationRefundsOnlyBeforeStartOrKnownFailure() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try store.reservePrayerActivity(id: "pending", now: clock("04:40"))
        try store.cancel(id: first.reservation.id, now: clock("04:50"))
        #expect(try store.reservations().isEmpty)
        _ = try store.reservePrayerActivity(id: "spent", now: clock("04:40"))
        try store.cancel(id: "spent", now: clock("05:02"))
        #expect(try store.reservations().count == 1)
        try store.cancel(id: "spent", now: clock("05:02"), requestFailed: true)
        #expect(try store.reservations().isEmpty)
    }
    @Test func staleDisabledQuietAndNightFailClosed() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: NotificationBudgetError.unavailable) { try store.reservePrayerActivity(id: "stale", now: clock("23:59")) }
        #expect(throws: NotificationBudgetError.disabled) { try store.reservePrayerActivity(id: "night", now: clock("02:00")) }
        #expect(throws: NotificationBudgetError.disabled) { try store.reservePrayerActivity(id: "isha", now: clock("18:00")) }
        let (off, offRoot) = try fixture(enabled: false); defer { try? FileManager.default.removeItem(at: offRoot) }
        #expect(throws: NotificationBudgetError.disabled) { try off.reservePrayerActivity(id: "off", now: clock("04:40")) }
        let (quiet, quietRoot) = try fixture(quiet: 5*60); defer { try? FileManager.default.removeItem(at: quietRoot) }
        #expect(throws: NotificationBudgetError.full) { try quiet.reservePrayerActivity(id: "quiet", now: clock("04:40")) }
        try Data("broken".utf8).write(to: root.appending(path: "budget.json"))
        #expect(throws: (any Error).self) { try store.reservePrayerActivity(id: "corrupt", now: clock("04:40")) }
    }
    @Test func legacyImportAndRepublishRetainExternalReservations() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.reservePrayerActivity(id: "external", now: clock("04:40"))
        let day = try GregorianDay("2026-10-09")
        let prayers = try #require(PrayerTimesEngine.calculate(day: day, place: .riyadh))
        let seed = NotificationBudgetReservation(id: "legacy", dayKey: "2026-10-09", scheduledAt: clock("06:00"))
        let policy = NotificationBudgetPolicy(generatedAt: clock("04:45"), validUntil: clock("23:59"), activityEnabled: false,
            remindersEnabled: true, dailyBudget: 4, quietFromMinutes: nil, dayBoundary: .fajr, prayerDays: [prayers])
        try store.publish(policy, importing: [seed, seed])
        try store.publish(policy, importing: [seed])
        #expect(Set(try store.reservations().map(\.id)) == ["external", "legacy"])
        #expect(throws: NotificationBudgetError.disabled) { try store.reservePrayerActivity(id: "off", now: clock("04:45")) }
    }
    @Test func parallelReservationsNeverOverspend() async throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = clock("04:40"), due = clock("15:32")
        let successes = await withTaskGroup(of: Bool.self) { group in
            for n in 0..<40 {
                group.addTask {
                    do { try NotificationBudgetStore(directory: root).reserve(.init(id: "parallel.\(n)", dayKey: "2026-10-09", scheduledAt: due), now: now); return true }
                    catch { return false }
                }
            }
            var count = 0; for await result in group where result { count += 1 }; return count
        }
        #expect(successes == 4)
        #expect(try store.reservations().count == 4)
    }
    @Test func storedBudgetDayFollowsConfiguredBoundaryAfterSanctity() throws {
        for boundary in [DayBoundary.midnight, .fajr, .maghrib] {
            let (store, root) = try fixture(boundary: boundary); defer { try? FileManager.default.removeItem(at: root) }
            let reserved = try store.reservePrayerActivity(id: "boundary", now: clock("04:40"))
            #expect(reserved.reservation.dayKey == (boundary == .maghrib ? "2026-10-08" : "2026-10-09"))
            #expect(reserved.reservation.scheduledAt == clock("05:01"))
        }
    }
}
