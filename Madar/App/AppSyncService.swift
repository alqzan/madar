import Foundation
import MadarData
import MadarSync

private struct UnprovisionedAccountProvider: CloudAccountProviding {
    func account() async throws -> CloudAccount { throw SyncFailure.notProvisioned }
}

@MainActor final class AppSyncService: SyncUIService {
    private weak var session: AppSession?
    private let store: ManagedDataStore
    let coordinator: SyncCoordinator
    init(session: AppSession, store: ManagedDataStore, backup: AppBackupService) {
        self.session = session; self.store = store
        let adapter = ManagedSyncAdapter(manager: store,
            checkpointAndSuspend: { _ in
                guard try backup.coordinator.hasConfiguredKey() else { throw SyncFailure.backupRequired }
                let receipt = try await backup.coordinator.export(kind: .automatic)
                return VerifiedSyncCheckpoint(file: receipt.fileURL, sha256: receipt.sha256, counts: receipt.counts, generationID: receipt.generationID)
            },
            activate: { [weak session] request in
                // Paid signing and real account rotation are deferred by the owner.
                // Keep local preference functional; fail before any unverified cloud transition.
                guard !request.cloudEnabled, request.accountHash == store.binding.accountHash,
                      request.dataChoice == .keepDevice else { throw SyncFailure.notProvisioned }
                guard let session else { throw SyncFailure.missingContainer }
                try await session.applySettingsAndWait(["core.iCloudSync": .bool(request.requestedDevicePreference)])
            },
            publishSnapshots: { [weak session] _ in
                guard let session else { throw SyncFailure.missingContainer }
                try session.reload(); try session.publishSnapshot()
            })
        coordinator = SyncCoordinator(adapter: adapter, accountProvider: UnprovisionedAccountProvider(),
            provisioning: SyncProvisioning(appGroupAvailable: true))
        coordinator.startObserving()
    }
    func status() async throws -> SyncUIStatus {
        await coordinator.refreshAccount()
        return SyncUIStatus(enabled: store.binding.cloudEnabled, availability: .localBuild,
            lastSyncedAt: coordinator.health.lastObservedImportAt, observedMessage: nil, accountChange: nil)
    }
    func setEnabled(_ enabled: Bool) async throws { try await coordinator.setSyncEnabled(enabled) }
    func resolveAccountChange(id: UUID, choice: SyncUIAccountChoice) async throws { throw SyncFailure.notProvisioned }
    func processLocalHistory() throws { _ = try coordinator.processHistory() }
}
