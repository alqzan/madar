import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
@testable import MadarCommands

@Suite(.serialized) @MainActor struct ReplayTests {
    private func fixture(at now: Date = Date()) throws -> (ModelContainer, CommandBus, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MadarCommandFixture-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: directory)
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        let currentDay = prayerDay(now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let daysSinceFriday = (calendar.component(.weekday, from: currentDay.date(in: calendar.timeZone)) + 1) % 7
        let trackDay = currentDay.adding(days: -(daysSinceFriday == 0 ? 7 : daysSinceFriday))
        _ = try settings.stage(["salah.trackingStart": .object(["dayKey": .string(trackDay.description), "edits": .number(0)])], now: now)
        try context.save()
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory, transactionClock: { $0 })), directory)
    }
    private func prayer(_ status: String = "jamaah", id: UUID = UUID(), now: Date) -> CommandEnvelope {
        .init(commandID: id, name: "prayer.log", payload: .object(["dayKey": .string(prayerDay(now).description), "prayer": .string("fajr"), "status": .string(status)]), source: .widget, issuedAt: now)
    }
    private func prayerDay(_ now: Date) -> GregorianDay {
        let place = try! ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        let civil = GregorianDay.containing(now, in: place.timeZone)
        guard let times = PrayerTimesEngine.calculate(day: civil, place: place) else { return civil }
        return now < times.fajr ? civil.adding(days: -1) : civil
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func previousFriday(before day: GregorianDay) -> GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        var candidate = day.adding(days: -1)
        while calendar.component(.weekday, from: candidate.date(in: calendar.timeZone)) != 6 { candidate = candidate.adding(days: -1) }
        return candidate
    }
    @Test func test_M1T06_HeartAnswerClearReplayAndUndoPreservePrayerStatus() async throws {
        let now = date("2026-10-13T09:00:00+03:00")
        let (container, bus, directory) = try fixture(at: now)
        let day = prayerDay(now).description
        let log = prayer(now: now)
        _ = try await bus.execute(log, now: now)
        func heart(_ value: MadarCore.JSONValue, source: CommandSource = .app, id: UUID = UUID()) -> CommandEnvelope {
            .init(commandID: id, name: "prayer.setHeart", payload: .object(["dayKey": .string(day), "prayer": .string("fajr"), "heart": value]), source: source, issuedAt: now)
        }
        let answer = heart(.string("present"))
        let saved = try await bus.execute(answer, now: now)
        #expect(saved.status == .applied && saved.undoToken != nil)
        #expect(try await bus.execute(answer, now: now.addingTimeInterval(1)) == saved)
        #expect(try await bus.execute(heart(.string("present")), now: now.addingTimeInterval(1)).status == .duplicate)
        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(row.status == "jamaah" && row.heart == "present")
        #expect(try await bus.execute(heart(.string("ranked")), now: now).reason == "invalidPayload")
        #expect(try await bus.execute(heart(.string("present"), source: .widget), now: now).status == .needsApp)
        let unrecorded = CommandEnvelope(name: "prayer.setHeart", payload: .object(["dayKey": .string(day), "prayer": .string("asr"), "heart": .string("present")]), issuedAt: now)
        #expect(try await bus.execute(unrecorded, now: now).status == .rejected)
        let reopened = try MadarContainerFactory.makeLocal(at: directory)
        let second = CommandBus(adapter: DurableCommandAdapter(container: reopened, lockDirectory: directory, transactionClock: { $0 }))
        let cleared = try await second.execute(heart(.null), now: now.addingTimeInterval(2))
        #expect(cleared.status == .applied)
        #expect(try ModelContext(reopened).fetch(FetchDescriptor<PrayerLog>()).first?.heart == nil)
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(try #require(cleared.undoToken).uuidString)]), issuedAt: now)
        #expect(try await second.execute(undo, now: now.addingTimeInterval(3)).status == .applied)
        let restored = try #require(try ModelContext(reopened).fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(restored.heart == "present" && restored.status == "jamaah")
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<QadaItem>()) == 0)
    }

    @Test func test_M0R04_distinctDuplicateReceiptNeverOverwritesLaterEdit() async throws {
        let (container, bus, _) = try fixture(), now = Date()
        let a = prayer(now: now), b = prayer(now: now)
        #expect(try await bus.execute(a, now: now).status == .applied)
        let firstRow = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        let stamp = firstRow.updatedAt
        #expect(try await bus.execute(b, now: now.addingTimeInterval(1)).status == .duplicate)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 2)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == stamp)
        #expect(try await bus.execute(prayer("alone", now: now.addingTimeInterval(2)), now: now.addingTimeInterval(2)).status == .applied)
        #expect(try await bus.execute(b, now: now.addingTimeInterval(3)).status == .duplicate)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
    }
    @Test func test_M0R05_replayBeforeTombstoneAndIdentityMismatch() async throws {
        let (container, bus, _) = try fixture(), now = Date()
        let a = prayer(now: now)
        let applied = try await bus.execute(a, now: now)
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(a.commandID.uuidString)]), issuedAt: now)
        #expect(try await bus.execute(undo, now: now.addingTimeInterval(1)).status == .applied)
        #expect(try await bus.execute(a, now: now.addingTimeInterval(2)) == applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.deletedAt != nil)
        let mismatch = try await bus.execute(prayer("alone", id: a.commandID, now: now), now: now.addingTimeInterval(3))
        #expect(mismatch.status == .rejected && mismatch.reason == "commandIdentityMismatch")
        let changedName = CommandEnvelope(commandID: a.commandID, name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark")])]), issuedAt: now)
        #expect(try await bus.execute(changedName, now: now).reason == "commandIdentityMismatch")
    }
    @Test func test_M0R06_onDiskExpiredReceiptReplaysAfterReopen() async throws {
        let (container, bus, directory) = try fixture(), now = Date()
        let a = prayer(now: now), b = prayer(now: now)
        _ = try await bus.execute(a, now: now)
        _ = try await bus.execute(b, now: now)
        _ = try await bus.execute(prayer("alone", now: now.addingTimeInterval(1)), now: now.addingTimeInterval(1))
        let reopened = try MadarContainerFactory.makeLocal(at: directory)
        let second = CommandBus(adapter: DurableCommandAdapter(container: reopened, lockDirectory: directory, transactionClock: { $0 }))
        #expect(try await second.execute(b, now: now.addingTimeInterval(8 * 86400)).status == .duplicate)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
    }
    @Test func test_M1T01_prayerChangeUndoAndFutureFridayGuard() async throws {
        let (container, bus, _) = try fixture(), now = Date()
        let first = prayer(now: now)
        #expect(try await bus.execute(first, now: now).status == .applied)
        let firstRow = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(firstRow.dayKey == prayerDay(now).description && firstRow.status == "jamaah")

        let changed = prayer("alone", now: now.addingTimeInterval(1))
        #expect(try await bus.execute(changed, now: now.addingTimeInterval(1)).status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "alone")
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(changed.commandID.uuidString)]), issuedAt: now.addingTimeInterval(2))
        #expect(try await bus.execute(undo, now: now.addingTimeInterval(2)).status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "jamaah")

        let tomorrow = prayerDay(now).adding(days: 1)
        let future = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string(tomorrow.description), "prayer": .string("fajr"), "status": .string("jamaah")]), source: .app, issuedAt: now)
        #expect(try await bus.execute(future, now: now).reason == "futurePrayer")

        let friday = previousFriday(before: prayerDay(now))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let dayAfterFriday = friday.adding(days: 1)
        #expect(calendar.component(.weekday, from: friday.date(in: calendar.timeZone)) == 6)
        #expect(calendar.component(.weekday, from: dayAfterFriday.date(in: calendar.timeZone)) == 7)
        let validFriday = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string(friday.description), "prayer": .string("dhuhr"), "status": .string("jamaah"), "fridayKind": .string("jumuah")]), source: .app, issuedAt: now)
        let fridayResult = try await bus.execute(validFriday, now: now)
        #expect(fridayResult.status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first(where: { $0.dayKey == friday.description && $0.prayer == "dhuhr" })?.fridayKind == "jumuah")
        let invalidFridayKind = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string(dayAfterFriday.description), "prayer": .string("fajr"), "status": .string("jamaah"), "fridayKind": .string("jumuah")]), source: .app, issuedAt: now)
        #expect(try await bus.execute(invalidFridayKind, now: now).reason == "invalidRecord")

        let jumuahAlone = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string(friday.description), "prayer": .string("dhuhr"), "status": .string("alone"), "fridayKind": .string("jumuah")]), source: .app, issuedAt: now)
        #expect(try await bus.execute(jumuahAlone, now: now).reason == "invalidRecord")
        let dhuhrAlone = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string(friday.description), "prayer": .string("dhuhr"), "status": .string("alone"), "fridayKind": .string("dhuhr")]), source: .app, issuedAt: now)
        #expect(try await bus.execute(dhuhrAlone, now: now).status == .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first(where: { $0.dayKey == friday.description && $0.prayer == "dhuhr" })?.fridayKind == "dhuhr")
    }
    @Test func test_M1T02_makeUpCommandIsAtomicIdempotentAndUndoable() async throws {
        let now = date("2026-10-13T09:00:00+03:00")
        let (container, bus, _) = try fixture(at: now)
        let context = ModelContext(container), dayKey = "2026-10-12"
        let missed = CommandEnvelope(name: "prayer.log", payload: .object([
            "dayKey": .string(dayKey), "prayer": .string("fajr"), "status": .string("missed")
        ]), source: .app, issuedAt: now)
        #expect(try await bus.execute(missed, now: now).status == .applied)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == nil)

        let makeUp = CommandEnvelope(name: "prayer.makeUp", payload: .object([
            "dayKey": .string(dayKey), "prayer": .string("fajr"), "at": .string(iso(now)), "fridayKind": .null
        ]), source: .app, issuedAt: now)
        let applied = try await bus.execute(makeUp, now: now)
        #expect(applied.status == .applied && applied.undoToken == makeUp.commandID)
        let log = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        let debt = try #require(context.fetch(FetchDescriptor<QadaItem>()).first)
        #expect(log.status == "qada" && debt.madeUpAt == now)
        let logStamp = log.updatedAt, debtStamp = debt.updatedAt

        let duplicate = CommandEnvelope(name: "prayer.makeUp", payload: makeUp.payload, source: .app, issuedAt: now.addingTimeInterval(1))
        #expect(try await bus.execute(duplicate, now: now.addingTimeInterval(1)).status == .duplicate)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == logStamp)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.updatedAt == debtStamp)

        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(makeUp.commandID.uuidString)]), issuedAt: now.addingTimeInterval(2))
        #expect(try await bus.execute(undo, now: now.addingTimeInterval(2)).status == .applied)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.status == "missed")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == nil)
    }

}
