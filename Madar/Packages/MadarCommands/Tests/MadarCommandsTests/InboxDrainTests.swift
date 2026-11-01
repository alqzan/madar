import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
import MadarInbox
@testable import MadarCommands

@Suite(.serialized) @MainActor struct InboxDrainTests {
    private func fixture() throws -> (ModelContainer, DurableCommandAdapter, PendingInbox) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MadarDrainFixture-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: directory)
        let now = Date(), context = ModelContext(container), settings = try SettingsStore(context: context)
        let day = prayerDay(now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let daysSinceFriday = (calendar.component(.weekday, from: day.date(in: calendar.timeZone)) + 1) % 7
        _ = try settings.stage(["salah.trackingStart": .object(["dayKey": .string(day.adding(days: -(daysSinceFriday == 0 ? 7 : daysSinceFriday)).description), "edits": .number(0)])], now: now)
        try context.save()
        return (container, DurableCommandAdapter(container: container, lockDirectory: directory, transactionClock: { $0 }), PendingInbox(directory: directory.appending(path: "PendingInbox")))
    }
    private func prayer(id: UUID = UUID(), generation: UUID, now: Date = Date()) -> InboxRecord {
        .init(expectedGenerationID: generation, command: .init(commandID: id, name: "prayer.log", payload: .object(["dayKey": .string(prayerDay(now).description), "prayer": .string("fajr"), "status": .string("jamaah")]), source: .notification, issuedAt: now))
    }
    private func prayerDay(_ now: Date) -> GregorianDay {
        let place = try! ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        let civil = GregorianDay.containing(now, in: place.timeZone)
        guard let times = PrayerTimesEngine.calculate(day: civil, place: place) else { return civil }
        return now < times.fajr ? civil.adding(days: -1) : civil
    }
    @Test func test_M0R03_refreshFailureLeavesCommittedDeliveryAndRetryDoesNotMutate() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID(), record = prayer(generation: UUID())
        let stamped = InboxRecord(expectedGenerationID: generation, command: record.command)
        _ = try inbox.enqueue(stamped)
        var failRefresh = true, refreshes = 0
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {
            refreshes += 1
            if failRefresh { throw InboxError.io(5) }
        })
        await #expect(throws: InboxError.self) { try await drainer.drain() }
        let first = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt)
        #expect(try inbox.claimBatch().count == 1)
        failRefresh = false
        try await drainer.drain()
        #expect(try inbox.claimBatch().isEmpty)
        #expect(refreshes == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == first)
    }
    @Test func test_M0R03_malformedAndOldGenerationDoNotBlockNewCommands() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        _ = try inbox.enqueue(prayer(generation: UUID()))
        _ = try inbox.enqueue(prayer(generation: generation))
        try Data("invalid\n".utf8).write(to: inbox.directory.appending(path: "pending/\(UUID()).jsonl"))
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {})
        try await drainer.drain()
        #expect(drainer.needsWidgetHabitRefresh, "Quarantining an unreadable record releases fail-closed widget actions.")
        #expect(try inbox.claimBatch().isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "unresolved").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "quarantine").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
    }
    @Test func test_M0R06_pendingPinsExpiredReceiptAndAcknowledgedRetryIsUnresolvedAfterGC() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID(), now = Date()
        let record = prayer(generation: generation, now: now)
        _ = try inbox.enqueue(record)
        var fail = true
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: { if fail { throw InboxError.io(5) } })
        await #expect(throws: InboxError.self) { try await drainer.drain(now: now) }
        try adapter.purgeExpiredReceipts(pinnedIDs: inbox.unacknowledgedCommandIDs(), now: now.addingTimeInterval(8 * 86400))
        #expect(try adapter.hasReceipt(commandID: record.command.commandID))
        fail = false
        try await drainer.drain(now: now.addingTimeInterval(8 * 86400))
        try adapter.purgeExpiredReceipts(pinnedIDs: inbox.unacknowledgedCommandIDs(), now: now.addingTimeInterval(8 * 86400))
        #expect(!((try adapter.hasReceipt(commandID: record.command.commandID))))
        _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: record.command))
        try await drainer.drain(now: now.addingTimeInterval(9 * 86400))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "unresolved").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
    }
    @Test func test_M0R03_duplicateForegroundDrainsRunOneRefresh() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        _ = try inbox.enqueue(prayer(generation: generation))
        var refreshes = 0
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: { refreshes += 1; await Task.yield() })
        async let a = drainer.drain()
        async let b = drainer.drain()
        let outcomes = try await (a, b)
        #expect(outcomes.0 != outcomes.1)
        #expect(refreshes == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
    }
    @Test func test_M0R03_maintenanceAndProtectionFailureLeaveDeliveryRecoverable() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        _ = try inbox.enqueue(prayer(generation: generation))
        var unavailable = true
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {}, shouldPause: { unavailable })
        #expect(!(try await drainer.drain()))
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
        unavailable = false
        let marker = StoreLease.maintenanceURL(lockURL: adapter.lockDirectory.appending(path: "CommandBus.lock"))
        try Data("maintenance".utf8).write(to: marker, options: .atomic)
        await #expect(throws: BackupOperationError.busy) { try await drainer.drain() }
        #expect(try inbox.processingFiles().count == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
        try FileManager.default.removeItem(at: marker)
        #expect(try await drainer.drain())
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
    }
    @Test func test_M0R03_cancellationAfterSaveResumesBeforeAcknowledgement() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        _ = try inbox.enqueue(prayer(generation: generation))
        var entered = false, allowRefresh = false
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {
            entered = true
            while !allowRefresh { await Task.yield() }
        })
        let operation = Task { try await drainer.drain() }
        while !entered { await Task.yield() }
        operation.cancel(); allowRefresh = true
        do { _ = try await operation.value; Issue.record("cancelled drain unexpectedly acknowledged") }
        catch is CancellationError { }
        let stamp = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt)
        #expect(try inbox.processingFiles().count == 1)
        try await drainer.drain()
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == stamp)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
    }
    @Test func test_M0R03_restoreGenerationRejectsOldDeviceReceiptAndUnstampedDelivery() async throws {
        let (container, adapter, inbox) = try fixture(), old = UUID(), replacement = UUID()
        var active = old
        let record = prayer(generation: old)
        _ = try inbox.enqueue(record)
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: active, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {})
        try await drainer.drain()
        #expect(try adapter.hasReceipt(commandID: record.command.commandID))
        active = replacement
        _ = try inbox.enqueue(.init(expectedGenerationID: old, command: record.command))
        _ = try inbox.enqueue(.init(expectedGenerationID: nil, command: record.command))
        _ = try inbox.enqueue(prayer(generation: replacement))
        try await drainer.drain()
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "unresolved").path).filter { $0.hasSuffix(".jsonl") }.count == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 2)
        #expect(try inbox.processingFiles().isEmpty)
    }

    @Test func test_M0R03_spoofedAppSourceCannotDisableLockFromInbox() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        let bus = CommandBus(adapter: adapter)
        let protected = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.faceIDLock": .string("app")])]))
        _ = try await bus.execute(protected)
        let spoofed = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.faceIDLock": .string("none")])]), source: .app)
        _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: spoofed))
        var locked = true
        let drainer = InboxDrainer(inbox: inbox, bus: bus, generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {}, authorization: { command in
            command.name == "prayer.log" ? nil : .init(status: locked ? .needsUnlock : .needsApp)
        })
        try await drainer.drain()
        #expect(try SettingsStore(context: ModelContext(container)).value(for: "core.faceIDLock") == .string("app"))
        #expect(try inbox.processingFiles().count == 1)
        locked = false
        try await drainer.drain()
        #expect(try SettingsStore(context: ModelContext(container)).value(for: "core.faceIDLock") == .string("app"))
        #expect(!((try adapter.hasReceipt(commandID: spoofed.commandID))))
        _ = try inbox.enqueue(prayer(generation: generation))
        locked = true
        try await drainer.drain()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try inbox.processingFiles().count == 1)
    }

    @Test func test_M0S1_deliveryCollisionDoesNotBlockNeighbors() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        let first = prayer(generation: generation)
        _ = try inbox.enqueue(first)
        _ = try inbox.claimBatch()
        _ = try inbox.enqueue(first)
        let neighbor = prayer(generation: generation)
        _ = try inbox.enqueue(neighbor)
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {})
        try await drainer.drain()
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        // Same transport ID with conflicting command identity must preserve the accepted
        // original, reject only the payload mismatch, and let the valid command proceed.
        _ = try inbox.enqueue(first)
        _ = try inbox.claimBatch()
        let changed = CommandEnvelope(commandID: first.command.commandID, name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("alone")]), source: .widget)
        _ = try inbox.enqueue(.init(deliveryID: first.deliveryID, expectedGenerationID: generation, command: changed))
        try await drainer.drain()
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.status == "jamaah")
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "quarantine").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
    }

    @Test func test_M0S1_newGenerationCannotReplayOldReceipt() async throws {
        // Both a fully acknowledged save and an interrupted save-before-refresh retain
        // Device.store identity across a synthetic domain replacement.
        for interrupted in [false, true] {
            let (container, adapter, inbox) = try fixture(), old = UUID(), replacement = UUID()
            let first = prayer(generation: old)
            _ = try inbox.enqueue(first)
            var active = old, failRefresh = interrupted, refreshes = 0
            let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: active, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {
                if failRefresh { throw InboxError.io(5) }
                refreshes += 1
            })
            if interrupted { await #expect(throws: InboxError.self) { try await drainer.drain() } }
            else { try await drainer.drain() }
            #expect(try adapter.hasReceipt(commandID: first.command.commandID))
            #expect(try inbox.wasCommitted(commandID: first.command.commandID, generationID: old) == !interrupted)
            let context = ModelContext(container)
            for row in try context.fetch(FetchDescriptor<PrayerLog>()) { context.delete(row) }
            try context.save()
            active = replacement; failRefresh = false
            let stampedRetry = InboxRecord(expectedGenerationID: replacement, command: first.command)
            _ = try inbox.enqueue(stampedRetry)
            try await drainer.drain()
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
            #expect(try inbox.processingFiles().isEmpty)
            #expect(try inbox.unacknowledgedCommandIDs() == [first.command.commandID])
            #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "unresolved").path).filter { $0.hasSuffix(".jsonl") }.count == (interrupted ? 2 : 1))
            #expect(!((try inbox.wasCommitted(commandID: first.command.commandID, generationID: replacement))))
            #expect(refreshes == (interrupted ? 0 : 1))
        }
    }

    @Test func test_M0S1_inheritedReceiptWithoutGenerationRemainsUnresolved() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID(), first = prayer(generation: UUID())
        let receipt = MadarData.CommandReceipt()
        receipt.commandID = first.command.commandID; receipt.name = first.command.name
        receipt.payloadHash = try first.command.payload.sha256(); receipt.status = "applied"
        let context = ModelContext(container); context.insert(receipt); try context.save()
        _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: first.command))
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: { Issue.record("unknown receipt scope must not refresh") })
        try await drainer.drain()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
        #expect(try inbox.unacknowledgedCommandIDs() == [first.command.commandID])
        #expect(try inbox.processingFiles().isEmpty)
        #expect(!((try inbox.wasCommitted(commandID: first.command.commandID, generationID: generation))))
    }

    @Test func indexedReceiptScopesStillRejectDuplicateMalformedAndFutureScopes() async throws {
        for invalid in ["duplicate", "malformed", "future"] {
            let (container, adapter, _) = try fixture()
            let bus = CommandBus(adapter: adapter), command = prayer(generation: UUID()).command
            let initial = try await bus.execute(command)
            #expect(initial.status == .applied)
            let context = ModelContext(container)
            let receipt = try #require(try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).first { $0.commandID == command.commandID })
            let scope = try #require(try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.commandReceiptScope:\(receipt.id.uuidString)" })
            let original = scope.valueJSON
            var duplicate: DeviceSetting?
            if invalid == "duplicate" {
                let row = DeviceSetting(); row.key = scope.key; row.valueJSON = original; context.insert(row); duplicate = row
            } else if invalid == "malformed" { scope.valueJSON = Data("not JSON".utf8) }
            else {
                var value = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
                value["version"] = 2; scope.valueJSON = try JSONSerialization.data(withJSONObject: value)
            }
            try context.save()
            let rejected = try await bus.execute(command)
            #expect(rejected.status == .needsApp); #expect(rejected.reason == "receiptGenerationUnknown")
            #expect(try context.fetchCount(FetchDescriptor<PrayerLog>()) == 1)
            if let duplicate { duplicate.deletedAt = Date() } else { scope.valueJSON = original }
            try context.save()
            let recovered = try await bus.execute(command)
            #expect(recovered.status == initial.status)
            #expect(try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
        }
    }

    @Test func test_M0S1_scopedReceiptReopensAfterSaveBeforeRefresh() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID(), first = prayer(generation: UUID())
        _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: first.command))
        let interrupted = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: { throw InboxError.io(5) })
        await #expect(throws: InboxError.self) { try await interrupted.drain() }
        let stamp = try #require(try ModelContext(container).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt)
        #expect(!((try inbox.wasCommitted(commandID: first.command.commandID, generationID: generation))))
        let reopened = try MadarContainerFactory.makeLocal(at: adapter.lockDirectory)
        let restartedAdapter = DurableCommandAdapter(container: reopened, lockDirectory: adapter.lockDirectory, generationProvider: { generation })
        let restarted = InboxDrainer(inbox: PendingInbox(directory: inbox.directory), bus: CommandBus(adapter: restartedAdapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try restartedAdapter.hasReceipt(commandID: $0) }, refresh: {})
        try await restarted.drain()
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try ModelContext(reopened).fetch(FetchDescriptor<PrayerLog>()).first?.updatedAt == stamp)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
        #expect(try inbox.wasCommitted(commandID: first.command.commandID, generationID: generation))
    }

    @Test func test_M1T02_recoveryCommandsStayAppOnlyAndUnknownCommandsQuarantine() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID()
        for name in ["unknown.command", "prayer.makeUp", "prayer.resolveGap"] {
            _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: .init(name: name, payload: .object([:]), source: .widget)))
        }
        let appOnly = CommandEnvelope(name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark")])]), source: .widget)
        let locked = prayer(generation: generation), neighbor = prayer(generation: generation)
        for command in [appOnly, locked.command, neighbor.command] {
            _ = try inbox.enqueue(.init(expectedGenerationID: generation, command: command))
        }
        var unlocked = false
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {}, authorization: { command in
            #expect(command.name == "prayer.log")
            return command.commandID == locked.command.commandID && !unlocked ? .init(status: .needsUnlock) : nil
        })
        try await drainer.drain()
        #expect(try inbox.processingFiles().count == 4)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 1)
        let quarantined = try FileManager.default.contentsOfDirectory(at: inbox.directory.appending(path: "quarantine"), includingPropertiesForKeys: nil)
        #expect(quarantined.filter { $0.pathExtension == "jsonl" }.count == 1)
        for file in quarantined where file.pathExtension == "json" {
            let diagnostic = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            #expect(diagnostic.contains("invalidCommand"))
            #expect(!diagnostic.contains("unknown.command"))
        }
        unlocked = true
        try await drainer.drain()
        #expect(try inbox.processingFiles().count == 3)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 2)
        #expect(!((try adapter.hasReceipt(commandID: appOnly.commandID))))
    }

    @Test func test_M0S1_newGenerationCannotReplayCollectedReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarCollectedReceipt-\(UUID())")
        let managed = try ManagedDataStore(root: root)
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox"))
        let adapter = DurableCommandAdapter(containerProvider: { try managed.containerForTransaction() }, lockDirectory: root, transactionClock: { $0 }, generationProvider: { managed.binding.generationID })
        let oldGeneration = managed.binding.generationID, deviceStore = managed.binding.deviceStoreURL, now = Date()
        let first = prayer(generation: oldGeneration, now: now)
        var refreshes = 0
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: managed.binding.generationID, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: { refreshes += 1 })
        _ = try inbox.enqueue(first)
        try await drainer.drain(now: now)
        #expect(try inbox.wasCommitted(commandID: first.command.commandID, generationID: oldGeneration))
        try adapter.purgeExpiredReceipts(pinnedIDs: inbox.unacknowledgedCommandIDs(), now: now.addingTimeInterval(8 * 86400))
        #expect(!((try adapter.hasReceipt(commandID: first.command.commandID))))
        #expect(try ModelContext(managed.container).fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key.hasPrefix("sys.commandReceiptScope:") }.isEmpty)
        // Exercise the production staging/pointer switch with a fixed Device.store, rather
        // than deleting the fact by hand or changing only the drainer's generation closure.
        let coordinator = BackupCoordinator(store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        try await coordinator.configurePassphrase("correct long fixture password")
        _ = try await coordinator.rotateLocalStore(accountHash: nil, preservingCurrentRows: false)
        let replacement = managed.binding.generationID
        #expect(replacement != oldGeneration)
        #expect(managed.binding.deviceStoreURL == deviceStore)
        #expect(try ModelContext(managed.container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
        _ = try inbox.enqueue(.init(expectedGenerationID: replacement, command: first.command))
        try await drainer.drain(now: now.addingTimeInterval(9 * 86400))
        #expect(try ModelContext(managed.container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
        #expect(try ModelContext(managed.container).fetchCount(FetchDescriptor<MadarData.CommandReceipt>()) == 0)
        #expect(try inbox.processingFiles().isEmpty)
        #expect(try inbox.unacknowledgedCommandIDs() == [first.command.commandID])
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "unresolved").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
        #expect(!((try inbox.wasCommitted(commandID: first.command.commandID, generationID: replacement))))
        #expect(refreshes == 1)
        let fresh = prayer(generation: replacement, now: now.addingTimeInterval(9 * 86400))
        _ = try inbox.enqueue(fresh)
        try await drainer.drain(now: now.addingTimeInterval(9 * 86400))
        #expect(try ModelContext(managed.container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try adapter.hasReceipt(commandID: fresh.command.commandID))
        #expect(!((try adapter.hasReceipt(commandID: first.command.commandID))))
        #expect(try inbox.unacknowledgedCommandIDs() == [first.command.commandID])
        #expect(refreshes == 2)
    }

    /// M4-F01: a Shortcut habit completion whose period closed before the drain is refused and
    /// quarantined; it must not block the valid completion and the prayer queued after it.
    @Test func test_M4F01_staleHabitCompletionDoesNotBlockLaterCommands() async throws {
        let (container, adapter, inbox) = try fixture(), generation = UUID(), now = Date()
        let bus = CommandBus(adapter: adapter), habit = UUID()
        var rule = HabitRule(effectiveFrom: prayerDay(now)); rule.measure = .count; rule.target = 2
        let ruleJSON = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(rule))
        #expect(try await bus.execute(.init(name: "habit.save", payload: .object(["id": .string(habit.uuidString), "name": .string("ماء"), "rule": ruleJSON]), issuedAt: now), now: now).status == .applied)
        let period = try #require(try HabitRepository(context: ModelContext(container)).readings(at: now).first?.summary.current?.key)
        try inbox.publishGeneration(.init(generationID: generation, acceptsUnstampedDeliveries: false))
        try HabitInboxCommandWriter.complete(inbox: inbox, habitID: habit, delta: 1, periodKey: "2000-01-01", source: .shortcut, issuedAt: now.addingTimeInterval(-3))
        try HabitInboxCommandWriter.complete(inbox: inbox, habitID: habit, delta: 1, periodKey: period, source: .shortcut, issuedAt: now.addingTimeInterval(-2))
        _ = try inbox.enqueue(prayer(generation: generation, now: now))
        // Without a period, an outside completion is refused before it can be credited to the drain day.
        let unscoped = try await bus.execute(.init(name: "habit.complete", payload: .object(["id": .string(habit.uuidString)]), source: .widget, issuedAt: now), now: now)
        #expect(unscoped.status == .rejected)
        let drainer = InboxDrainer(inbox: inbox, bus: bus, generation: { .init(generationID: generation, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {})
        try await drainer.drain()
        #expect(drainer.needsWidgetHabitRefresh, "Applied and terminally rejected deliveries both release the snapshot action after the drain.")
        #expect(try inbox.claimBatch().isEmpty)
        #expect(try HabitRepository(context: ModelContext(container)).readings(at: now).first?.summary.current?.value == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.directory.appending(path: "quarantine").path).filter { $0.hasSuffix(".jsonl") }.count == 1)
    }
}
