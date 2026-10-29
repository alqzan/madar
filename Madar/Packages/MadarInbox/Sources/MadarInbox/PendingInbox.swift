import Foundation
import Darwin
import MadarCore

public enum InboxError: Error, Equatable, Sendable {
    case duplicateDelivery, malformedRecord, unknownVersion, invalidLocation, io(Int32)
}
public struct InboxRecord: Codable, Equatable, Sendable {
    public let transportVersion: Int
    public let deliveryID: UUID
    public let expectedGenerationID: UUID?
    public let command: CommandEnvelope
    public init(transportVersion: Int = 1, deliveryID: UUID = UUID(), expectedGenerationID: UUID?, command: CommandEnvelope) {
        self.transportVersion = transportVersion; self.deliveryID = deliveryID
        self.expectedGenerationID = expectedGenerationID; self.command = command
    }
}
public struct InboxTicket: Sendable, Equatable {
    public let deliveryID: UUID
    public let commandID: UUID
}
/// App-published store identity, separate from canonical room snapshots and disposable overlays.
public struct InboxGeneration: Codable, Equatable, Sendable {
    public let version: Int
    public let generationID: UUID
    public let acceptsUnstampedDeliveries: Bool
    public init(generationID: UUID, acceptsUnstampedDeliveries: Bool) {
        version = 1; self.generationID = generationID; self.acceptsUnstampedDeliveries = acceptsUnstampedDeliveries
    }
    public func permits(_ record: InboxRecord) -> Bool {
        if let expected = record.expectedGenerationID { return expected == generationID }
        return acceptsUnstampedDeliveries
    }
}
private struct CompletedIdentity: Codable {
    let version: Int
    let generationID: UUID
    let commandID: UUID
}
private struct InboxDiagnostic: Codable {
    let version: Int
    let deliveryID: UUID
    let reason: String
}

