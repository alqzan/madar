import Foundation
import Testing
import MadarCore
import MadarSnapshots
@testable import MadarInbox

struct PrayerInboxCommandWriterTests {
    private func fixture() -> PendingInbox {
        PendingInbox(directory: FileManager.default.temporaryDirectory.appending(path: "MadarPrayerIntent-\(UUID())"))
    }

    @Test func test_M1F04_shortcutPrayerLogPublishesAStampedInboxCommand() throws {
        let inbox = fixture()
        let generation = InboxGeneration(generationID: UUID(), acceptsUnstampedDeliveries: false)
        try inbox.publishGeneration(generation)
        let instant = Date(timeIntervalSince1970: 1_797_000_000)
        let ticket = try PrayerInboxCommandWriter.logPrayer(
            inbox: inbox,
            dayKey: "2026-10-09",
            prayer: "dhuhr",
            status: "alone",
            shortened: true,
            fridayKind: "dhuhr",
            timeZone: try #require(TimeZone(identifier: "Asia/Riyadh")),
            source: .shortcut,
            issuedAt: instant
        )
        let file = try #require(try inbox.claimBatch().first)
        let record = try inbox.read(file)
        #expect(ticket.commandID == record.command.commandID)
        #expect(record.expectedGenerationID == generation.generationID)
        #expect(record.command.name == "prayer.log")
        #expect(record.command.source == .shortcut)
        #expect(record.command.issuedAt == instant)
        #expect(record.command.payload == .object([
            "dayKey": .string("2026-10-09"),
            "prayer": .string("dhuhr"),
            "status": .string("alone"),
            "shortened": .bool(true),
            "fridayKind": .string("dhuhr")
        ]))
    }

    @Test func test_M1F04_shortcutPrayerLogRejectsInvalidOrAmbiguousInput() throws {
        let inbox = fixture()
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        func write(dayKey: String = "2026-10-09", prayer: String = "dhuhr", status: String = "alone",
                   shortened: Bool? = nil, fridayKind: String? = nil) throws {
            _ = try PrayerInboxCommandWriter.logPrayer(inbox: inbox, dayKey: dayKey, prayer: prayer,
                status: status, shortened: shortened, fridayKind: fridayKind, timeZone: zone, source: .shortcut)
        }

        #expect(throws: PrayerInboxCommandError.invalidDayKey) { try write(dayKey: "2026-02-30") }
        #expect(throws: PrayerInboxCommandError.invalidPrayer) { try write(prayer: "unknown") }
        #expect(throws: PrayerInboxCommandError.unsupportedStatus) { try write(status: "missed") }
        #expect(throws: PrayerInboxCommandError.invalidShortening) { try write(prayer: "fajr", shortened: true) }
        #expect(throws: PrayerInboxCommandError.invalidShortening) {
            try write(status: "jamaah", shortened: true, fridayKind: "jumuah")
        }
        #expect(throws: PrayerInboxCommandError.fridayKindRequired) { try write() }
        #expect(throws: PrayerInboxCommandError.jumuahRequiresCongregation) {
            try write(status: "alone", fridayKind: "jumuah")
        }
        #expect(throws: PrayerInboxCommandError.unexpectedFridayKind) {
            try write(dayKey: "2026-10-10", fridayKind: "jumuah")
        }
        #expect(try inbox.claimBatch().isEmpty)
    }

    @Test func test_M1F04_controlResolvesPrayerDayFromFreshTimesAndRejectsFuturePrayer() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let formatter = ISO8601DateFormatter()
        func instant(_ value: String) throws -> Date { try #require(formatter.date(from: value)) }
        let candidateTimes = [
            PrayerInboxCommandWriter.PrayerTime(prayer: "fajr", at: try instant("2026-10-13T05:00:00+03:00")),
            PrayerInboxCommandWriter.PrayerTime(prayer: "dhuhr", at: try instant("2026-10-13T12:00:00+03:00")),
            PrayerInboxCommandWriter.PrayerTime(prayer: "asr", at: try instant("2026-10-13T15:00:00+03:00")),
            PrayerInboxCommandWriter.PrayerTime(prayer: "maghrib", at: try instant("2026-10-13T18:00:00+03:00")),
            PrayerInboxCommandWriter.PrayerTime(prayer: "isha", at: try instant("2026-10-13T19:30:00+03:00")),
            PrayerInboxCommandWriter.PrayerTime(prayer: "fajr", at: try instant("2026-10-14T05:00:00+03:00"))
        ]
        let candidateSnapshot = PrayerNextSnapshot(items: candidateTimes.map {
            .init(prayer: $0.prayer, name: "", at: $0.at)
        }, numerals: "hindi")
        let times = PrayerNextSnapshot.itemsForTodayAndTomorrow(
            candidateSnapshot.items, at: try instant("2026-10-13T12:15:00+03:00"), timeZone: zone
        ).map { PrayerInboxCommandWriter.PrayerTime(prayer: $0.prayer, at: $0.at) }

        #expect(try PrayerInboxCommandWriter.currentPrayerDayKey(
            at: instant("2026-10-13T12:15:00+03:00"), prayer: "dhuhr", prayerTimes: times, timeZone: zone
        ) == "2026-10-13")
        #expect(try PrayerInboxCommandWriter.currentPrayerDayKey(
            at: instant("2026-10-13T03:00:00+03:00"), prayer: "isha", prayerTimes: times, timeZone: zone
        ) == "2026-10-12")
        #expect(throws: PrayerInboxCommandError.prayerNotOccurred) {
            try PrayerInboxCommandWriter.currentPrayerDayKey(
                at: instant("2026-10-13T11:00:00+03:00"), prayer: "dhuhr", prayerTimes: times, timeZone: zone
            )
        }
        #expect(throws: PrayerInboxCommandError.missingTodayFajr) {
            try PrayerInboxCommandWriter.currentPrayerDayKey(
                at: instant("2026-10-13T12:15:00+03:00"), prayer: "dhuhr", prayerTimes: [], timeZone: zone
            )
        }
    }

    @Test func test_M1F04_controlPrayerLogPublishesAStampedInboxCommand() throws {
        let inbox = fixture()
        let generation = InboxGeneration(generationID: UUID(), acceptsUnstampedDeliveries: false)
        try inbox.publishGeneration(generation)
        _ = try PrayerInboxCommandWriter.logPrayer(
            inbox: inbox,
            dayKey: "2026-10-13",
            prayer: "asr",
            status: "jamaah",
            timeZone: try #require(TimeZone(identifier: "Asia/Riyadh")),
            source: .control
        )
        let file = try #require(try inbox.claimBatch().first)
        let record = try inbox.read(file)
        #expect(record.expectedGenerationID == generation.generationID)
        #expect(record.command.name == "prayer.log")
        #expect(record.command.source == .control)
        #expect(record.command.payload == .object([
            "dayKey": .string("2026-10-13"),
            "prayer": .string("asr"),
            "status": .string("jamaah")
        ]))
    }
}
