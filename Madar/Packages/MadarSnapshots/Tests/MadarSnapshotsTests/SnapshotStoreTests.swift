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
}

/// Expected values come from the S1/S7 canonical: at 16:20 the next prayer is Maghrib 17:34, «بعد ١:١٤».
struct PrayerNextSnapshotTests {
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
