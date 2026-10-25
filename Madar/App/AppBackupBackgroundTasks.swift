import BackgroundTasks
import Foundation
import MadarData

@MainActor protocol BackupBackgroundTask: AnyObject {
    func setExpirationHandler(_ handler: (@Sendable () -> Void)?)
    func complete(success: Bool)
}

@MainActor protocol BackupBackgroundScheduling: AnyObject {
    func register(_ launch: @escaping @MainActor (any BackupBackgroundTask) -> Void) -> Bool
    func submit(earliest: Date) async throws
    func cancel()
}

/// Only the application delegate registers this task. Cold launches use the same
/// runtime/store as the scene; no extension or secondary container opens records.
@MainActor final class AppBackupBackgroundTasks {
    static let identifier = "com.alqzan.madar2.backup"
    private let scheduler: any BackupBackgroundScheduling
    private let loadService: @MainActor () async throws -> AppBackupService
    private var registered = false
    private var registrationAttempted = false
    private var active: Task<Void, Never>?
    private weak var currentService: AppBackupService?
    private var scheduleRevision = 0
    private var scheduling = false

    init(scheduler: any BackupBackgroundScheduling = SystemBackupBackgroundScheduler(),
         loadService: @escaping @MainActor () async throws -> AppBackupService) {
        self.scheduler = scheduler; self.loadService = loadService
    }
    func register() {
        guard !registrationAttempted else { return }
        registrationAttempted = true
        registered = scheduler.register { [weak self] task in self?.launch(task) }
    }
    /// Serialize OS submissions. A changed/undone setting during an asynchronous
    /// submission is read again afterwards, so an old daily request cannot win.
    func reschedule(using service: AppBackupService) async {
        guard registered else { return }
        currentService = service; scheduleRevision += 1
        guard !scheduling else { return }
        scheduling = true
        defer { scheduling = false }
        while let service = currentService {
            let revision = scheduleRevision
            do {
                if let next = try service.nextBackgroundBackupDate() { try await scheduler.submit(earliest: next) }
                else { scheduler.cancel() }
            } catch { /* Foreground catch-up remains available; retry next activation. */ }
            if revision == scheduleRevision { break }
        }
    }
    private func launch(_ task: any BackupBackgroundTask) {
        guard active == nil else { task.complete(success: false); return }
        let cancellation = BackupCancellation()
        let work = Task { @MainActor [self] in
            var success = false
            defer {
                task.setExpirationHandler(nil)
                task.complete(success: success)
                active = nil
            }
            do {
                let service = try await loadService()
                try cancellation.check()
                // Re-arm before capture as well, in case iOS terminates this run.
                await reschedule(using: service)
                try cancellation.check()
                try await service.runScheduledBackup(cancellation: cancellation)
                try cancellation.check()
                success = true
            } catch {
                if let service = currentService { await reschedule(using: service) }
                else { try? await scheduler.submit(earliest: .now.addingTimeInterval(3600)) }
            }
        }
        active = work
        task.setExpirationHandler { cancellation.cancel(); work.cancel() }
    }
}

@MainActor private final class SystemBackupBackgroundScheduler: BackupBackgroundScheduling {
    func register(_ launch: @escaping @MainActor (any BackupBackgroundTask) -> Void) -> Bool {
        #if DEBUG
        // Test stores must not change this installation's real pending requests.
        if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #endif
        return BGTaskScheduler.shared.register(forTaskWithIdentifier: AppBackupBackgroundTasks.identifier, using: .main) { task in
            let box = BackgroundTaskBox(task)
            Task { @MainActor in launch(SystemBackupTask(box.task)) }
        }
    }
    func submit(earliest: Date) async throws { try await Self.submitRequest(earliest: earliest) }
    @concurrent private static func submitRequest(earliest: Date) async throws {
        let request = BGProcessingTaskRequest(identifier: "com.alqzan.madar2.backup")
        request.earliestBeginDate = earliest
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        if #available(iOS 27, *) { try await BGTaskScheduler.shared.submitTaskRequest(request) }
        else { try BGTaskScheduler.shared.submit(request) }
    }
    func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppBackupBackgroundTasks.identifier) }
}

// BGTask is supplied by the system on its callback queue. The box only transfers
// that reference to MainActor; all property access/completion then stays there.
private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask
    init(_ task: BGTask) { self.task = task }
}
@MainActor private final class SystemBackupTask: BackupBackgroundTask {
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func setExpirationHandler(_ handler: (@Sendable () -> Void)?) { task.expirationHandler = handler }
    func complete(success: Bool) { task.setTaskCompleted(success: success) }
}