/// Immutable one-record JSONL spool. Contains no SwiftData or writable-store dependency.
/// Producers publish one file atomically; only the app claims, acknowledges or resolves it.
public struct PendingInbox: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory.standardizedFileURL.resolvingSymlinksInPath() }
    @discardableResult public func enqueue(_ record: InboxRecord) throws -> InboxTicket {
        guard record.transportVersion == 1 else { throw InboxError.unknownVersion }
        try prepare()
        var data = try encode(record); data.append(10)
        guard data.count <= 1_048_576 else { throw InboxError.malformedRecord }
        try publish(data, to: location("pending", record.deliveryID), exclusive: true)
        return InboxTicket(deliveryID: record.deliveryID, commandID: record.command.commandID)
    }
    /// Resume processing files first. Atomic renames publish ownership without store access.
    public func processingFiles() throws -> [URL] { try files(in: "processing") }
    public func claimBatch() throws -> [URL] {
        try prepare()
        let resumed = try files(in: "processing")
        var claimed: [URL] = []
        pendingFiles: for file in try files(in: "pending") {
            // Delivery IDs identify envelopes, not physical file ownership. A producer may
            // publish the same ID after the first file was claimed. Preserve both accepted
            // records under distinct filenames; only the command transaction resolves replay.
            var destination = directory.appending(path: "processing/\(file.lastPathComponent)")
            while renamex_np(file.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
                if errno == ENOENT { continue pendingFiles }
                guard errno == EEXIST else { throw InboxError.io(errno) }
                destination = directory.appending(path: "processing/\(file.deletingPathExtension().lastPathComponent)~\(UUID()).jsonl")
            }
            try syncDirectory(file.deletingLastPathComponent()); try syncDirectory(destination.deletingLastPathComponent())
            claimed.append(destination)
        }
        return resumed + claimed
    }
    public func read(_ file: URL) throws -> InboxRecord {
        try validate(file, folder: "processing")
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 1_048_576 else { throw InboxError.malformedRecord }
        let data = try Data(contentsOf: file)
        guard data.last == 10, data.dropLast().firstIndex(of: 10) == nil else { throw InboxError.malformedRecord }
        let record: InboxRecord
        do { record = try JSONDecoder().decode(InboxRecord.self, from: data.dropLast()) }
        catch { throw InboxError.malformedRecord }
        guard record.transportVersion == 1 else { throw InboxError.unknownVersion }
        guard record.deliveryID == deliveryID(for: file) else { throw InboxError.malformedRecord }
        return record
    }
    /// Save replay provenance after commit+refresh and before unlink. A later retry whose
    /// seven-day receipt was collected requires explicit resolution, never a fresh mutation.
    public func markCommitted(commandID: UUID, generationID: UUID) throws {
        try prepare()
        let marker = directory.appending(path: "completed/\(generationID.uuidString)-\(commandID.uuidString).json")
        try publish(encode(CompletedIdentity(version: 1, generationID: generationID, commandID: commandID)), to: marker, exclusive: false)
    }
    public func wasCommitted(commandID: UUID, generationID: UUID) throws -> Bool {
        let marker = directory.appending(path: "completed/\(generationID.uuidString)-\(commandID.uuidString).json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        let value = try JSONDecoder().decode(CompletedIdentity.self, from: Data(contentsOf: marker))
        guard value.version == 1, value.generationID == generationID, value.commandID == commandID else { throw InboxError.malformedRecord }
        return true
    }
    /// Receipt GC does not make an already completed command ID a fresh action.
    /// Search every generation: a producer's new snapshot stamp cannot erase provenance
    /// from the generation where this identity previously committed.
    public func wasCommitted(commandID: UUID) throws -> Bool {
        let folder = directory.appending(path: "completed", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        let suffix = "-\(commandID.uuidString).json"
        for marker in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where marker.lastPathComponent.hasSuffix(suffix) {
            let value = try JSONDecoder().decode(CompletedIdentity.self, from: Data(contentsOf: marker))
            guard value.version == 1, value.commandID == commandID,
                  marker.lastPathComponent == "\(value.generationID.uuidString)-\(commandID.uuidString).json" else { throw InboxError.malformedRecord }
            return true
        }
        return false
    }
    public func acknowledge(_ file: URL) throws {
        try validate(file, folder: "processing")
        try FileManager.default.removeItem(at: file)
        try syncDirectory(file.deletingLastPathComponent())
    }
    public func quarantine(_ file: URL, reason: String) throws { try retain(file, folder: "quarantine", reason: reason) }
    public func retainForResolution(_ file: URL, reason: String) throws { try retain(file, folder: "unresolved", reason: reason) }
    /// Conservative GC: unreadable files throw so callers cannot accidentally collect dedupe IDs.
    public func unacknowledgedCommandIDs() throws -> Set<UUID> {
        var result: Set<UUID> = []
        for folder in ["pending", "processing", "unresolved", "quarantine"] {
            for file in try files(in: folder) {
                let data = try Data(contentsOf: file)
                guard data.count <= 1_048_576, let record = try? JSONDecoder().decode(InboxRecord.self, from: data) else { throw InboxError.malformedRecord }
                result.insert(record.command.commandID)
            }
        }
        return result
    }
    public func publishGeneration(_ generation: InboxGeneration) throws {
        try prepare(); try publish(encode(generation), to: directory.appending(path: "Generation.json"), exclusive: false)
    }
    public func currentGeneration() throws -> InboxGeneration? {
        let file = directory.appending(path: "Generation.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let value = try JSONDecoder().decode(InboxGeneration.self, from: Data(contentsOf: file))
        guard value.version == 1 else { throw InboxError.unknownVersion }
        return value
    }
    private func prepare() throws {
        for folder in ["pending", "processing", "quarantine", "unresolved", "completed"] {
            let url = directory.appending(path: folder, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // Persist the spool's directory entries as well as each published record.
        try syncDirectory(directory)
        try syncDirectory(directory.deletingLastPathComponent())
    }
    private func location(_ folder: String, _ id: UUID) -> URL { directory.appending(path: "\(folder)/\(id.uuidString).jsonl") }
    private func files(in folder: String) throws -> [URL] {
        let url = directory.appending(path: folder, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            // A directory or link with a record's name is never claimed, so it cannot stall the drain.
            .filter { $0.pathExtension == "jsonl" && deliveryID(for: $0) != nil && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func deliveryID(for file: URL) -> UUID? {
        let parts = file.deletingPathExtension().lastPathComponent.split(separator: "~", omittingEmptySubsequences: false)
        guard parts.count == 1 || (parts.count == 2 && UUID(uuidString: String(parts[1])) != nil) else { return nil }
        return UUID(uuidString: String(parts[0]))
    }
    private func validate(_ file: URL, folder: String) throws {
        let actualParent = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let expectedParent = directory.appending(path: folder, directoryHint: .isDirectory).standardizedFileURL.resolvingSymlinksInPath().path
        guard actualParent == expectedParent,
              file.pathExtension == "jsonl", deliveryID(for: file) != nil,
              try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
              try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw InboxError.invalidLocation }
    }
    private func retain(_ file: URL, folder: String, reason: String) throws {
        try validate(file, folder: "processing")
        let id = deliveryID(for: file)!
        // Fixed machine reason only; never write a command payload or localized error description.
        guard ["malformedRecord", "unknownVersion", "invalidCommand", "generationChanged", "legacyIdentityAmbiguous"].contains(reason) else { throw InboxError.invalidLocation }
        var destination = directory.appending(path: "\(folder)/\(file.lastPathComponent)")
        // Retained copies can collide too, including across app restarts.
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appending(path: "\(folder)/\(id.uuidString)~\(UUID()).jsonl")
        }
        let diagnostic = destination.deletingPathExtension().appendingPathExtension("diagnostic.json")
        try publish(encode(InboxDiagnostic(version: 1, deliveryID: id, reason: reason)), to: diagnostic, exclusive: false)
        guard renamex_np(file.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw InboxError.io(errno) }
        try syncDirectory(file.deletingLastPathComponent()); try syncDirectory(destination.deletingLastPathComponent())
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func publish(_ data: Data, to destination: URL, exclusive: Bool) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appending(path: ".\(UUID()).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw InboxError.io(errno) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        let flags = exclusive ? UInt32(RENAME_EXCL) : 0
        guard renamex_np(temporary.path, destination.path, flags) == 0 else {
            if errno == EEXIST { throw InboxError.duplicateDelivery }; throw InboxError.io(errno)
        }
        try syncDirectory(parent)
    }
    private func syncDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw InboxError.io(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw InboxError.io(errno) }
    }
}
