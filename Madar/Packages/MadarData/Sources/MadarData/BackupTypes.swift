import Foundation
import SwiftData

public enum BackupOperationError: Error, Equatable, Sendable {
    case busy, cancelled, cloudRestoreUnsupported, invalidManagedStore, stalePreview, backupNotConfigured, nonceExhausted, simulatedInterruption(String), adoptionRequiresEmptyRoot
}
public enum BackupKind: String, Codable, Sendable { case manual, automatic }
public enum RestoreMode: String, Codable, Sendable { case merge, replace }
public struct BackupProgress: Sendable {
    public enum Phase: String, Sendable { case reading, decrypting, validating, automaticBackup, encrypting, writing, staging, promoting, completed }
    public let phase: Phase; public let completedUnits: Int64; public let totalUnits: Int64
    public init(phase: Phase, completedUnits: Int64, totalUnits: Int64) { self.phase = phase; self.completedUnits = completedUnits; self.totalUnits = totalUnits }
}
public final class BackupCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value || Task.isCancelled { throw BackupOperationError.cancelled } }
}
public struct BackupReceipt: Codable, Sendable {
    public let id: UUID; public let fileURL: URL; public let createdAt: Date; public let kind: BackupKind; public let generationID: UUID; public let sha256: String; public let counts: [String:Int]
}
public struct RestorePreview: Sendable {
    public let id: UUID; public let fileURL: URL; public let fileName: String; public let createdAt: Date
    public let counts: [String:Int]; public let currentCounts: [String:Int]; public let additions: Int; public let updates: Int; public let deletions: Int
    public let earliestDate: Date?; public let latestDate: Date?; public let skippedCount: Int; public let warnings: [String]
    let validated: ValidatedBackup; let fileHash: String; let generationID: UUID; let currentFingerprint: String
}
public struct RestoreResult: Sendable {
    public let generationID: UUID; public let restoredCount: Int; public let skippedCount: Int; public let automaticBackup: BackupReceipt; public let warnings: [String]
    public let container: ModelContainer
}
public struct ManagedStoreBinding: Codable, Sendable, Equatable {
    public let generationID: UUID; public let syncedDirectory: URL; public let deviceStoreURL: URL; public let accountHash: String?; public let cloudEnabled: Bool
}
/// Required root integrations: freeze/drain writers before capture, rebind after commit, rebuild snapshots/reset history before resuming.
@MainActor public struct BackupLifecycle {
    public var quiesce: @MainActor () async throws -> Void
    public var bindContainer: @MainActor (ModelContainer) -> Void
    public var rebuildSnapshots: @MainActor (ModelContainer) async throws -> Void
    public var resetHistory: @MainActor (UUID) async throws -> Void
    public var resume: @MainActor () -> Void
    public init(quiesce: @escaping @MainActor () async throws -> Void = {}, bindContainer: @escaping @MainActor (ModelContainer) -> Void = { _ in }, rebuildSnapshots: @escaping @MainActor (ModelContainer) async throws -> Void = { _ in }, resetHistory: @escaping @MainActor (UUID) async throws -> Void = { _ in }, resume: @escaping @MainActor () -> Void = {}) {
        self.quiesce = quiesce; self.bindContainer = bindContainer; self.rebuildSnapshots = rebuildSnapshots; self.resetHistory = resetHistory; self.resume = resume
    }
}
public enum BackupSchedule: String, Codable, Sendable {
    case off, daily, weekly
    public var interval: TimeInterval? { switch self { case .off: nil; case .daily: 86400; case .weekly: 7*86400 } }
    public func isDue(lastSuccess: Date?, now: Date) -> Bool { guard let interval else { return false }; guard let lastSuccess else { return true }; return now.timeIntervalSince(lastSuccess) >= interval }
}

public struct BackupStatus: Codable, Sendable {
    public let lastSuccessAt: Date?; public let lastResult: String; public let localOnly: Bool
    /// Book files the last successful backup left out to stay within its budget (RD4); nil in older status files.
    public let excludedBooks: [BackupBookExclusion]?
    public init(lastSuccessAt: Date?, lastResult: String, localOnly: Bool, excludedBooks: [BackupBookExclusion]? = nil) { self.lastSuccessAt = lastSuccessAt; self.lastResult = lastResult; self.localOnly = localOnly; self.excludedBooks = excludedBooks }
}
