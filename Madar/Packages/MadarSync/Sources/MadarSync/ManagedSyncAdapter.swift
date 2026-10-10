import Foundation
import SwiftData
import MadarData

/// Connects sync orchestration to the single generation manager. Lifecycle closures belong
/// to BackupCoordinator/AppSession: they must quiesce writers before rotating/rebinding.
/// No extra container is opened here; history refreshes the manager only under its shared lease.
@MainActor public final class ManagedSyncAdapter: SyncLifecycleAdapter {
    public let manager: ManagedDataStore
    private let suspend: @MainActor (SyncTransitionReason) async throws -> VerifiedSyncCheckpoint
    private let activation: @MainActor (SyncActivationRequest) async throws -> Void
    private let snapshots: @MainActor (Set<String>) throws -> Void
    public init(manager: ManagedDataStore, checkpointAndSuspend: @escaping @MainActor (SyncTransitionReason) async throws -> VerifiedSyncCheckpoint,
                activate: @escaping @MainActor (SyncActivationRequest) async throws -> Void,
                publishSnapshots: @escaping @MainActor (Set<String>) throws -> Void) {
        self.manager = manager; suspend = checkpointAndSuspend; activation = activate; snapshots = publishSnapshots
    }
    public var binding: ManagedStoreBinding { manager.binding }
    public var syncPreference: Bool {
        get throws { try withExclusiveStoreAccess { container, _ in
            let store = try SettingsStore(context: ModelContext(container))
            return try store.value(for: "core.iCloudSync") == .bool(true)
        } }
    }
    public func checkpointAndSuspend(reason: SyncTransitionReason) async throws -> VerifiedSyncCheckpoint { try await suspend(reason) }
    public func activate(_ request: SyncActivationRequest) async throws {
        guard request.generationBefore == manager.binding.generationID else { throw SyncFailure.generationChanged }
        try await activation(request)
    }
    public func withExclusiveStoreAccess<T>(_ action: (ModelContainer, ManagedStoreBinding) throws -> T) throws -> T {
        let lease = StoreLease(lockURL: manager.commandLockURL); try lease.acquire(); defer { lease.release() }
        let container = try manager.containerForTransaction()
        return try action(container, manager.binding)
    }
    public func publishSnapshots(changedModels: Set<String>) throws { try snapshots(changedModels) }
}
