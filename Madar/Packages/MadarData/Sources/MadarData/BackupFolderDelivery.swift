import Foundation
import CryptoKit

/// Device-only permission and ownership metadata; never included in a data backup.
public struct BackupFolderConfiguration: Codable, Sendable {
    public var bookmark: Data
    public let ownerID: UUID
    public let folderName: String
    public var owned: [BackupFolderFile]
    public var lastCopiedAt: Date?
    public init(bookmark: Data, ownerID: UUID = UUID(), folderName: String) {
        self.bookmark = bookmark; self.ownerID = ownerID; self.folderName = folderName
        owned = []; lastCopiedAt = nil
    }
}
public struct BackupFolderFile: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let sha256: String
    public let kind: BackupKind
    public let createdAt: Date
}
public struct BackupFolderResult: Sendable {
    public let configuration: BackupFolderConfiguration
    /// nil means this provider does not expose an iCloud upload result.
    public let uploadedToICloud: Bool?
    public let preservedChangedFiles: Int
}
public enum BackupFolderError: Error, Equatable { case invalidFolder, invalidSource, changedDestination }

/// Copies only coordinator-verified encrypted receipts. Local success remains valid
/// when a provider is unavailable; callers retain configuration and retry later.
public enum BackupFolderDelivery {
    public static func select(_ folder: URL) throws -> BackupFolderConfiguration {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard folder.isFileURL, values.isDirectory == true, values.isSymbolicLink != true else { throw BackupFolderError.invalidFolder }
        return try .init(bookmark: folder.bookmarkData(options: .minimalBookmark), folderName: folder.lastPathComponent)
    }

