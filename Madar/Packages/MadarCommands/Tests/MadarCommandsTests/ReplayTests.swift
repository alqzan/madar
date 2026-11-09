import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
import MadarPrayer
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
    @Test func prayerCanBeLoggedAgainAfterUndo() async throws {
        let now = date("2026-10-15T12:00:00+03:00")
        let (container, bus, directory) = try fixture(at: now)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = prayerDay(now)
        let payload: [String: MadarCore.JSONValue] = ["dayKey": .string(day.description), "prayer": .string("fajr"), "status": .string("jamaah")]
        func log(_ commandID: UUID) -> CommandEnvelope { .init(commandID: commandID, name: "prayer.log", payload: .object(payload), issuedAt: now) }

        let firstCommand = UUID(), first = try await bus.execute(log(firstCommand), now: now)
        #expect(first.status == .applied)
        #expect(try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(firstCommand.uuidString)]), issuedAt: now.addingTimeInterval(1)), now: now.addingTimeInterval(1)).status == .applied)

        let pending = try #require(try PrayerRepository(context: ModelContext(container)).day(day, now: now.addingTimeInterval(2)).cells.first { $0.reference.prayer == .fajr })
        #expect(pending.status == .pending)
        let secondCommand = UUID()
        let second = try await bus.execute(log(secondCommand), now: now.addingTimeInterval(3))
        #expect(second.status == .applied, "A fresh prayer log after undo must restore the natural-key row.")

        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(row.id == StableIdentity.uuid(for: "PrayerLog:\(day):fajr"))
        #expect(row.deletedAt == nil && row.restoredAt != nil && row.restoredAt! > row.deletionBarrierAt!)
        #expect(row.status == "jamaah")
        let recorded = try #require(try PrayerRepository(context: ModelContext(container)).day(day, now: now.addingTimeInterval(4)).cells.first { $0.reference.prayer == .fajr })
        #expect(recorded.status == .jamaah)
    }
    @Test func qadaCanBeLoggedAgainAfterUndo() async throws {
        let now = date("2026-10-15T15:00:00+03:00")
        let (container, bus, directory) = try fixture(at: now)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = prayerDay(now)
        let payload: [String: MadarCore.JSONValue] = ["dayKey": .string(day.description), "prayer": .string("fajr"), "status": .string("qada")]
        func log(_ commandID: UUID) -> CommandEnvelope { .init(commandID: commandID, name: "prayer.log", payload: .object(payload), issuedAt: now) }

        let firstCommand = UUID()
        #expect(try await bus.execute(log(firstCommand), now: now).status == .applied)
        #expect(try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(firstCommand.uuidString)]), issuedAt: now.addingTimeInterval(1)), now: now.addingTimeInterval(1)).status == .applied)

        let pending = try #require(try PrayerRepository(context: ModelContext(container)).day(day, now: now.addingTimeInterval(2)).cells.first { $0.reference.prayer == .fajr })
        #expect(pending.status == .pending)
        let secondCommand = UUID()
        #expect(try await bus.execute(log(secondCommand), now: now.addingTimeInterval(3)).status == .applied)
        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(row.status == "qada" && row.deletedAt == nil && row.restoredAt! > row.deletionBarrierAt!)
        #expect(try ModelContext(container).fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func retiredBacklogCommandsCannotCreatePrayerOrDebtRows() async throws {
        let now = date("2026-10-08T09:00:00+03:00")
        let (container, bus, directory) = try fixture(at: now)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload: [String: MadarCore.JSONValue] = ["dayKey": .string("2026-10-02"), "prayer": .string("dhuhr"), "status": .string("missed")]
        for name in ["prayer.addOldMissed", "prayer.makeUp", "prayer.markUnrecorded", "prayer.addOldMissedRun", "prayer.makeUpOldest", "prayer.resolveGap"] {
            let result = try await bus.execute(.init(name: name, payload: .object(payload), source: .app, issuedAt: now), now: now)
            #expect(result.status == .rejected, "Retired prayer backlog command was accepted: \(name)")
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func test_M1T07_QiyamMidnightReplayUndoAndExplicitRestoration() async throws {
        // P05 golden: Oct 7 at 23:30 and Oct 8 at 02:10 belong to night 2026-10-07.
        let late = date("2026-10-07T23:30:00+03:00"), early = date("2026-10-08T02:10:00+03:00")
        let (container, bus, _) = try fixture(at: late)
        func command(_ night: String = "2026-10-07", rakaat: Double = 8, restore: Bool = false, source: CommandSource = .app, at: Date) -> CommandEnvelope {
            .init(name: "prayer.logQiyam", payload: .object(["nightKey": .string(night), "rakaat": .number(rakaat), "witr": .bool(true), "restoreDeleted": .bool(restore)]), source: source, issuedAt: at)
        }
        let first = command(at: late)
        let result = try await bus.execute(first, now: late)
        #expect(result.status == .applied && result.undoToken != nil)
        #expect(try await bus.execute(first, now: early) == result)
        #expect(try await bus.execute(command(at: early), now: early).status == .duplicate)
        let context = ModelContext(container)
        var rows = try context.fetch(FetchDescriptor<QiyamNight>())
        #expect(rows.count == 1 && rows[0].nightKey == "2026-10-07" && rows[0].rakaat == 8 && rows[0].witr)
        #expect(rows[0].quranSessionID == nil)
        #expect(try context.fetchCount(FetchDescriptor<HifzSession>()) == 0)
        #expect(try await bus.execute(command("2026-10-08", at: early), now: early).reason == "invalidNight")
        #expect(try await bus.execute(command("2026-09-30", at: early), now: early).reason == "invalidNight")
        #expect(try await bus.execute(command(rakaat: 8.5, at: early), now: early).reason == "invalidPayload")
        #expect(try await bus.execute(command(rakaat: 100, at: early), now: early).reason == "invalidPayload")
        #expect(try await bus.execute(command(source: .widget, at: early), now: early).status == .needsApp)
        // New insertion undo is a tombstone. A normal save must never resurrect it.
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(try #require(result.undoToken).uuidString)]), issuedAt: late)
        #expect(try await bus.execute(undo, now: late.addingTimeInterval(1)).status == .applied)
        #expect(try await bus.execute(command(at: late.addingTimeInterval(2)), now: late.addingTimeInterval(2)).reason == "explicitRestoreRequired")
        #expect(try await bus.execute(command(restore: true, at: late.addingTimeInterval(3)), now: late.addingTimeInterval(3)).status == .applied)
        rows = try ModelContext(container).fetch(FetchDescriptor<QiyamNight>())
        #expect(rows.count == 1 && rows[0].deletedAt == nil)
        #expect(try #require(rows[0].restoredAt) > #require(rows[0].deletionBarrierAt))
        #expect(rows[0].rakaat == 8 && rows[0].witr && rows[0].quranSessionID == nil)
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
    @Test func performedLatePrayerCommandLogsQadaWithoutDebtAndUndoRemovesIt() async throws {
        let now = date("2026-10-13T09:00:00+03:00")
        let (container, bus, directory) = try fixture(at: now)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = ModelContext(container)
        let command = CommandEnvelope(name: "prayer.log", payload: .object([
            "dayKey": .string("2026-10-12"), "prayer": .string("fajr"), "status": .string("qada")
        ]), source: .app, issuedAt: now)
        let applied = try await bus.execute(command, now: now)
        #expect(applied.status == .applied && applied.undoToken == command.commandID)
        let row = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(row.status == "qada" && row.eventAt == now && row.loggedAt == now)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        // The same envelope again replays its stored receipt; a fresh envelope with the same payload is a natural-key duplicate. Neither adds a row.
        #expect(try await bus.execute(command, now: now.addingTimeInterval(1)).status == .applied)
        let resent = CommandEnvelope(name: command.name, payload: command.payload, source: .app, issuedAt: now.addingTimeInterval(1))
        #expect(try await bus.execute(resent, now: now.addingTimeInterval(1)).status == .duplicate)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil }.count == 1)

        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(command.commandID.uuidString)]), issuedAt: now.addingTimeInterval(2))
        #expect(try await bus.execute(undo, now: now.addingTimeInterval(2)).status == .applied)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        let retiredMakeUp = CommandEnvelope(name: "prayer.makeUp", payload: .object(["dayKey": .string("2026-10-12"), "prayer": .string("fajr")]), issuedAt: now.addingTimeInterval(3))
        #expect(try await bus.execute(retiredMakeUp, now: now.addingTimeInterval(3)).status == .rejected)
    }
}
