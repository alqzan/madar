import XCTest
import SwiftData
import UIKit
import ImageIO
import MadarCore
@testable import MadarData
import MadarInbox
import MadarSnapshots
@testable import Madar

/// App-host coverage of the real session drain and backup lifecycle. Physical
/// notification delivery and @main foreground callbacks require separate checks.
@MainActor final class AppInboxLifecycleTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let managed: ManagedDataStore
        let session: AppSession
    }

    private func fixture() throws -> Fixture {
        // Never delete SQLite files while SwiftData owns handles. Synthetic stores
        // remain in the host's temporary directory until process exit.
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarAppInbox-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        // The fixed prayer day 2026-10-10 must fall inside tracking; a fresh store starts tracking today.
        let settings = ModelContext(managed.container)
        _ = try SettingsStore(context: settings).stage(["salah.trackingStart": .object(["dayKey": .string("2026-10-01"), "edits": .number(0)])])
        try settings.save()
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        XCTAssertTrue(UIApplication.shared.isProtectedDataAvailable, "App-host drain requires an unlocked device")
        return Fixture(root: root, managed: managed, session: session)
    }

    private func prayerCommand(source: CommandSource, prayer: Prayer = .fajr, status: String = "jamaah", issuedAt: Date = Date()) -> CommandEnvelope {
        CommandEnvelope(name: "prayer.log", payload: .object([
            "dayKey": .string("2026-10-10"), "prayer": .string(prayer.rawValue), "status": .string(status)
        ]), source: source, issuedAt: issuedAt)
    }

    private func record(_ command: CommandEnvelope, fixture: Fixture, generation: UUID? = nil) throws -> InboxRecord {
        InboxRecord(expectedGenerationID: generation ?? fixture.managed.binding.generationID, command: command)
    }

    private func deliveries(_ folder: String, fixture: Fixture) throws -> [URL] {
        let directory = fixture.session.pendingInbox.directory.appending(path: folder)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
    }

    private func receipts(_ fixture: Fixture) throws -> [MadarData.CommandReceipt] {
        try ModelContext(fixture.session.container).fetch(FetchDescriptor<MadarData.CommandReceipt>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
    }

    private func prayers(_ fixture: Fixture) throws -> [PrayerLog] {
        try ModelContext(fixture.session.container).fetch(FetchDescriptor<PrayerLog>())
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
    }

    private func assertAcknowledged(_ record: InboxRecord, fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let inbox = fixture.session.pendingInbox
        for folder in ["pending", "processing", "unresolved", "quarantine"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.directory.appending(path: "\(folder)/\(record.deliveryID).jsonl").path), file: file, line: line)
        }
        XCTAssertTrue(try inbox.wasCommitted(commandID: record.command.commandID, generationID: fixture.managed.binding.generationID), file: file, line: line)
    }

    private func waitForAcknowledgement(_ record: InboxRecord, fixture: Fixture) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let pending = fixture.session.pendingInbox.directory.appending(path: "pending/\(record.deliveryID).jsonl")
            let processing = fixture.session.pendingInbox.directory.appending(path: "processing/\(record.deliveryID).jsonl")
            if !FileManager.default.fileExists(atPath: pending.path),
               !FileManager.default.fileExists(atPath: processing.path),
               try fixture.session.pendingInbox.wasCommitted(commandID: record.command.commandID, generationID: fixture.managed.binding.generationID) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("resumeWriters did not acknowledge the queued delivery within five seconds")
    }

    func testNotificationAndWidgetLeaveNoFactUntilSessionDrainThenOneFactTwoReceipts() async throws {
        let fixture = try fixture()
        let issuedAt = Date()
        let notification = prayerCommand(source: .notification, issuedAt: issuedAt.addingTimeInterval(-1))
        let widget = prayerCommand(source: .widget, issuedAt: issuedAt)
        XCTAssertNotEqual(notification.commandID, widget.commandID)
        let first = try record(notification, fixture: fixture)
        let second = try record(widget, fixture: fixture)
        try fixture.session.pendingInbox.enqueue(first)
        try fixture.session.pendingInbox.enqueue(second)
        XCTAssertTrue(try prayers(fixture).isEmpty)
        XCTAssertTrue(try receipts(fixture).isEmpty)
        XCTAssertEqual(try deliveries("pending", fixture: fixture).count, 2)
        // Remove only this test's synthetic snapshot to prove the real refresh hook runs.
        try fixture.session.snapshotStore.remove("foundation")

        try await fixture.session.drainInbox()

        let rows = try prayers(fixture)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.status, "jamaah")
        XCTAssertEqual(rows.first?.source, "notification")
        let savedReceipts = try receipts(fixture)
        XCTAssertEqual(savedReceipts.count, 2)
        XCTAssertEqual(Set(savedReceipts.compactMap(\.commandID)), [notification.commandID, widget.commandID])
        XCTAssertEqual(savedReceipts.first { $0.commandID == notification.commandID }?.status, "applied")
        XCTAssertEqual(savedReceipts.first { $0.commandID == widget.commandID }?.status, "duplicate")
        try assertAcknowledged(first, fixture: fixture)
        try assertAcknowledged(second, fixture: fixture)
        XCTAssertTrue(try deliveries("pending", fixture: fixture).isEmpty)
        XCTAssertTrue(try deliveries("processing", fixture: fixture).isEmpty)
        let snapshot = try XCTUnwrap(fixture.session.snapshotStore.read("foundation", as: FoundationSnapshot.self))
        XCTAssertEqual(snapshot.payload.firstCalendar, fixture.session.string("core.firstCalendar"))
        XCTAssertEqual(snapshot.privacy, SnapshotPrivacy())
        XCTAssertFalse(fixture.session.protectedDataAuthorized)
    }

    func testSameCommandReplayThroughSessionPreservesFactReceiptAndRefreshesSnapshot() async throws {
        let fixture = try fixture()
        let command = prayerCommand(source: .notification)
        let first = try record(command, fixture: fixture)
        try fixture.session.pendingInbox.enqueue(first)
        try await fixture.session.drainInbox()
        let originalFact = try XCTUnwrap(try prayers(fixture).first).record()
        let originalReceipt = try XCTUnwrap(try receipts(fixture).first).record()
        let replay = try record(command, fixture: fixture)
        XCTAssertNotEqual(first.deliveryID, replay.deliveryID)
        try fixture.session.pendingInbox.enqueue(replay)
        try fixture.session.snapshotStore.remove("foundation")

        try await fixture.session.drainInbox()

        XCTAssertEqual(try prayers(fixture).count, 1)
        XCTAssertEqual(try receipts(fixture).count, 1)
        XCTAssertEqual(try XCTUnwrap(try prayers(fixture).first).record(), originalFact)
        XCTAssertEqual(try XCTUnwrap(try receipts(fixture).first).record(), originalReceipt)
        try assertAcknowledged(replay, fixture: fixture)
        XCTAssertNotNil(fixture.session.snapshotStore.read("foundation", as: FoundationSnapshot.self))
    }

    func testQuiescePausesInboxAndResumeWritersAutomaticallyDrains() async throws {
        let fixture = try fixture()
        try await fixture.session.quiesceWriters()
        let delivery = try record(prayerCommand(source: .widget), fixture: fixture)
        try fixture.session.pendingInbox.enqueue(delivery)

        try await fixture.session.drainInbox()

        XCTAssertTrue(fixture.session.maintenanceInProgress)
        XCTAssertTrue(try prayers(fixture).isEmpty)
        XCTAssertTrue(try receipts(fixture).isEmpty)
        XCTAssertEqual(try deliveries("pending", fixture: fixture).count, 1)
        XCTAssertTrue(try deliveries("processing", fixture: fixture).isEmpty)
        fixture.session.resumeWriters()
        // Do not call drainInbox here: this tests the real resume task.
        try await waitForAcknowledgement(delivery, fixture: fixture)
        XCTAssertFalse(fixture.session.maintenanceInProgress)
        XCTAssertNil(fixture.session.errorMessage)
        XCTAssertEqual(try prayers(fixture).count, 1)
        XCTAssertEqual(try receipts(fixture).count, 1)
        try assertAcknowledged(delivery, fixture: fixture)
    }

    func testActualBackupReplaceRetainsDeviceReceiptsAndResolvesOldGenerationDelivery() async throws {
        let fixture = try fixture()
        let session = fixture.session
        let backup = AppBackupService(session: session, store: fixture.managed, backupDirectory: fixture.root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        let first = try record(prayerCommand(source: .notification), fixture: fixture)
        try session.pendingInbox.enqueue(first)
        try await session.drainInbox()
        let originalGeneration = fixture.managed.binding.generationID
        let deviceStoreURL = fixture.managed.binding.deviceStoreURL
        ExportPrivacyTestHarness.install(on: session)
        let archive = try await backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        let correction = try record(prayerCommand(source: .widget, status: "alone"), fixture: fixture)
        try session.pendingInbox.enqueue(correction)
        try await session.drainInbox()
        try await waitForAcknowledgement(correction, fixture: fixture)
        XCTAssertEqual(try prayers(fixture).first?.status, "alone")
        let receiptIDs = Set(try receipts(fixture).compactMap(\.commandID))
        XCTAssertEqual(receiptIDs, [first.command.commandID, correction.command.commandID])
        let preview = try await backup.previewRestore(file: archive, passphrase: "test-only-passphrase", progress: { _ in })

        let restored = try await backup.restore(previewID: preview.id, mode: .replace, progress: { _ in })

        XCTAssertTrue(restored.warnings.isEmpty, restored.warnings.description)
        XCTAssertNotEqual(fixture.managed.binding.generationID, originalGeneration)
        XCTAssertEqual(fixture.managed.binding.deviceStoreURL, deviceStoreURL)
        XCTAssertEqual(Set(try receipts(fixture).compactMap(\.commandID)), receiptIDs)
        XCTAssertEqual(try prayers(fixture).count, 1)
        XCTAssertEqual(try prayers(fixture).first?.status, "jamaah")
        XCTAssertFalse(session.maintenanceInProgress)
        let active = try XCTUnwrap(try session.pendingInbox.currentGeneration())
        XCTAssertEqual(active.generationID, fixture.managed.binding.generationID)
        XCTAssertFalse(active.acceptsUnstampedDeliveries)
        XCTAssertNotNil(session.snapshotStore.read("foundation", as: FoundationSnapshot.self))

        // The producer accepted the original identity before replacement and delivers
        // it late. AppSession must preserve it for resolution, never apply it now.
        let stale = try record(prayerCommand(source: .notification, prayer: .dhuhr), fixture: fixture, generation: originalGeneration)
        try session.pendingInbox.enqueue(stale)
        try await session.drainInbox()
        // restore's resume task may already be draining; await its disposition too.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let unresolvedFile = session.pendingInbox.directory.appending(path: "unresolved/\(stale.deliveryID).jsonl")
        while !FileManager.default.fileExists(atPath: unresolvedFile.path), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let unresolved = try deliveries("unresolved", fixture: fixture)
        XCTAssertTrue(unresolved.contains { $0.lastPathComponent == "\(stale.deliveryID).jsonl" })
        XCTAssertTrue(try deliveries("pending", fixture: fixture).isEmpty)
        XCTAssertTrue(try deliveries("processing", fixture: fixture).isEmpty)
        XCTAssertEqual(try prayers(fixture).count, 1)
        XCTAssertEqual(Set(try receipts(fixture).compactMap(\.commandID)), receiptIDs)
        XCTAssertFalse(try session.pendingInbox.wasCommitted(commandID: stale.command.commandID, generationID: active.generationID))
        await backup.cancel()
    }
    func test_M0S1_RA4_CurrentReceiptScopeAndPendingTransportSurviveMigration() async throws {
        // Synthetic host data is retained until process exit; never remove open SQLite files.
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarV1Inbox-\(UUID())")
        let dataRoot = root.appending(path: "Data"), oldID = UUID(), receiptID = UUID()
        let generation = dataRoot.appending(path: "Generations/\(oldID.uuidString)")
        let command = prayerCommand(source: .notification)
        struct Scope: Codable { let version: Int; let generationID: UUID }
        func seedV1() throws -> [DataRecord] {
            try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
            let container = try ModelContainer(for: MadarSchemaV1.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV1.syncedTypes), url: generation.appending(path: "Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV1.deviceTypes), url: dataRoot.appending(path: "Device.store"), cloudKitDatabase: .none)
            ])
            let context = container.mainContext; context.autosaveEnabled = false
            let prayer = MadarSchemaV1.PrayerLog(); prayer.dayKey = "2026-10-10"; prayer.prayer = "fajr"; prayer.source = "notification"
            let money = MadarSchemaV1.Transaction(); money.amountMinor = 12345; money.dayKey = "2026-10-10"
            let receipt = MadarSchemaV1.CommandReceipt(); receipt.id = receiptID; receipt.commandID = command.commandID
            receipt.name = command.name; receipt.payloadHash = try command.payload.sha256(); receipt.source = "notification"
            receipt.issuedAt = command.issuedAt; receipt.expiresAt = Date().addingTimeInterval(-86400)
            let scope = MadarSchemaV1.DeviceSetting(); scope.key = "sys.commandReceiptScope:\(receiptID.uuidString)"
            scope.valueJSON = try JSONEncoder().encode(Scope(version: 1, generationID: oldID))
            context.insert(prayer); context.insert(money); context.insert(receipt); context.insert(scope); try context.save()
            let all = try LegacyRecordBridge.all(context, syncedOnly: false)
            try DurableFiles.encode(1, to: generation.appending(path: "SchemaVersion.json"))
            try DurableFiles.encode(1, to: dataRoot.appending(path: "DeviceSchemaVersion.json"))
            try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: try RecordFingerprint.hash(all.filter { MadarSchemaV1.syncedNames.contains($0.model) }), createdAt: Date()), to: generation.appending(path: "GenerationReady.json"))
            try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: dataRoot.appending(path: "ActiveGeneration.json"))
            return all.map { var row = $0; if row.model == "Transaction" { row.model = "MoneyTransaction" }; return row }
        }
        let expected = try seedV1()
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox"))
        try inbox.publishGeneration(.init(generationID: oldID, acceptsUnstampedDeliveries: false))
        let oldDelivery = InboxRecord(expectedGenerationID: oldID, command: command); try inbox.enqueue(oldDelivery)
        let managed = try ManagedDataStore(root: dataRoot, commandLockURL: root.appending(path: "CommandBus.lock"))
        XCTAssertNotEqual(managed.binding.generationID, oldID)
        let settings = ModelContext(managed.container)
        _ = try SettingsStore(context: settings).stage(["salah.trackingStart": .object(["dayKey": .string("2026-10-01"), "edits": .number(0)])])
        try settings.save()
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let fixture = Fixture(root: root, managed: managed, session: session)
        XCTAssertTrue(UIApplication.shared.isProtectedDataAvailable)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        let recoveryWarnings = try await backup.coordinator.recoverPendingLifecycle()
        XCTAssertTrue(recoveryWarnings.isEmpty, recoveryWarnings.description)
        let replay = try record(command, fixture: fixture); try inbox.enqueue(replay)
        try await session.drainInbox()
        XCTAssertEqual(Set(try deliveries("unresolved", fixture: fixture).map(\.lastPathComponent)), ["\(oldDelivery.deliveryID).jsonl", "\(replay.deliveryID).jsonl"])
        XCTAssertTrue(try deliveries("pending", fixture: fixture).isEmpty)
        XCTAssertTrue(try deliveries("processing", fixture: fixture).isEmpty)
        XCTAssertFalse(try inbox.wasCommitted(commandID: command.commandID, generationID: managed.binding.generationID))
        let rows = try RecordBridge.all(session.container.mainContext, syncedOnly: false)
        // Later additive optional fields (e.g. PrayerLog.fridayKind) arrive as null; every V1 field must survive unchanged.
        for original in expected {
            let migrated = rows.first { $0.model == original.model && $0.id == original.id }
            XCTAssertEqual(migrated?.fields.filter { original.fields[$0.key] != nil || $0.value != .null }, original.fields, original.model)
        }
        XCTAssertEqual(try receipts(fixture).count, 1); XCTAssertEqual(try prayers(fixture).count, 1)
        let fresh = try record(prayerCommand(source: .widget, prayer: .dhuhr), fixture: fixture)
        try inbox.enqueue(fresh); try await session.drainInbox(); try assertAcknowledged(fresh, fixture: fixture)
        let freshReceipt = try XCTUnwrap(try receipts(fixture).first { $0.commandID == fresh.command.commandID }).record()
        XCTAssertEqual(freshReceipt.fields["status"], .string("applied"))
        try inbox.enqueue(try record(fresh.command, fixture: fixture)); try await session.drainInbox()
        XCTAssertEqual(try receipts(fixture).count, 2); XCTAssertEqual(try prayers(fixture).count, 2)
        XCTAssertEqual(try XCTUnwrap(try receipts(fixture).first { $0.commandID == fresh.command.commandID }).record(), freshReceipt)
        let fingerprint = try RecordFingerprint.hash(RecordBridge.all(ModelContext(session.container), syncedOnly: false))
        let reopened = try ManagedDataStore(root: dataRoot, commandLockURL: root.appending(path: "CommandBus.lock"))
        XCTAssertEqual(reopened.binding.generationID, managed.binding.generationID)
        let resumed = try AppSession(container: reopened.container, managedStore: reopened, groupDirectory: root)
        try await resumed.drainInbox()
        XCTAssertEqual(try RecordFingerprint.hash(RecordBridge.all(ModelContext(resumed.container), syncedOnly: false)), fingerprint)
        XCTAssertEqual(try deliveries("unresolved", fixture: fixture).count, 2)
        XCTAssertNil(resumed.errorMessage)
    }

}

