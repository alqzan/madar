import Foundation
import Testing
@testable import MadarSnapshots

struct SnapshotStoreTests {
    private func temporaryStore() -> SnapshotStore {
        SnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }
    @Test func completeRoundTripAndExpiry() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let instant = Date(timeIntervalSince1970: 1_791_532_800)
        let snapshot = SnapshotEnvelope(name: "FoundationSnapshot", generatedAt: instant, validUntil: instant.addingTimeInterval(60), dayKey: "2026-10-10", tzID: "Asia/Riyadh", privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: "hijri", numerals: "arabicIndic"))
        try store.write(snapshot)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant)?.payload == snapshot.payload)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant.addingTimeInterval(60)) == nil)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: instant.addingTimeInterval(-1)) == nil)
    }
    @Test func corruptUnknownVersionAndTraversalReturnPlaceholder() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "FoundationSnapshot.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: file)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self) == nil)
        try Data("{truncated".utf8).write(to: file)
        #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self) == nil)
        #expect(throws: SnapshotError.invalidName) { try store.remove("../outside") }
    }
    @Test func concurrentReadersNeverSeePartialJSON() async throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let now = Date(timeIntervalSince1970: 1_791_532_800)
        let envelope = SnapshotEnvelope(name: "FoundationSnapshot", generatedAt: now, validUntil: now.addingTimeInterval(600), dayKey: "2026-10-10", tzID: "Asia/Riyadh", privacy: SnapshotPrivacy(), payload: FoundationSnapshot(firstCalendar: "hijri", numerals: "arabicIndic"))
        try store.write(envelope)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for _ in 0..<100 { try store.write(envelope) } }
            group.addTask { for _ in 0..<100 { #expect(store.read("FoundationSnapshot", as: FoundationSnapshot.self, now: now) != nil) } }
            try await group.waitForAll()
        }
    }
    @Test func exclusiveAccessAllowsOnlyOneConcurrentActionClaim() async throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let now = Date(), name = "ActionClaim"
        func envelope(_ value: String) -> SnapshotEnvelope<FoundationSnapshot> {
            .init(name: name, generatedAt: now, validUntil: now.addingTimeInterval(600), dayKey: "2026-11-01", tzID: "Asia/Riyadh", privacy: .init(), payload: .init(firstCalendar: value, numerals: "hindi"))
        }
        try store.write(envelope("available"))

        let wins = try await withThrowingTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try store.withExclusiveAccess(for: name) {
                        guard let current = store.read(name, as: FoundationSnapshot.self, now: now),
                              current.payload.firstCalendar == "available" else { return false }
                        Thread.sleep(forTimeInterval: 0.005)
                        try store.write(envelope("claimed"))
                        return true
                    }
                }
            }
            var total = 0
            for try await didWin in group where didWin { total += 1 }
            return total
        }

        #expect(wins == 1)
        #expect(store.read(name, as: FoundationSnapshot.self, now: now)?.payload.firstCalendar == "claimed")
    }
}

/// Expected values come from the S1/S7 canonical: at 16:20 the next prayer is Maghrib 17:34, «بعد ١:١٤».
struct PrayerNextSnapshotTests {
    @Test func configuredTimelineRefreshesAtMinuteHorizonOrEarlierExpiry() {
        let start = Date(timeIntervalSince1970: 1_791_000_000)
        let value = PrayerNextSnapshot(items: [.init(prayer: "fajr", name: "الفجر", at: start.addingTimeInterval(30 * 3600))], numerals: "hindi")
        let window = value.minuteWindow(from: start, validUntil: start.addingTimeInterval(30 * 3600))
        #expect(window.dates.count == 481)
        #expect(window.refreshAt == start.addingTimeInterval(481 * 60))
        let short = value.minuteWindow(from: start, validUntil: start.addingTimeInterval(90))
        #expect(short.dates == [start, start.addingTimeInterval(60)])
        #expect(short.refreshAt == start.addingTimeInterval(90))
    }
    private let base = Date(timeIntervalSince1970: 1_791_000_000) // arbitrary instant; only differences matter
    private func snapshot(numerals: String = "hindi") -> PrayerNextSnapshot {
        PrayerNextSnapshot(items: [
            .init(prayer: "isha", name: "العشاء", at: base.addingTimeInterval(194 * 60)),
            .init(prayer: "maghrib", name: "المغرب", at: base.addingTimeInterval(74 * 60 + 27)),
            .init(prayer: "asr", name: "العصر", at: base.addingTimeInterval(-10 * 60)),
        ], numerals: numerals)
    }
    @Test func nextPrayerAndCountdownMatchTheCanonical() {
        let state = snapshot().state(at: base)
        #expect(state?.item.prayer == "maghrib")
        #expect(state?.minutes == 74)
        #expect(snapshot().countdown(minutes: 74) == "١:١٤")
    }
    @Test func movesToTheFollowingPrayerAtTheTimeAndEndsWhenOutOfData() {
        #expect(snapshot().state(at: base.addingTimeInterval(74 * 60 + 27))?.item.prayer == "isha")
        #expect(snapshot().state(at: base.addingTimeInterval(194 * 60)) == nil)
    }
    @Test func todayAndTomorrowKeepTodaysFajrForControlsAfterItOccurred() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let formatter = ISO8601DateFormatter()
        func instant(_ value: String) throws -> Date { try #require(formatter.date(from: value)) }
        let candidates = [
            PrayerNextSnapshot.Item(prayer: "isha", name: "العشاء", at: try instant("2026-10-12T19:30:00+03:00")),
            PrayerNextSnapshot.Item(prayer: "fajr", name: "الفجر", at: try instant("2026-10-13T05:00:00+03:00")),
            PrayerNextSnapshot.Item(prayer: "dhuhr", name: "الظهر", at: try instant("2026-10-13T12:00:00+03:00")),
            PrayerNextSnapshot.Item(prayer: "fajr", name: "الفجر", at: try instant("2026-10-14T05:00:00+03:00"))
        ]

        let retained = PrayerNextSnapshot.itemsForTodayAndTomorrow(
            candidates, at: try instant("2026-10-13T12:15:00+03:00"), timeZone: zone
        )
        #expect(retained.map(\.prayer) == ["fajr", "dhuhr", "fajr"])
        #expect(retained.first?.at == (try instant("2026-10-13T05:00:00+03:00")))
    }
    @Test func countdownUsesTwoFieldsAndTheChosenNumerals() {
        #expect(snapshot().countdown(minutes: 5) == "٠:٠٥")
        #expect(snapshot().countdown(minutes: 600) == "١٠:٠٠")
        #expect(snapshot(numerals: "western").countdown(minutes: 74) == "1:14")
    }
    @Test func timelineHasOneEntryPerMinuteAndStopsAtTheLastPrayer() {
        let dates = snapshot().timelineDates(from: base.addingTimeInterval(30))
        #expect(dates.count == 195) // base+0 ... base+194 min
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 60 })
    }
    @Test func roundTripsThroughTheSnapshotStore() throws {
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let value = snapshot()
        try store.write(SnapshotEnvelope(name: "prayerNext", generatedAt: base, validUntil: base.addingTimeInterval(3600), dayKey: "2026-10-07", tzID: "Asia/Riyadh", privacy: SnapshotPrivacy(), payload: value))
        #expect(store.read("prayerNext", as: PrayerNextSnapshot.self, now: base.addingTimeInterval(1))?.payload == value)
    }
}
