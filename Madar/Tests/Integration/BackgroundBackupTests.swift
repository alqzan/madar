import XCTest
import SwiftData
import MadarData
@testable import Madar

@MainActor final class BackgroundBackupTests: XCTestCase {
    private func fixture(progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }) async throws -> (AppSession, AppBackupService) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundBackup-" + UUID().uuidString)
        let store = try ManagedDataStore(root: root.appendingPathComponent("Data"))
        let session = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        let service = AppBackupService(session: session, store: store, backupDirectory: root.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore(), scheduledProgress: progress)
        session.backupService = service
        return (session, service)
    }
    func testScheduleRequiresKeyAndFollowsLastSuccessfulBackup() async throws {
        let (session, service) = try await fixture()
        let scheduler = FakeBackupScheduler()
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) { service }
        runner.register(); runner.register()
        XCTAssertEqual(scheduler.registrations, 1)
        await runner.reschedule(using: service)
        XCTAssertNil(scheduler.pending)
        try await service.coordinator.configurePassphrase("synthetic long password")
        let now = Date()
        let receipt = try await service.coordinator.export(kind: .manual, now: now)
        try await session.applySettingsAndWait(["core.backup": .string("daily")])
        XCTAssertEqual(try service.nextBackgroundBackupDate(now: now), receipt.createdAt.addingTimeInterval(86_400))
        await runner.reschedule(using: service)
        XCTAssertEqual(scheduler.pending, receipt.createdAt.addingTimeInterval(86_400))
        try await session.applySettingsAndWait(["core.backup": .string("weekly")])
        XCTAssertEqual(try service.nextBackgroundBackupDate(now: now), receipt.createdAt.addingTimeInterval(604_800))
        try await session.applySettingsAndWait(["core.backup": .string("manual")])
        await runner.reschedule(using: service)
        XCTAssertNil(scheduler.pending)
    }
    func testColdLaunchCreatesOneEncryptedBackupAndRepeatIsNotDue() async throws {
        let (session, service) = try await fixture()
        try await service.coordinator.configurePassphrase("synthetic long password")
        try await session.applySettingsAndWait(["core.backup": .string("daily")])
        let scheduler = FakeBackupScheduler()
        var loads = 0
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) { loads += 1; return service }
        service.backgroundTasks = runner
        runner.register()
        let first = FakeBackupTask(); scheduler.launch?(first)
        await fulfillment(of: [first.finished], timeout: 30)
        XCTAssertEqual(first.results, [true]); XCTAssertEqual(loads, 1)
        let receipt = try XCTUnwrap(service.coordinator.catalog().first)
        XCTAssertEqual(receipt.kind, .automatic)
        let preview = try await service.coordinator.preview(file: receipt.fileURL, passphrase: "synthetic long password")
        XCTAssertEqual(preview.counts, receipt.counts)
        XCTAssertEqual(scheduler.pending, receipt.createdAt.addingTimeInterval(86_400))
        let second = FakeBackupTask(); scheduler.launch?(second)
        await fulfillment(of: [second.finished], timeout: 10)
        XCTAssertEqual(second.results, [true]); XCTAssertEqual(try service.coordinator.catalog().count, 1)
        XCTAssertFalse(session.maintenanceInProgress)
    }
    func testExpirationWhileLoadingKeepsPreviousBackupAndCompletesOnce() async throws {
        let (session, service) = try await fixture()
        try await service.coordinator.configurePassphrase("synthetic long password")
        let previous = try await service.coordinator.export(kind: .manual)
        let bytes = try Data(contentsOf: previous.fileURL)
        let scheduler = FakeBackupScheduler(), entered = expectation(description: "cold load started")
        var release: CheckedContinuation<Void, Never>?
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) {
            await withCheckedContinuation { release = $0; entered.fulfill() }
            return service
        }
        runner.register()
        let task = FakeBackupTask(); scheduler.launch?(task)
        await fulfillment(of: [entered], timeout: 5)
        let duplicate = FakeBackupTask(); scheduler.launch?(duplicate)
        XCTAssertEqual(duplicate.results, [false])
        task.expiration?(); release?.resume()
        await fulfillment(of: [task.finished], timeout: 10)
        XCTAssertEqual(task.results, [false]); XCTAssertNil(task.expiration)
        XCTAssertEqual(try service.coordinator.catalog().map(\.id), [previous.id])
        XCTAssertEqual(try Data(contentsOf: previous.fileURL), bytes)
        XCTAssertFalse(session.maintenanceInProgress)
    }
    func testExpirationWhileWritingRemovesPartialAndPreservesPreviousReceipt() async throws {
        let writing = expectation(description: "automatic backup reached file writing")
        let gate = DispatchSemaphore(value: 0)
        let (session, service) = try await fixture { update in
            if update.phase == .writing {
                writing.fulfill()
                _ = gate.wait(timeout: .now() + 10)
            }
        }
        try await service.coordinator.configurePassphrase("synthetic long password")
        let previous = try await service.coordinator.export(kind: .manual, now: .now.addingTimeInterval(-2 * 86_400))
        let bytes = try Data(contentsOf: previous.fileURL)
        try await session.applySettingsAndWait(["core.backup": .string("daily")])
        let scheduler = FakeBackupScheduler()
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) { service }
        service.backgroundTasks = runner; runner.register()
        let task = FakeBackupTask(); scheduler.launch?(task)
        await fulfillment(of: [writing], timeout: 15)
        task.expiration?(); gate.signal()
        await fulfillment(of: [task.finished], timeout: 15)
        XCTAssertEqual(task.results, [false])
        XCTAssertEqual(try service.coordinator.catalog().map(\.id), [previous.id])
        XCTAssertEqual(try Data(contentsOf: previous.fileURL), bytes)
        XCTAssertEqual(try service.coordinator.status().lastResult, "cancelled")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: service.coordinator.backupDirectory.path).allSatisfy { !$0.hasSuffix(".partial") })
        XCTAssertFalse(session.maintenanceInProgress)
        XCTAssertNotNil(scheduler.pending)
    }
    func testDisablingDuringAsyncSubmissionRemovesStaleRequest() async throws {
        let (session, service) = try await fixture()
        try await service.coordinator.configurePassphrase("synthetic long password")
        try await session.applySettingsAndWait(["core.backup": .string("daily")])
        let scheduler = FakeBackupScheduler(), entered = expectation(description: "submission started")
        var release: CheckedContinuation<Void, Never>?
        scheduler.onSubmit = { await withCheckedContinuation { release = $0; entered.fulfill() } }
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) { service }
        service.backgroundTasks = runner; runner.register()
        let submission = Task { await runner.reschedule(using: service) }
        await fulfillment(of: [entered], timeout: 5)
        try await service.setSchedule(.manual)
        release?.resume(); await submission.value
        XCTAssertNil(scheduler.pending)
    }
    func testFailedColdLoadSchedulesRetryWithoutClaimingSuccess() async {
        let scheduler = FakeBackupScheduler(), before = Date()
        let runner = AppBackupBackgroundTasks(scheduler: scheduler) { throw BackupOperationError.busy }
        runner.register()
        let task = FakeBackupTask(); scheduler.launch?(task)
        await fulfillment(of: [task.finished], timeout: 5)
        XCTAssertEqual(task.results, [false])
        XCTAssertGreaterThanOrEqual(scheduler.pending ?? .distantPast, before.addingTimeInterval(3600))
    }
    func testAppDeclaresOnlyItsProcessingIdentifier() {
        let bundle = Bundle(for: AppSession.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], [AppBackupBackgroundTasks.identifier])
        XCTAssertTrue((bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("processing"))
    }
}

@MainActor private final class FakeBackupScheduler: BackupBackgroundScheduling {
    var registrations = 0
    var pending: Date?
    var launch: (@MainActor (any BackupBackgroundTask) -> Void)?
    var onSubmit: (@MainActor () async -> Void)?
    func register(_ launch: @escaping @MainActor (any BackupBackgroundTask) -> Void) -> Bool {
        registrations += 1; self.launch = launch; return true
    }
    func submit(earliest: Date) async throws { await onSubmit?(); pending = earliest }
    func cancel() { pending = nil }
}
@MainActor private final class FakeBackupTask: BackupBackgroundTask {
    var expiration: (@Sendable () -> Void)?
    var results: [Bool] = []
    let finished = XCTestExpectation(description: "background task completed")
    func setExpirationHandler(_ handler: (@Sendable () -> Void)?) { expiration = handler }
    func complete(success: Bool) { results.append(success); finished.fulfill() }
}