/// B1-17
final class TemporaryFilesCleanupTests: XCTestCase {
    func testOnlyOldItemsWithKnownNamesAreRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupFixture-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func make(_ name: String, age: TimeInterval) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        let oldBook = try make("\(UUID().uuidString).epub", age: 7200), freshBook = try make("\(UUID().uuidString).epub", age: 60)
        let oldImport = try make("MadarImport-\(UUID()).madarbackup", age: 7200), stranger = try make("someone-else.tmp", age: 7200)
        XCTAssertEqual(TemporaryFilesCleanup.run(in: root), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldBook.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: oldImport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshBook.path), "A recent file may still be in use")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path), "Unknown names are never touched")
    }
}

/// B1-13
final class DiaryCameraCopyTests: XCTestCase {
    func testCameraCopyKeepsTwoThousandPixelsWhileTheLibraryCopyStaysSmall() throws {
        let size = CGSize(width: 3000, height: 2000)
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let original = try XCTUnwrap(image.jpegData(compressionQuality: 0.82))
        func longEdge(_ data: Data) throws -> Int {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            return max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        XCTAssertEqual(try longEdge(XCTUnwrap(DiaryPhotoLibrary.cameraCopy(of: original))), 2048)
        XCTAssertEqual(try longEdge(XCTUnwrap(DiaryPhotoLibrary.smallCopy(of: original))), 640)
    }
}
