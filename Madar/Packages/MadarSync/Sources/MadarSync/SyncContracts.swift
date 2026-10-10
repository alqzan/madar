import Foundation
import SwiftData
import CloudKit
import CryptoKit
import MadarData

public enum SyncFailure: Error, Equatable, Sendable {
    case notProvisioned, backupRequired, invalidCheckpoint, missingContainer, generationChanged, transitionInProgress, unknownAccount, invalidPreflight, cursorWriteFailed
}
public enum CloudAccount: Equatable, Sendable {
    case available(hash: String), signedOut, restricted, temporarilyUnavailable
    public var identityHash: String? { if case .available(let hash) = self { hash } else { nil } }
}
public protocol CloudAccountProviding: Sendable { func account() async throws -> CloudAccount }
public struct AppleCloudAccountProvider: CloudAccountProviding {
    public let containerIdentifier: String
    public init(containerIdentifier: String) { self.containerIdentifier = containerIdentifier }
    public func account() async throws -> CloudAccount {
        let container = CKContainer(identifier: containerIdentifier)
        switch try await container.accountStatus() {
        case .available:
            let record = try await container.userRecordID()
            let bytes = Data((containerIdentifier + ":" + record.recordName).utf8)
            return .available(hash: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        case .noAccount: return .signedOut
        case .restricted: return .restricted
        case .temporarilyUnavailable, .couldNotDetermine: return .temporarilyUnavailable
        @unknown default: return .temporarilyUnavailable
        }
    }
}
/// Set verifiedEntitlements only after checking the running signed target's App Group,
/// CloudKit container/private database entitlement and environment. Defaults fail closed.
public struct SyncProvisioning: Sendable {
    public let appGroupAvailable: Bool
    public let verifiedEntitlements: Bool
    public let cloudKitContainerIdentifier: String?
    public init(appGroupAvailable: Bool, verifiedEntitlements: Bool = false, cloudKitContainerIdentifier: String? = nil) { self.appGroupAvailable = appGroupAvailable; self.verifiedEntitlements = verifiedEntitlements; self.cloudKitContainerIdentifier = cloudKitContainerIdentifier }
    public var mayOpenCloudMirror: Bool { appGroupAvailable && verifiedEntitlements && cloudKitContainerIdentifier?.isEmpty == false }
}
public enum SyncPreflight {
    public static func validate(syncedDirectory: URL, deviceStoreURL: URL, cloudRequested: Bool, provisioning: SyncProvisioning) throws {
        guard syncedDirectory.isFileURL, deviceStoreURL.isFileURL, deviceStoreURL.lastPathComponent == "Device.store", syncedDirectory.standardizedFileURL != deviceStoreURL.standardizedFileURL,
              provisioning.appGroupAvailable else { throw SyncFailure.invalidPreflight }
        if cloudRequested && !provisioning.mayOpenCloudMirror { throw SyncFailure.notProvisioned }
    }
}
public struct VerifiedSyncCheckpoint: Equatable, Sendable {
    public let file: URL
    public let sha256: String
    public let counts: [String: Int]
    public let generationID: UUID
    public init(file: URL, sha256: String, counts: [String: Int], generationID: UUID) { self.file = file; self.sha256 = sha256; self.counts = counts; self.generationID = generationID }
    public func verifyFile() throws {
        guard file.isFileURL, FileManager.default.fileExists(atPath: file.path), sha256.count == 64 else { throw SyncFailure.invalidCheckpoint }
        let actual = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw SyncFailure.invalidCheckpoint }
    }
}
public enum AccountDataChoice: String, Sendable { case keepDevice, useNewAccount }
public enum SyncTransitionReason: Sendable { case accountChange, disableCloud, enableCloud }
public struct SyncActivationRequest: Sendable {
    public let accountHash: String?
    public let cloudEnabled: Bool
    public let dataChoice: AccountDataChoice
    public let checkpoint: VerifiedSyncCheckpoint?
    public let generationBefore: UUID
    public let requestedDevicePreference: Bool
    public init(accountHash: String?, cloudEnabled: Bool, dataChoice: AccountDataChoice, checkpoint: VerifiedSyncCheckpoint?, generationBefore: UUID, requestedDevicePreference: Bool) {
        self.accountHash = accountHash; self.cloudEnabled = cloudEnabled; self.dataChoice = dataChoice; self.checkpoint = checkpoint; self.generationBefore = generationBefore; self.requestedDevicePreference = requestedDevicePreference
    }
}
/// The app/data owner controls every container. All operations use CommandBus.lock and its
/// maintenance marker, pause writes, release old contexts/mirror, then rebind the app.
/// No account generation may be opened in parallel with a still-owned old mirrored container.
@MainActor public protocol SyncLifecycleAdapter: AnyObject {
    var binding: ManagedStoreBinding { get }
    var syncPreference: Bool { get throws }
    func checkpointAndSuspend(reason: SyncTransitionReason) async throws -> VerifiedSyncCheckpoint
    func activate(_ request: SyncActivationRequest) async throws
    func withExclusiveStoreAccess<T>(_ action: (ModelContainer, ManagedStoreBinding) throws -> T) throws -> T
    func publishSnapshots(changedModels: Set<String>) throws
}
public struct SyncHealth: Equatable, Sendable {
    public enum Phase: String, Sendable { case idle, checkingAccount, localOnly, cloudConfigured, waitingForAccountChoice, transitioning, failed }
    public let phase: Phase
    public let message: String
    public let lastObservedImportAt: Date?
    public let lastObservedExportAt: Date?
    public init(phase: Phase, message: String, lastObservedImportAt: Date? = nil, lastObservedExportAt: Date? = nil) { self.phase = phase; self.message = message; self.lastObservedImportAt = lastObservedImportAt; self.lastObservedExportAt = lastObservedExportAt }
}