    public static func deliver(_ receipts: [BackupReceipt], from sourceDirectory: URL, to configuration: BackupFolderConfiguration,
                               now: Date = .now) async throws -> BackupFolderResult {
        let task = Task.detached(priority: .utility) {
            try copy(receipts, from: sourceDirectory, to: configuration, now: now)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    public static func uploadStatus(_ configuration: BackupFolderConfiguration) async -> Bool? {
        await Task.detached(priority: .utility) {
            guard let latest = configuration.owned.max(by: { $0.createdAt < $1.createdAt }),
                  latest.name == (latest.name as NSString).lastPathComponent else { return nil as Bool? }
            var stale = false
            guard let folder = try? URL(resolvingBookmarkData: configuration.bookmark, options: .withoutUI, bookmarkDataIsStale: &stale) else { return nil }
            let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let file = folder.appendingPathComponent("Madar-" + configuration.ownerID.uuidString).appendingPathComponent(latest.name)
            return cloudStatus(file)
        }.value
    }

    private static func copy(_ receipts: [BackupReceipt], from sourceDirectory: URL, to configuration: BackupFolderConfiguration,
                             now: Date) throws -> BackupFolderResult {
        var result = configuration, stale = false
        let folder = try URL(resolvingBookmarkData: configuration.bookmark, options: .withoutUI, bookmarkDataIsStale: &stale)
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        if stale { result.bookmark = try folder.bookmarkData(options: .minimalBookmark) }
        let manager = FileManager.default
        let directory = folder.appendingPathComponent("Madar-" + configuration.ownerID.uuidString, isDirectory: true)
        if manager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw BackupFolderError.invalidFolder }
        } else { try manager.createDirectory(at: directory, withIntermediateDirectories: false) }
        var owned = Dictionary(configuration.owned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lastFile: URL?
        var copiedAny = false
        for receipt in receipts.sorted(by: { $0.createdAt < $1.createdAt }) {
            try Task.checkCancellation()
            let source = receipt.fileURL, name = source.lastPathComponent
            guard source.isFileURL, source.deletingLastPathComponent().resolvingSymlinksInPath() == sourceDirectory.resolvingSymlinksInPath(),
                  (name.hasSuffix(".madarbackup") || name.hasSuffix(".madarbackupset")), name.contains(receipt.id.uuidString),
                  try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                  try encryptedHeader(at: source), try hash(source) == receipt.sha256 else { throw BackupFolderError.invalidSource }
            let target = directory.appendingPathComponent(name)
            var coordinationError: NSError?, copyError: Error?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinated in
                do {
                    if manager.fileExists(atPath: coordinated.path) {
                        guard try coordinated.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                              try hash(coordinated) == receipt.sha256 else { throw BackupFolderError.changedDestination }
                    } else {
                        let partial = coordinated.deletingLastPathComponent().appendingPathComponent(".Madar-" + UUID().uuidString + ".partial")
                        defer { try? manager.removeItem(at: partial) }
                        try manager.copyItem(at: source, to: partial)
                        guard try hash(partial) == receipt.sha256 else { throw BackupFolderError.invalidSource }
                        // moveItem refuses an existing target: never replace someone else's bytes.
                        try manager.moveItem(at: partial, to: coordinated)
                        copiedAny = true
                    }
                } catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            owned[receipt.id] = .init(id: receipt.id, name: name, sha256: receipt.sha256, kind: receipt.kind, createdAt: receipt.createdAt)
            lastFile = target
        }
        // Only our old automatic receipts, with unchanged bytes, may be pruned.
        // All current receipts have been copied and verified before this starts.
        let active = Set(receipts.map(\.id))
        var preserved = 0
        let automatic = receipts.filter { $0.kind == .automatic }
        let cutoff = automatic.count >= 4 ? automatic.map(\.createdAt).min() : nil
        for file in owned.values where file.kind == .automatic && !active.contains(file.id) && cutoff.map({ file.createdAt < $0 }) == true {
            guard file.name == (file.name as NSString).lastPathComponent, file.name.contains(file.id.uuidString), (file.name.hasSuffix(".madarbackup") || file.name.hasSuffix(".madarbackupset")) else { throw BackupFolderError.invalidSource }
            let target = directory.appendingPathComponent(file.name)
            if try !removeUnchanged(at: target, expectedHash: file.sha256) { preserved += 1; continue }
            owned.removeValue(forKey: file.id)
        }
        result.owned = owned.values.sorted { $0.id.uuidString < $1.id.uuidString }
        if copiedAny || (result.lastCopiedAt == nil && !receipts.isEmpty) { result.lastCopiedAt = now }
        return .init(configuration: result,
                     uploadedToICloud: lastFile.flatMap(cloudStatus),
                     preservedChangedFiles: preserved)
    }

    /// File providers may replace bytes while relinquishing a file for deletion.
    /// Validate only inside the coordinated accessor, after that relinquishment.
    static func removeUnchanged(at target: URL, expectedHash: String, coordinator: NSFileCoordinator = NSFileCoordinator()) throws -> Bool {
        var coordinationError: NSError?, deletionError: Error?
        var removed = false
        coordinator.coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { coordinated in
            do {
                guard FileManager.default.fileExists(atPath: coordinated.path) else { removed = true; return }
                guard try coordinated.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return }
                let currentHash: String
                do { currentHash = try hash(coordinated) }
                catch is CancellationError { throw CancellationError() }
                catch { return } // An unreadable or structurally changed package belongs to the provider now.
                guard currentHash == expectedHash else { return }
                try FileManager.default.removeItem(at: coordinated); removed = true
            } catch { deletionError = error }
        }
        if let coordinationError { throw coordinationError }
        if let deletionError { throw deletionError }
        return removed
    }

    private static func cloudStatus(_ file: URL) -> Bool? {
        guard let files = try? BackupArtifact.artifactFiles(file) else { return nil }
        var uploaded = true
        for (_, child) in files {
            guard let values = try? child.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey]),
                  values.isUbiquitousItem == true, let complete = values.ubiquitousItemIsUploaded else { return nil }
            uploaded = uploaded && complete
        }
        return uploaded
    }
    private static func hash(_ file: URL) throws -> String { try BackupArtifact.fingerprint(file: file) }
    private static func encryptedHeader(at file: URL) throws -> Bool { try BackupArtifact.encryptedHeader(file: file) }
}
