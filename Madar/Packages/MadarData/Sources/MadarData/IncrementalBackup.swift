import Foundation
import SwiftData
import CryptoKit
import Darwin

/// A backup set is self-contained. Unchanged, authenticated media envelopes are
/// cloned into the next set by SHA-256; no retained set depends on an older one.
/// Manual .madarbackup exports keep the original portable v1 format.
public enum BackupArtifact {
    static let maximumBytes = 512 * 1024 * 1024
    static let indexName = "Snapshot.madarindex"
    static let mediaDirectory = "Media"
    struct MediaLink: Codable, Sendable { let path: String; let object: String }
    struct PackageIndex: Codable, Sendable { let formatVersion: Int; let media: [MediaLink] }

    @MainActor public static func validate(file: URL, passphrase: String) throws -> ValidatedBackup {
        let value = try validateContents(file: file, passphrase: passphrase)
        try BackupCodec.validateTypedRows(value.records)
        return value
    }
    static func validateContents(file: URL, passphrase: String? = nil, credential: BackupCredential? = nil,
                                 cancellation: BackupCancellation = BackupCancellation(),
                                 progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> ValidatedBackup {
        if try isDirectory(file) {
            return try readPackage(file, passphrase: passphrase, credential: credential, cancellation: cancellation, progress: progress).backup
        }
        return try BackupCodec.validateContents(readBounded(file), passphrase: passphrase, credential: credential,
                                               cancellation: cancellation, progress: progress)
    }
    /// Ciphertext-only fingerprint, including every package child and its length.
    /// Used for stale previews, delivery and coordinated retention checks.
    public static func fingerprint(file: URL) throws -> String {
        let files = try artifactFiles(file)
        if files.count == 1 && files[0].0.isEmpty { return try hashFile(files[0].1) }
        let entries = try files.map { name, url in
            name + ":" + String(try fileSize(url)) + ":" + (try hashFile(url))
        }.joined(separator: "\n")
        return BackupCodec.hash(Data(entries.utf8))
    }
    static func encryptedHeader(file: URL) throws -> Bool {
        let package = try isDirectory(file)
        let url = package ? file.appendingPathComponent(indexName) : file
        if package { _ = try artifactFiles(file) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        guard let bytes = try handle.read(upToCount: 4), bytes.count == 4 else { return false }
        let count = bytes.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...65536).contains(count), let data = try handle.read(upToCount: count), data.count == count,
              let header = try? JSONDecoder().decode(BackupHeader.self, from: data) else { return false }
        return header.magic == "MADARBK" && header.cipher == "AES-256-GCM" && header.formatVersion == (package ? 2 : 1)
    }
    /// Reserve a distinct envelope nonce before I/O, including unused reservations
    /// when cancellation or an authenticated cache hit avoids encryption.
    static func envelopeCount(records: [DataRecord]) -> Int {
        1 + Set(records.filter { $0.model == "Media" && $0.fields["data"] != .null }
            .compactMap { $0.fields["sha256"]?.string }).count
    }
    @discardableResult static func writePackage(records: [DataRecord], to destination: URL, previous: URL?,
                                                credential: BackupCredential, prefixes: [Data], now: Date,
                                                cancellation: BackupCancellation,
                                                progress: @Sendable (BackupProgress) -> Void) throws -> Int {
        try cancellation.check()
        // The distinct media hashes are known from the rows (contentFiles verifies each against its bytes), so no file is decoded yet.
        let hashes = Set(records.filter { $0.model == "Media" && $0.fields["data"] != .null }.compactMap { $0.fields["sha256"]?.string })
        guard prefixes.count == hashes.count + 1 else { throw DataError.invalidBackup }
        // A damaged, differently keyed or older cache is never authoritative.
        var cached: [String: URL] = [:]
        if let previous, let old = try? readPackage(previous, credential: credential, hydrateMedia: false, cancellation: cancellation) {
            for link in old.links {
                if let descriptor = old.backup.manifest.files.first(where: { $0.path == link.path }) {
                    cached[descriptor.sha256] = previous.appendingPathComponent(mediaDirectory).appendingPathComponent(link.object)
                }
            }
        }
        try cancellation.check()
        let manager = FileManager.default
        try manager.createDirectory(at: destination.appendingPathComponent(mediaDirectory), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        var completed = false
        defer { if !completed { try? manager.removeItem(at: destination) } }
        var objects: [String: String] = [:], links: [MediaLink] = []
        var reused = 0, prefixIndex = 1
        // Each media file is sealed and written the moment it is decoded, then released (B1-15).
        var files = try withoutActuallyEscaping(progress) { progress in try BackupCodec.contentFiles(records: records, now: now, mediaSink: { path, bytes in
            try cancellation.check()
            let sha = BackupCodec.hash(bytes)
            let name: String
            if let existing = objects[sha] { name = existing }
            else if let source = cached[sha] {
                name = source.lastPathComponent
                let target = destination.appendingPathComponent(mediaDirectory).appendingPathComponent(name)
                // APFS clones are independent files: a later write/corruption of
                // one backup cannot mutate another through a shared inode.
                if clonefile(source.path, target.path, 0) != 0 { try manager.copyItem(at: source, to: target) }
                try cancellation.check()
                guard try hashFile(target) == String(name.dropLast(".madarmedia".count)) else { throw DataError.invalidBackup }
                objects[sha] = name; reused += 1
                progress(.init(phase: .writing, completedUnits: Int64(objects.count), totalUnits: Int64(hashes.count + 1)))
            } else {
                let encrypted = try BackupCodec.seal(archive: BackupCodec.encodeArchive(["blob": bytes]), credential: credential,
                                                      noncePrefix: prefixes[prefixIndex], now: now, cancellation: cancellation)
                prefixIndex += 1
                name = BackupCodec.hash(encrypted) + ".madarmedia"
                try write(encrypted, to: destination.appendingPathComponent(mediaDirectory).appendingPathComponent(name),
                          cancellation: cancellation, progress: progress)
                objects[sha] = name
            }
            links.append(.init(path: path, object: name))
        }) }
        files["package.json"] = try JSONEncoder().encode(PackageIndex(formatVersion: 2, media: links))
        let index = try BackupCodec.seal(archive: BackupCodec.encodeArchive(files), credential: credential,
                                        noncePrefix: prefixes[0], now: now, formatVersion: 2, cancellation: cancellation)
        try write(index, to: destination.appendingPathComponent(indexName), cancellation: cancellation, progress: progress)
        _ = try readPackage(destination, credential: credential, hydrateMedia: false, cancellation: cancellation)
        completed = true
        return reused
    }
    private static func readPackage(_ directory: URL, passphrase: String? = nil, credential: BackupCredential? = nil,
                                    hydrateMedia: Bool = true, cancellation: BackupCancellation = BackupCancellation(),
                                    progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> (backup: ValidatedBackup, links: [MediaLink]) {
        let all = try artifactFiles(directory)
        let opened = try BackupCodec.openArchive(readBounded(directory.appendingPathComponent(indexName)), passphrase: passphrase,
                                                 credential: credential, formatVersion: 2, cancellation: cancellation, progress: progress)
        var files = opened.files
        guard let indexData = files.removeValue(forKey: "package.json"), let manifestData = files["manifest.json"] else { throw DataError.invalidBackup }
        let index = try JSONDecoder().decode(PackageIndex.self, from: indexData)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        let mediaFiles = manifest.files.filter { $0.path.hasPrefix("media/") }
        guard index.formatVersion == 2, manifest.storeSchemaVersion == opened.header.storeSchemaVersion,
              Set(index.media.map(\.path)).count == index.media.count,
              Set(index.media.map(\.path)) == Set(mediaFiles.map(\.path)) else { throw DataError.invalidBackup }
        let expectedPaths = Set([indexName] + index.media.map { mediaDirectory + "/" + $0.object })
        guard Set(all.map(\.0)) == expectedPaths else { throw DataError.invalidBackup }
        var objects: [String: Data] = [:], hydratedBytes = 0, checkedObjects = Set<String>()
        for link in index.media {
            try cancellation.check()
            guard validObjectName(link.object), let descriptor = mediaFiles.first(where: { $0.path == link.path }) else { throw DataError.invalidBackup }
            if !hydrateMedia {
                // Verify the object and drop it at once: only one media file is ever in memory.
                // A shared object is verified once.
                guard checkedObjects.insert(link.object).inserted else { continue }
                let encrypted = try readBounded(directory.appendingPathComponent(mediaDirectory).appendingPathComponent(link.object))
                guard BackupCodec.hash(encrypted) == String(link.object.dropLast(".madarmedia".count)) else { throw DataError.invalidBackup }
                let blob = try BackupCodec.openArchive(encrypted, credential: opened.credential, cancellation: cancellation)
                guard Set(blob.files.keys) == ["blob"], let bytes = blob.files["blob"], bytes.count == descriptor.bytes, BackupCodec.hash(bytes) == descriptor.sha256 else { throw DataError.invalidBackup }
                continue
            }
            let data: Data
            if let existing = objects[link.object] { data = existing }
            else {
                let encrypted = try readBounded(directory.appendingPathComponent(mediaDirectory).appendingPathComponent(link.object))
                guard BackupCodec.hash(encrypted) == String(link.object.dropLast(".madarmedia".count)) else { throw DataError.invalidBackup }
                let blob = try BackupCodec.openArchive(encrypted, credential: opened.credential, cancellation: cancellation)
                guard Set(blob.files.keys) == ["blob"], let bytes = blob.files["blob"] else { throw DataError.invalidBackup }
                data = bytes; objects[link.object] = data
            }
            guard data.count == descriptor.bytes, BackupCodec.hash(data) == descriptor.sha256,
                  hydratedBytes <= maximumBytes - data.count else { throw DataError.invalidBackup }
            hydratedBytes += data.count; files[link.path] = data
        }
        let models = try SchemaCompatibility.modelNames(version: manifest.storeSchemaVersion)
        return (try BackupCodec.validateFiles(files, manifest: manifest, sourceModels: models, hydrateMedia: hydrateMedia, cancellation: cancellation, progress: progress), index.media)
    }
    private static func validObjectName(_ name: String) -> Bool {
        guard name.hasSuffix(".madarmedia") else { return false }
        let hex = name.dropLast(".madarmedia".count)
        return hex.count == 64 && hex.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard url.isFileURL, values.isSymbolicLink != true else { throw DataError.invalidBackup }
        return values.isDirectory == true
    }
    static func artifactFiles(_ url: URL) throws -> [(String, URL)] {
        if try !isDirectory(url) { _ = try fileSize(url); return [("", url)] }
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        guard Set(children.map(\.lastPathComponent)) == [indexName, mediaDirectory],
              try isDirectory(url.appendingPathComponent(mediaDirectory)) else { throw DataError.invalidBackup }
        var files = [(indexName, url.appendingPathComponent(indexName))]
        let media = try manager.contentsOfDirectory(at: url.appendingPathComponent(mediaDirectory), includingPropertiesForKeys: nil)
        guard media.count < 100000 else { throw DataError.invalidBackup }
        for child in media {
            guard validObjectName(child.lastPathComponent) else { throw DataError.invalidBackup }
            files.append((mediaDirectory + "/" + child.lastPathComponent, child))
        }
        var total = 0
        for (_, file) in files {
            let size = try fileSize(file)
            guard total <= maximumBytes - size else { throw DataError.invalidBackup }; total += size
        }
        return files.sorted { $0.0 < $1.0 }
    }
    static func fileSize(_ url: URL) throws -> Int {
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true, let size = value.fileSize, size <= maximumBytes else { throw DataError.invalidBackup }
        return size
    }
    static func readBounded(_ url: URL) throws -> Data {
        _ = try fileSize(url)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var data = Data()
        while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            guard data.count <= maximumBytes - bytes.count else { throw DataError.invalidBackup }
            data.append(bytes)
        }
        return data
    }
    private static func hashFile(_ url: URL) throws -> String {
        _ = try fileSize(url)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256(), total = 0
        while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation(); total += bytes.count
            guard total <= maximumBytes else { throw DataError.invalidBackup }; digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func write(_ bytes: Data, to file: URL, cancellation: BackupCancellation,
                              progress: @Sendable (BackupProgress) -> Void) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: attributes) else { throw DataError.invalidBackup }
        let handle = try FileHandle(forWritingTo: file)
        do {
            var offset = 0
            while offset < bytes.count {
                try cancellation.check(); let end = min(offset + 64 * 1024, bytes.count)
                try handle.write(contentsOf: bytes.subdata(in: offset..<end)); offset = end
                progress(.init(phase: .writing, completedUnits: Int64(offset), totalUnits: Int64(bytes.count)))
            }
            try handle.synchronize(); try handle.close(); try cancellation.check()
        } catch { try? handle.close(); throw error }
    }
}
