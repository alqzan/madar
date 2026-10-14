import XCTest
import SwiftData
import MadarCore
import MadarCommands
import MadarData
@testable import Madar

@MainActor final class CommandIntegrationTests: XCTestCase {
    // Leave synthetic stores in the simulator temporary directory until process exit.
    // Removing SQLite files while Core Data still owns handles violates its API contract.
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let container = try MadarContainerFactory.makeLocal(at: directory)
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory, transactionClock: { $0 })), directory)
    }
    func testNotificationAndWidgetUpsertProduceOneDurablePrayerLog() async throws {
        let (container, bus, directory) = try fixture()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-10T12:00:00+03:00"))
        let fixtureContext = ModelContext(container)
        _ = try SettingsStore(context: fixtureContext).stage(["salah.trackingStart": .object(["dayKey": .string("2026-10-10"), "edits": .number(0)])], now: now)
        try fixtureContext.save()
        let payload = MadarCore.JSONValue.object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("jamaah")])
        let notification = CommandEnvelope(name: "prayer.log", payload: payload, source: .notification, issuedAt: now)
        let initial = try await bus.execute(notification, now: now)
        XCTAssertEqual(initial.status, .applied)
        let widget = CommandEnvelope(name: "prayer.log", payload: payload, source: .widget, issuedAt: now)
        let repeated = try await bus.execute(widget, now: now)
        XCTAssertEqual(repeated.status, .duplicate)
        _ = try await bus.execute(notification, now: now)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PrayerLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 2)
        let reopened = try MadarContainerFactory.makeLocal(at: directory)
        let persisted = try ModelContext(reopened).fetch(FetchDescriptor<PrayerLog>())
        XCTAssertEqual(persisted.count, 1)
        let saved = try XCTUnwrap(persisted.first)
        XCTAssertEqual(saved.status, "jamaah")
        XCTAssertEqual(saved.dayPolicy, "prayerDay@1")
    }
    func testPresetUndoImmediateAndExpiresAtSixtySeconds() async throws {
        let (container, bus, _) = try fixture()
        let now = Date()
        let command = CommandEnvelope(name: "settings.applyPreset", payload: .object(["settings": .object(["core.theme": .string("dark")])]), issuedAt: now)
        let result = try await bus.execute(command, now: now)
        XCTAssertEqual(result.status, .applied)
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(command.commandID.uuidString)]), issuedAt: now)
        let undone = try await bus.execute(undo, now: now)
        XCTAssertEqual(undone.status, .applied)
        let fresh = try SettingsStore(context: ModelContext(container))
        XCTAssertEqual(try fresh.value(for: "core.theme"), .string("auto"))
        let second = CommandEnvelope(name: "settings.applyPreset", payload: command.payload, issuedAt: now)
        _ = try await bus.execute(second, now: now)
        let tooLate = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(second.commandID.uuidString)]), issuedAt: now.addingTimeInterval(60))
        let expired = try await bus.execute(tooLate, now: now.addingTimeInterval(60))
        XCTAssertEqual(expired.status, .rejected)
        let receipts = try ModelContext(container).fetch(FetchDescriptor<MadarData.CommandReceipt>())
        let receipt = try XCTUnwrap(receipts.first { $0.commandID == second.commandID })
        XCTAssertEqual(receipt.expiresAt.timeIntervalSince(now), 7 * 86400, accuracy: 0.01)
    }
    func testInvalidBatchRollsBackAndDeviceSettingNeverInSyncedStore() async throws {
        let (container, bus, _) = try fixture()
        let command = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark"), "core.hijriOffset": .number(99)])]))
        do { _ = try await bus.execute(command); XCTFail("invalid offset accepted") } catch {}
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DeviceSetting>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 0)
        let valid = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark")])]))
        _ = try await bus.execute(valid)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Setting>()), 0)
        let device = try ModelContext(container).fetch(FetchDescriptor<DeviceSetting>())
        XCTAssertEqual(device.filter { $0.key == "core.theme" }.count, 1)
        XCTAssertEqual(device.filter { $0.key == "sys.writerID" }.count, 1)
    }
    func testTwoIndependentAdaptersSerializeSameCommand() async throws {
        let (container, first, directory) = try fixture()
        let otherContainer = try MadarContainerFactory.makeLocal(at: directory)
        let second = CommandBus(adapter: DurableCommandAdapter(container: otherContainer, lockDirectory: directory, transactionClock: { $0 }))
        let command = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.firstCalendar": .string("gregorian")])]))
        async let a = first.execute(command)
        async let b = second.execute(command)
        _ = try await (a, b)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Setting>()), 1)
    }

    func testPresetDeadlineStartsAtApplicationTime() async throws {
        let (container, _, directory) = try fixture()
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory))
        let arrival = Date().addingTimeInterval(-30)
        let command = CommandEnvelope(name: "settings.applyPreset", payload: .object(["settings": .object(["core.theme": .string("dark")])]), issuedAt: arrival)
        let beforeApplication = Date()
        _ = try await bus.execute(command, now: arrival)
        let receipt = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<MadarData.CommandReceipt>()).first)
        XCTAssertGreaterThanOrEqual(receipt.createdAt, beforeApplication)
        XCTAssertEqual(try XCTUnwrap(receipt.undoExpiresAt).timeIntervalSince(receipt.createdAt), 60, accuracy: 0.001)
        XCTAssertEqual(receipt.expiresAt.timeIntervalSince(receipt.createdAt), 7 * 86400, accuracy: 0.001)
    }

    func testUndoCannotOverwriteLaterSettingOrLayoutEdit() async throws {
        let (container, bus, _) = try fixture()
        let now = Date()
        let schema = try SettingsSchema.bundled()
        let defaultLayout = try schema.definition(for: "bahw.layout").defaultValue
        let layout = try JSONDecoder().decode(MadarCore.JSONValue.self, from: defaultLayout.canonicalData())
        let preset = CommandEnvelope(name: "settings.applyPreset", payload: .object(["settings": .object(["core.theme": .string("dark")]), "layouts": .object(["bahw": layout])]), issuedAt: now)
        _ = try await bus.execute(preset, now: now)
        guard case .object(var changedLayout) = defaultLayout else { return XCTFail("layout fixture") }
        changedLayout["hidden"] = .array([.string("mal")])
        let changed = try JSONDecoder().decode(MadarCore.JSONValue.self, from: MadarData.JSONValue.object(changedLayout).canonicalData())
        let edit = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["bahw.layout": changed])]), issuedAt: now.addingTimeInterval(1))
        _ = try await bus.execute(edit, now: now.addingTimeInterval(1))
        let undo = CommandEnvelope(name: "system.undo", payload: .object(["undoToken": .string(preset.commandID.uuidString)]), issuedAt: now.addingTimeInterval(2))
        do { _ = try await bus.execute(undo, now: now.addingTimeInterval(2)); XCTFail("superseded undo accepted") } catch {}
        let store = try SettingsStore(context: ModelContext(container))
        XCTAssertEqual(try store.value(for: "core.theme"), .string("dark"))
        XCTAssertEqual(try store.value(for: "bahw.layout"), .object(changedLayout))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 2)
    }

    func testCommandResolvesActiveContainerAfterWaitingForLease() async throws {
        let (old, _, directory) = try fixture()
        let replacement = try MadarContainerFactory.makeLocal(at: directory.appending(path: "replacement"))
        var active = old
        var providerReads = 0
        let adapter = DurableCommandAdapter(containerProvider: { providerReads += 1; return active }, lockDirectory: directory)
        let bus = CommandBus(adapter: adapter)
        let lease = StoreLease(lockURL: directory.appending(path: "CommandBus.lock"))
        try lease.acquire()
        let transition = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(80))
            active = replacement
            lease.release()
        }
        let command = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.firstCalendar": .string("gregorian")])]))
        let outcome = try await bus.execute(command)
        try await transition.value
        XCTAssertEqual(outcome.status, .applied)
        XCTAssertEqual(providerReads, 1)
        XCTAssertEqual(try ModelContext(old).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 0)
        XCTAssertEqual(try ModelContext(replacement).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 1)
    }

    func testMaintenanceRejectsBeforeOpeningOrMutatingContainer() async throws {
        let (container, _, directory) = try fixture()
        var providerReads = 0
        let bus = CommandBus(adapter: DurableCommandAdapter(containerProvider: { providerReads += 1; return container }, lockDirectory: directory))
        let marker = StoreLease.maintenanceURL(lockURL: directory.appending(path: "CommandBus.lock"))
        try Data("active restore".utf8).write(to: marker, options: .atomic)
        defer { try? FileManager.default.removeItem(at: marker) }
        let command = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.firstCalendar": .string("gregorian")])]))
        do { _ = try await bus.execute(command); XCTFail("maintenance accepted a write") }
        catch { XCTAssertEqual(error as? BackupOperationError, .busy) }
        XCTAssertEqual(providerReads, 0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()), 0)
    }
}
