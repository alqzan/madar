import XCTest
import SwiftData
import UIKit
import ImageIO
import MadarCore
@testable import MadarData
import MadarInbox
@testable import MadarCommands
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
        // Prayer logging is closed in production (17 Nov 2026); these inbox-lifecycle tests use the prayer handler as their vehicle.
        session.commandAdapter.prayerLoggingRetired = false
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

    func testRejectedActionsSurfaceAReadFailureAndCanBeReadAfterRecovery() async throws {
        let isolated = try fixture()
        let inbox = isolated.session.pendingInbox
        let quarantine = inbox.directory.appendingPathComponent("quarantine")
        let original = inbox.directory.appendingPathComponent("quarantine-test-original")
        let files = FileManager.default
        let delivery = try record(prayerCommand(source: .widget), fixture: isolated)
        _ = try inbox.enqueue(delivery)
        let claimed = try XCTUnwrap(try inbox.claimBatch().first)
        try inbox.quarantine(claimed, reason: "invalidCommand")
        let before = try await isolated.session.rejectedActions()
        XCTAssertEqual(before.count, 1)
        try files.moveItem(at: quarantine, to: original)
        try Data("temporary test obstruction".utf8).write(to: quarantine)
        do {
            _ = try await isolated.session.rejectedActions()
            XCTFail("A read failure must not look like an empty queue.")
        } catch {
            XCTAssertFalse(Task.isCancelled)
        }
        try files.removeItem(at: quarantine)
        try files.moveItem(at: original, to: quarantine)
        let recovered = try await isolated.session.rejectedActions()
        XCTAssertEqual(recovered.map(\.id), before.map(\.id))
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

    func testInterruptedBackupAndLegacyReadFoldersAreRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupFixture-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func makeFolder(_ name: String, age: TimeInterval) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("archive.aar"))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        let oldBackup = try makeFolder("MadarBackup-\(UUID())", age: 7200), freshBackup = try makeFolder("MadarBackup-\(UUID())", age: 60)
        let oldLegacy = try makeFolder("MadarLegacyRead-\(UUID())", age: 7200), stranger = try makeFolder("SomeoneElse-\(UUID())", age: 7200)
        XCTAssertEqual(TemporaryFilesCleanup.run(in: root), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldBackup.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: oldLegacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshBackup.path), "A backup in progress may still be using it")
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
