import Foundation
import MadarData
import MadarSync

private struct UnprovisionedAccountProvider: CloudAccountProviding {
    func account() async throws -> CloudAccount { throw SyncFailure.notProvisioned }
}

@MainActor final class AppSyncService: SyncUIService {
    /// The CloudKit container this signed build is entitled for, from `MadarCloudKitContainer`
    /// (empty in the default build). Read once before the store opens.
    static let provisionedContainer: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MadarCloudKitContainer") as? String,
              value.hasPrefix("iCloud.") else { return nil }
        return value
    }()
    static var isProvisioned: Bool { provisionedContainer != nil }

    private weak var session: AppSession?
    private let store: ManagedDataStore
    let coordinator: SyncCoordinator
    init(session: AppSession, store: ManagedDataStore, backup: AppBackupService) {
        self.session = session; self.store = store
        let containerID = store.provisionedContainer
        let adapter = ManagedSyncAdapter(manager: store,
            checkpointAndSuspend: { _ in
                guard try backup.coordinator.hasConfiguredKey() else { throw SyncFailure.backupRequired }
                let receipt = try await backup.coordinator.export(kind: .automatic)
                return VerifiedSyncCheckpoint(file: receipt.fileURL, sha256: receipt.sha256, counts: receipt.counts, generationID: receipt.generationID)
            },
            activate: { [weak session] request in
                guard let session else { throw SyncFailure.missingContainer }
                // Taking another account's data replaces this device's generation; it waits for a device trial.
                guard request.dataChoice == .keepDevice else { throw SyncFailure.notProvisioned }
                // A store that mirrored under one account never attaches under another: CloudKit mirroring can purge
                // rows it holds for the old account. The data stays on the device and sync stays off until a device
                // trial proves the switch; the person's account choice is kept.
                let switchingAccount = store.mirrorBound && store.binding.accountHash != nil && request.accountHash != store.binding.accountHash
                let mirror = request.cloudEnabled && containerID != nil && !switchingAccount
                let preference = request.requestedDevicePreference && !switchingAccount
                if mirror != store.binding.cloudEnabled || request.accountHash != store.binding.accountHash || switchingAccount {
                    // Before the first upload, keep a verified copy of everything on this device. A store that was
                    // already mirroring re-attaches after launch without a new backup.
                    if mirror && !store.binding.cloudEnabled && !store.mirrorBound {
                        guard try backup.coordinator.hasConfiguredKey() else { throw SyncFailure.backupRequired }
                        _ = try await backup.coordinator.export(kind: .automatic)
                    }
                    try await session.quiesceWriters()
                    do {
                        let lease = StoreLease(lockURL: store.commandLockURL); try lease.acquire(); defer { lease.release() }
                        try store.bindCloudMirror(enabled: mirror, accountHash: request.accountHash)
                        session.bindContainer(store.container)
                        try session.reload(); try session.publishSnapshot()
                    } catch { session.resumeWriters(); throw error }
                    session.resumeWriters()
                }
                try await session.applySettingsAndWait(["core.iCloudSync": .bool(preference)])
            },
            publishSnapshots: { [weak session] _ in
                guard let session else { throw SyncFailure.missingContainer }
                try session.reload(); try session.publishSnapshot()
            })
        // CKContainer traps for an identifier the build is not entitled to: only a provisioned build asks iCloud.
        let accounts: any CloudAccountProviding = containerID.map { AppleCloudAccountProvider(containerIdentifier: $0) } ?? UnprovisionedAccountProvider()
        coordinator = SyncCoordinator(adapter: adapter, accountProvider: accounts,
            provisioning: SyncProvisioning(appGroupAvailable: true, verifiedEntitlements: containerID != nil, cloudKitContainerIdentifier: containerID))
        coordinator.startObserving()
    }
    func status() async throws -> SyncUIStatus {
        await coordinator.refreshAccount()
        let availability: SyncUIAvailability
        switch (store.provisionedContainer, coordinator.observedAccount) {
        case (nil, _): availability = .localBuild
        case (_, .available?): availability = coordinator.health.message.contains("ممتلئة") ? .quotaFull : .available
        case (_, .signedOut?): availability = .noAccount
        case (_, .restricted?): availability = .restricted
        default: availability = .unavailable
        }
        let change = coordinator.checkpoint.map { saved in
            SyncUIAccountChange(id: saved.generationID,
                safetyBackupAt: (try? saved.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
        }
        return SyncUIStatus(enabled: store.binding.cloudEnabled, availability: availability,
            lastSyncedAt: coordinator.health.lastObservedImportAt ?? coordinator.health.lastObservedExportAt,
            observedMessage: coordinator.health.phase == .failed ? coordinator.health.message : nil,
            accountChange: coordinator.pendingAccountHash == nil ? nil : change)
    }
    func setEnabled(_ enabled: Bool) async throws { try await coordinator.setSyncEnabled(enabled) }
    func resolveAccountChange(id: UUID, choice: SyncUIAccountChoice) async throws {
        guard choice == .keepDeviceData else { throw SyncFailure.notProvisioned }
        try await coordinator.resolveAccountChange(.keepDevice)
    }
    func processLocalHistory() throws { _ = try coordinator.processHistory() }
}
