import Foundation
import CryptoKit
import SwiftData
import Testing
import MadarData
@testable import MadarSync

private enum TestFailure: Error { case snapshot }
private actor Accounts: CloudAccountProviding {
    var value: CloudAccount
    var calls = 0
    init(_ value: CloudAccount) { self.value = value }
    func account() async throws -> CloudAccount { calls += 1; return value }
    func replace(_ value: CloudAccount) { self.value = value }
    func count() -> Int { calls }
}
@MainActor private final class LifecycleProbe: SyncLifecycleAdapter {
    let manager: ManagedDataStore
    var preference = true
    var requests: [SyncActivationRequest] = []
    var suspensions = 0
    var saved: VerifiedSyncCheckpoint?
    var published: [Set<String>] = []
    init(_ manager: ManagedDataStore) { self.manager = manager }
    var binding: ManagedStoreBinding { manager.binding }
    var syncPreference: Bool { preference }
    func checkpointAndSuspend(reason: SyncTransitionReason) async throws -> VerifiedSyncCheckpoint {
        suspensions += 1
        let records = try RecordBridge.all(ModelContext(manager.container))
        let bytes = try BackupCodec.export(records: records, passphrase: "sync-local-test-credential")
        let verified = try BackupCodec.validate(bytes, passphrase: "sync-local-test-credential")
        #expect(Set(verified.records) == Set(records))
        let file = manager.root.appendingPathComponent("AccountCheckpoint.madarbackup")
        try bytes.write(to: file, options: .atomic)
        let checkpoint = VerifiedSyncCheckpoint(file: file, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), counts: verified.manifest.counts, generationID: binding.generationID)
        saved = checkpoint
        return checkpoint
    }
    // This probe captures decisions only. It deliberately never opens a cloud store.
    func activate(_ request: SyncActivationRequest) async throws { requests.append(request); preference = request.requestedDevicePreference }
    func withExclusiveStoreAccess<T>(_ action: (ModelContainer, ManagedStoreBinding) throws -> T) throws -> T { try action(manager.container, manager.binding) }
    func publishSnapshots(changedModels: Set<String>) throws { published.append(changedModels) }
}
@Suite(.serialized) @MainActor struct SyncTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("MadarSyncTests-\(UUID())", isDirectory: true) }
    private func prayer(_ context: ModelContext, status: String = "jamaah", at date: Date = Date()) throws {
        let row = PrayerLog(); row.dayKey = "2026-10-09"; row.prayer = "fajr"; row.status = status; row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight"; row.eventAt = date; row.updatedAt = date
        context.insert(row); try context.save()
    }
    @Test func persistentHistorySurvivesReopenAndFiltersOwnCursorWrites() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        var manager: ManagedDataStore? = try .init(root: directory)
        let generation = manager!.binding.generationID
        let writer = ModelContext(manager!.container); writer.author = "madar.command.widget"
        try prayer(writer)
        let history = HistoryProcessor()
        var models: Set<String> = []
        let first = try history.drain(container: manager!.container, generationID: generation) { models.formUnion($0) }
        #expect(first.transactions >= 1); #expect(models.contains("PrayerLog"))
        #expect(try history.drain(container: manager!.container, generationID: generation) { _ in }.transactions == 0)
        manager = nil
        let reopened = try ManagedDataStore(root: directory)
        #expect(try HistoryProcessor().drain(container: reopened.container, generationID: generation) { _ in }.transactions == 0)
        #expect(try ModelContext(reopened.container).fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count == 1)
    }
    @Test func failedSnapshotReplaysAndMergerHonorsStickyDeletion() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        let writer = ModelContext(manager.container); writer.author = "madar.command.notification"
        let deleted = PrayerLog(); deleted.dayKey = "2026-10-09"; deleted.prayer = "fajr"; deleted.deletedAt = Date(timeIntervalSince1970: 100); deleted.deletionBarrierAt = deleted.deletedAt; deleted.updatedAt = Date(timeIntervalSince1970: 100)
        let newer = PrayerLog(); newer.dayKey = deleted.dayKey; newer.prayer = deleted.prayer; newer.updatedAt = Date(timeIntervalSince1970: 200)
        writer.insert(deleted); writer.insert(newer); try writer.save()
        let history = HistoryProcessor()
        #expect(throws: TestFailure.snapshot) { try history.drain(container: manager.container, generationID: manager.binding.generationID) { _ in throw TestFailure.snapshot } }
        let replay = try history.drain(container: manager.container, generationID: manager.binding.generationID) { _ in }
        #expect(replay.transactions >= 1)
        let rows = try ModelContext(manager.container).fetch(FetchDescriptor<PrayerLog>())
        #expect(rows.filter { $0.deletedAt == nil && $0.mergedInto == nil }.isEmpty)
        #expect(try history.drain(container: manager.container, generationID: manager.binding.generationID) { _ in }.transactions == 0)
    }
    /// Owner 7 Nov 2026: a launch after a session that only wrote device rows no longer re-merges the whole store,
    /// while a synced change still merges duplicates exactly as before.
    @Test func deviceOnlyChangesAdvanceTheCursorWithoutMergingAndSyncedChangesStillMerge() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        let generation = manager.binding.generationID
        let history = HistoryProcessor()
        let writer = ModelContext(manager.container); writer.author = "madar.command.app"
        let visit = DeviceSetting(); visit.key = "sys.bahwReturnVisit"; visit.valueJSON = Data("{}".utf8); visit.updatedAt = Date()
        writer.insert(visit); try writer.save()
        let deviceOnly = try history.drain(container: manager.container, generationID: generation) { _ in }
        #expect(deviceOnly.transactions >= 1)
        #expect(deviceOnly.changedModels == ["DeviceSetting"])
        #expect(deviceOnly.reconciledRows == 0)
        #expect(try history.drain(container: manager.container, generationID: generation) { _ in }.transactions == 0)
        // Two live versions of one natural key: the synced change must still merge them into one.
        let older = PrayerLog(); older.dayKey = "2026-10-09"; older.prayer = "fajr"; older.status = "alone"; older.updatedAt = Date(timeIntervalSince1970: 100)
        let newer = PrayerLog(); newer.dayKey = "2026-10-09"; newer.prayer = "fajr"; newer.status = "jamaah"; newer.updatedAt = Date(timeIntervalSince1970: 200)
        writer.insert(older); writer.insert(newer); try writer.save()
        let synced = try history.drain(container: manager.container, generationID: generation) { _ in }
        #expect(synced.changedModels.contains("PrayerLog"))
        #expect(synced.reconciledRows >= 1)
        let live = try ModelContext(manager.container).fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        #expect(live.count == 1); #expect(live.first?.status == "jamaah")
    }
    @Test func corruptCursorAndNewGenerationRecoverWithoutSkippingData() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        let context = ModelContext(manager.container); context.author = "madar.command.app"; try prayer(context)
        let history = HistoryProcessor()
        _ = try history.drain(container: manager.container, generationID: manager.binding.generationID) { _ in }
        let cursor = try #require(context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.historyCursor.app" })
        cursor.valueJSON = Data("broken".utf8); try context.save()
        #expect(try history.drain(container: manager.container, generationID: manager.binding.generationID) { _ in }.cursorRecovered)
        let newGeneration = UUID()
        let reset = try history.drain(container: manager.container, generationID: newGeneration) { _ in }
        #expect(reset.cursorRecovered); #expect(reset.changedModels.contains("PrayerLog"))
        #expect(try history.drain(container: manager.container, generationID: newGeneration) { _ in }.transactions == 0)
    }
    @Test func unprovisionedDoesNotQueryCloudOrMutateLocalStore() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        try prayer(ModelContext(manager.container))
        let adapter = LifecycleProbe(manager); let accounts = Accounts(.available(hash: "unqueried"))
        let sync = SyncCoordinator(adapter: adapter, accountProvider: accounts, provisioning: .init(appGroupAvailable: true))
        await sync.refreshAccount()
        #expect(sync.health.phase == .localOnly); #expect(await accounts.count() == 0); #expect(adapter.requests.isEmpty); #expect(adapter.suspensions == 0)
        #expect(try RecordBridge.all(ModelContext(manager.container)).count == 1)
        #expect(sync.health.lastObservedImportAt == nil && sync.health.lastObservedExportAt == nil)
        _ = try sync.processHistory()
        #expect(sync.health.lastObservedImportAt == nil && sync.health.lastObservedExportAt == nil)
    }
    @Test func accountChoiceRequiresVerifiedBackupAndFreshDestination() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory, accountHash: "account-A")
        try prayer(ModelContext(manager.container))
        let device = DeviceSetting(); device.key = "sys.deviceSentinel"; device.valueJSON = Data("true".utf8); manager.container.mainContext.insert(device); try manager.container.mainContext.save()
        let adapter = LifecycleProbe(manager); let accounts = Accounts(.available(hash: "account-B"))
        let sync = SyncCoordinator(adapter: adapter, accountProvider: accounts, provisioning: .init(appGroupAvailable: true, verifiedEntitlements: true, cloudKitContainerIdentifier: "iCloud.test.probe"))
        await sync.refreshAccount()
        #expect(sync.health.phase == .waitingForAccountChoice); #expect(adapter.suspensions == 1); #expect(adapter.requests.isEmpty)
        let saved = try #require(sync.checkpoint); try saved.verifyFile(); #expect(saved.counts["PrayerLog"] == 1); #expect(saved.counts["DeviceSetting"] == nil)
        await accounts.replace(.available(hash: "account-C"))
        await #expect(throws: SyncFailure.unknownAccount) { try await sync.resolveAccountChange(.keepDevice) }
        #expect(adapter.requests.isEmpty); #expect(manager.binding.accountHash == "account-A")
        await accounts.replace(.available(hash: "account-B"))
        try await sync.resolveAccountChange(.useNewAccount)
        let decision = try #require(adapter.requests.last)
        #expect(decision.accountHash == "account-B" && decision.dataChoice == .useNewAccount && decision.checkpoint == saved)
        #expect(try ModelContext(manager.container).fetch(FetchDescriptor<DeviceSetting>()).contains { $0.key == "sys.deviceSentinel" })
        // The test verifies the decision boundary, not a real CloudKit rotation.
        #expect(!manager.isCloudBacked)
    }
    /// A store that has never met an account binds the first one without a choice or checkpoint,
    /// and stays local: turning sync on is a separate, explicit step.
    @Test func firstAccountBindsLocallyWithoutChoiceOrCheckpoint() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        try prayer(ModelContext(manager.container))
        let adapter = LifecycleProbe(manager); adapter.preference = true
        let sync = SyncCoordinator(adapter: adapter, accountProvider: Accounts(.available(hash: "account-A")), provisioning: .init(appGroupAvailable: true, verifiedEntitlements: true, cloudKitContainerIdentifier: "iCloud.test.probe"))
        await sync.refreshAccount()
        #expect(sync.health.phase == .localOnly); #expect(sync.pendingAccountHash == nil); #expect(adapter.suspensions == 0)
        let request = try #require(adapter.requests.first)
        #expect(adapter.requests.count == 1 && request.accountHash == "account-A" && !request.cloudEnabled && request.dataChoice == .keepDevice && request.checkpoint == nil)
        #expect(sync.observedAccount == .available(hash: "account-A"))
        #expect(try RecordBridge.all(ModelContext(manager.container)).count == 1)
    }
    @Test func returningToOriginalAccountReleasesPendingTransition() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory, accountHash: "account-A")
        let adapter = LifecycleProbe(manager); adapter.preference = false
        let accounts = Accounts(.available(hash: "account-B"))
        let sync = SyncCoordinator(adapter: adapter, accountProvider: accounts, provisioning: .init(appGroupAvailable: true, verifiedEntitlements: true, cloudKitContainerIdentifier: "iCloud.test.probe"))
        await sync.refreshAccount(); #expect(sync.pendingAccountHash == "account-B")
        await accounts.replace(.available(hash: "account-A")); await sync.refreshAccount()
        #expect(sync.pendingAccountHash == nil && sync.checkpoint == nil)
        #expect(adapter.requests.count == 1 && adapter.requests[0].accountHash == "account-A" && !adapter.requests[0].cloudEnabled)
    }
    @Test func sharedMaintenanceLeaseRejectsHistoryAccess() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let manager = try ManagedDataStore(root: directory)
        let adapter = ManagedSyncAdapter(manager: manager, checkpointAndSuspend: { _ in throw TestFailure.snapshot }, activate: { _ in }, publishSnapshots: { _ in })
        try Data("{}".utf8).write(to: directory.appendingPathComponent("StoreMaintenance.json"))
        #expect(throws: (any Error).self) { try adapter.withExclusiveStoreAccess { _, _ in } }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("StoreMaintenance.json"))
        #expect(try adapter.withExclusiveStoreAccess { _, binding in binding.generationID } == manager.binding.generationID)
    }
    @Test func checkpointTamperingFailsAndPreflightProtectsDeviceStore() throws {
        let directory = root(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("checkpoint"); let bytes = Data("sealed".utf8); try bytes.write(to: file)
        let checkpoint = VerifiedSyncCheckpoint(file: file, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), counts: [:], generationID: UUID())
        try checkpoint.verifyFile(); try Data("changed".utf8).write(to: file)
        #expect(throws: SyncFailure.invalidCheckpoint) { try checkpoint.verifyFile() }
        #expect(throws: SyncFailure.notProvisioned) { try SyncPreflight.validate(syncedDirectory: directory, deviceStoreURL: directory.appendingPathComponent("Device.store"), cloudRequested: true, provisioning: .init(appGroupAvailable: true)) }
        #expect(throws: SyncFailure.invalidPreflight) { try SyncPreflight.validate(syncedDirectory: directory, deviceStoreURL: directory.appendingPathComponent("Madar.store"), cloudRequested: false, provisioning: .init(appGroupAvailable: true)) }
    }
}
