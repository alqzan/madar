import Foundation
import SwiftData
import CryptoKit
import CommonCrypto
import AppleArchive
import System

public struct BackupManifest: Codable, Sendable {
    public struct File: Codable, Sendable { public let path: String; public let bytes: Int; public let sha256: String }
    public let formatVersion: Int; public let storeSchemaVersion: Int; public let createdAt: Date; public let counts: [String:Int]; public let files: [File]
}
struct BackupHeader: Codable {
    let magic: String; let formatVersion: Int; let appVersion: String; let storeSchemaVersion: Int; let createdAt: Date
    struct KDF: Codable { let alg: String; let iterations: Int; let salt: Data }
    let kdf: KDF; let cipher: String; let chunkSize: Int; let chunkCount: Int; let noncePrefix: Data
}
public struct ValidatedBackup: Sendable { public let manifest: BackupManifest; public let records: [DataRecord] }
/// Authenticated Apple Archive, staged and validated before a destination context is changed.
public enum BackupCodec {
    private static let chunkSize = 1024*1024
    private static let maximumBytes = 512*1024*1024
    public static func export(records: [DataRecord], passphrase: String, appVersion: String = "0.1", now: Date = Date()) throws -> Data {
        guard passphrase.count >= 10 else { throw DataError.invalidBackup }
        let archive = try archive(records:records,now:now)
        let credential = try BackupCredential.derive(passphrase:passphrase)
        return try seal(archive:archive,credential:credential,noncePrefix:random(count:4),appVersion:appVersion,now:now)
    }
    static func seal(archive: Data, credential: BackupCredential, noncePrefix: Data, appVersion: String = "0.1", now: Date = Date(), formatVersion: Int = 1, cancellation: BackupCancellation = BackupCancellation(), progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> Data {
        guard archive.count <= maximumBytes, credential.salt.count == 16, credential.keyData.count == 32, noncePrefix.count == 4 else { throw DataError.invalidBackup }
        let count = max(1,(archive.count+chunkSize-1)/chunkSize)
        let header = BackupHeader(magic:"MADARBK",formatVersion:formatVersion,appVersion:appVersion,storeSchemaVersion:MadarSchema.version,createdAt:now,kdf:.init(alg:"PBKDF2-HMAC-SHA256",iterations:600000,salt:credential.salt),cipher:"AES-256-GCM",chunkSize:chunkSize,chunkCount:count,noncePrefix:noncePrefix)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let headerBytes = try encoder.encode(header)
        let key = SymmetricKey(data:credential.keyData)
        var output = integer(UInt64(headerBytes.count),bytes:4); output.append(headerBytes)
        for index in 0..<count {
            try cancellation.check()
            let range = index*chunkSize..<min((index+1)*chunkSize,archive.count)
            let nonce = try AES.GCM.Nonce(data:header.noncePrefix+integer(UInt64(index),bytes:8))
            let aad = headerBytes+integer(UInt64(index),bytes:8)+Data([index == count-1 ? 1 : 0])
            let sealed = try AES.GCM.seal(archive.subdata(in:range),using:key,nonce:nonce,authenticating:aad)
            let payload = sealed.ciphertext+sealed.tag; output.append(integer(UInt64(payload.count),bytes:4)); output.append(payload)
            progress(.init(phase:.encrypting,completedUnits:Int64(index+1),totalUnits:Int64(count)))
        }
        return output
    }
    /// Plaintext preparation used by the asynchronous file coordinator and authenticated malformed-archive tests.
    static func archive(records: [DataRecord], now: Date = Date()) throws -> Data {
        try encodeArchive(contentFiles(records: records, now: now))
    }
    /// Shared logical representation; never contains the device store or SQLite files.
    /// With `mediaSink`, each media file is handed over as soon as it is decoded and verified and is not kept: the caller seals or writes it,
    /// so only one decoded file is alive at a time instead of every photo, recording and book at once (B1-15). The manifest still lists
    /// every media file, so the archive's index is byte-for-byte what the all-in-memory call produces without the media entries.
    static func contentFiles(records: [DataRecord], now: Date = Date(), mediaSink: ((String, Data) throws -> Void)? = nil) throws -> [String: Data] {
        guard records.allSatisfy({ MadarSchema.syncedNames.contains($0.model) }) else { throw DataError.invalidBackup }
        var files: [String:Data] = [:]; var persisted = records
        var sunk: [BackupManifest.File] = []
        for i in persisted.indices.filter({ persisted[$0].model == "Media" }).sorted(by: { persisted[$0].id.uuidString < persisted[$1].id.uuidString }) {
            if let bytes = try? persisted[i].decode("data",as:Data.self) {
                let digest = hash(bytes)
                guard digest == persisted[i].fields["sha256"]?.string, bytes.count == Int(persisted[i].fields["sizeBytes"]?.number ?? -1) else { throw DataError.invalidBackup }
                let path = "media/\(persisted[i].id.uuidString)"
                if let mediaSink { sunk.append(.init(path:path,bytes:bytes.count,sha256:digest)); try mediaSink(path,bytes) } else { files[path] = bytes }
                persisted[i].fields["data"] = .null
            } else if persisted[i].isLive && persisted[i].fields["state"] == .string("ok") { throw DataError.invalidBackup }
        }
        for model in MadarSchema.syncedNames {
            var bytes = Data()
            for row in persisted.filter({ $0.model == model }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) { bytes.append(try JSONValue.object(row.fields).canonicalData()); bytes.append(0x0a) }
            files["data/\(model).jsonl"] = bytes
        }
        let manifest = BackupManifest(formatVersion:1,storeSchemaVersion:MadarSchema.version,createdAt:now,counts:Dictionary(uniqueKeysWithValues:MadarSchema.syncedNames.map { model in (model,records.filter { $0.model == model }.count) }),files:(files.map { BackupManifest.File(path:$0.key,bytes:$0.value.count,sha256:hash($0.value)) }+sunk).sorted { $0.path < $1.path })
        files["manifest.json"] = try JSONEncoder().encode(manifest)
        return files
    }
    @MainActor public static func validate(_ backup: Data, passphrase: String) throws -> ValidatedBackup {
        let result = try validateContents(backup,passphrase:passphrase)
        try validateTypedRows(result.records); return result
    }
    static func validateContents(_ backup: Data, passphrase: String? = nil, credential: BackupCredential? = nil, cancellation: BackupCancellation = BackupCancellation(), progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> ValidatedBackup {
        let opened = try openArchive(backup, passphrase: passphrase, credential: credential, cancellation: cancellation, progress: progress)
        guard let bytes = opened.files["manifest.json"] else { throw DataError.invalidBackup }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: bytes)
        guard manifest.storeSchemaVersion == opened.header.storeSchemaVersion else { throw DataError.invalidBackup }
        let sourceModels = try SchemaCompatibility.modelNames(version: opened.header.storeSchemaVersion)
        return try validateFiles(opened.files, manifest: manifest, sourceModels: sourceModels, cancellation: cancellation, progress: progress)
    }
    /// Shared authenticated envelope. Version 2 is used only by the self-contained
    /// incremental package index; a naked index cannot be restored as a v1 file.
    static func openArchive(_ backup: Data, passphrase: String? = nil, credential: BackupCredential? = nil,
                            formatVersion: Int = 1, cancellation: BackupCancellation = BackupCancellation(),
                            progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> (files: [String: Data], header: BackupHeader, credential: BackupCredential) {
        try cancellation.check()
        guard backup.count <= maximumBytes else { throw DataError.invalidBackup }
        var offset = 0
        func take(_ count: Int) throws -> Data { guard count >= 0, offset <= backup.count-count else { throw DataError.invalidBackup }; defer { offset += count }; return backup.subdata(in:offset..<offset+count) }
        func size() throws -> Int { Int(try take(4).reduce(UInt64(0)) { ($0<<8)|UInt64($1) }) }
        let headerLength = try size(); guard (1...65536).contains(headerLength) else { throw DataError.invalidBackup }
        let headerBytes = try take(headerLength); let header = try JSONDecoder().decode(BackupHeader.self,from:headerBytes)
        guard header.magic == "MADARBK", header.formatVersion == formatVersion, header.cipher == "AES-256-GCM", header.kdf.alg == "PBKDF2-HMAC-SHA256", header.kdf.iterations == 600000, header.kdf.salt.count == 16, header.noncePrefix.count == 4, header.chunkSize == chunkSize, (1...512).contains(header.chunkCount) else { throw DataError.unsupportedBackup }
        guard header.storeSchemaVersion <= MadarSchema.version else { throw DataError.newerStore }
        let key: SymmetricKey
        if let passphrase { key = try derive(passphrase:passphrase,salt:header.kdf.salt,iterations:header.kdf.iterations) }
        else if let credential, credential.salt == header.kdf.salt, credential.keyData.count == 32 { key = SymmetricKey(data:credential.keyData) }
        else { throw BackupOperationError.backupNotConfigured }
        var archive = Data()
        for index in 0..<header.chunkCount {
            try cancellation.check()
            let length = try size(); guard (16...chunkSize+16).contains(length), index == header.chunkCount-1 || length == chunkSize+16 else { throw DataError.invalidBackup }
            let payload = try take(length); let nonce = try AES.GCM.Nonce(data:header.noncePrefix+integer(UInt64(index),bytes:8))
            let box = try AES.GCM.SealedBox(nonce:nonce,ciphertext:payload.dropLast(16),tag:payload.suffix(16))
            let aad = headerBytes+integer(UInt64(index),bytes:8)+Data([index == header.chunkCount-1 ? 1 : 0])
            do { archive.append(try AES.GCM.open(box,using:key,authenticating:aad)) } catch { throw DataError.authenticationFailed }
            progress(.init(phase:.decrypting,completedUnits:Int64(index+1),totalUnits:Int64(header.chunkCount)))
        }
        guard offset == backup.count else { throw DataError.invalidBackup }
        let openedCredential = BackupCredential(salt: header.kdf.salt, keyData: key.withUnsafeBytes { Data($0) }, nextNonceCounter: 0)
        return (try decodeArchive(archive), header, openedCredential)
    }
    static func validateFiles(_ files: [String: Data], manifest: BackupManifest, sourceModels: [String], hydrateMedia: Bool = true, cancellation: BackupCancellation = BackupCancellation(), progress: @Sendable (BackupProgress) -> Void = { _ in }) throws -> ValidatedBackup {
        guard manifest.formatVersion == 1, Set(manifest.counts.keys) == Set(sourceModels), Set(manifest.files.map(\.path)).count == manifest.files.count else { throw DataError.invalidBackup }
        // Without hydration (the write-time check of a package whose media were already verified one by one) media bytes are absent by design.
        let carried = hydrateMedia ? manifest.files : manifest.files.filter { !$0.path.hasPrefix("media/") }
        guard Set(files.keys) == Set(carried.map(\.path)+["manifest.json"]) else { throw DataError.invalidBackup }
        for file in carried { guard let data = files[file.path], data.count == file.bytes, hash(data) == file.sha256 else { throw DataError.invalidBackup } }
        var records: [DataRecord] = []
        for model in sourceModels {
            guard let data = files["data/\(model).jsonl"] else { throw DataError.invalidBackup }
            let lines = data.split(separator:0x0a,omittingEmptySubsequences:true)
            guard manifest.counts[model] == lines.count else { throw DataError.invalidBackup }
            for line in lines { let fields = try JSONDecoder().decode([String:JSONValue].self,from:Data(line)); var row = DataRecord(model:model,fields:fields)
                guard UUID(uuidString:fields["id"]?.string ?? "") != nil else { throw DataError.invalidBackup }
                if model == "Media", !hydrateMedia { /* verified object by object by the caller */ }
                else if model == "Media", let media = files["media/\(row.id.uuidString)"] { guard hash(media) == row.fields["sha256"]?.string, media.count == Int(row.fields["sizeBytes"]?.number ?? -1) else { throw DataError.invalidBackup }; try row.set(media,for:"data") }
                else if model == "Media", row.isLive && row.fields["state"] == .string("ok") { throw DataError.invalidBackup }
                records.append(row)
            }
        }
        let allowedPaths = Set(sourceModels.map { "data/\($0).jsonl" } + (hydrateMedia ? records.filter { $0.model == "Media" && $0.fields["data"] != .null }.map { "media/\($0.id.uuidString)" } : manifest.files.map(\.path).filter { $0.hasPrefix("media/") }))
        guard Set(manifest.files.map(\.path)) == allowedPaths else { throw DataError.invalidBackup }
        records = try SchemaCompatibility.currentRecords(records,from:manifest.storeSchemaVersion)
        // Decode every stored property through generated typed models in an isolated validation container.
        try RecordValidator.validate(records)
        try cancellation.check()
        progress(.init(phase:.validating,completedUnits:Int64(records.count),totalUnits:Int64(records.count)))
        return ValidatedBackup(manifest:manifest,records:records)
    }
    @MainActor static func validateTypedRows(_ rows: [DataRecord]) throws {
        let container = try MadarContainerFactory.makeInMemory(); let context = ModelContext(container); context.autosaveEnabled = false
        for row in rows { try RecordBridge.upsert(row,in:context) }
        context.rollback()
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    static func integer(_ value: UInt64, bytes: Int) -> Data { Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded:value >> ($0*8)) }) }
    static func random(count: Int) -> Data { var generator = SystemRandomNumberGenerator(); return Data((0..<count).map { _ in UInt8.random(in:.min ... .max,using:&generator) }) }
    static func derive(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var key = Data(count:32); let password = Array(passphrase.utf8)
        guard !password.isEmpty else { throw DataError.authenticationFailed }
        let result = key.withUnsafeMutableBytes { output in salt.withUnsafeBytes { saltBytes in password.withUnsafeBytes { passwordBytes in CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),passwordBytes.baseAddress!.assumingMemoryBound(to:CChar.self),password.count,saltBytes.baseAddress!.assumingMemoryBound(to:UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),UInt32(iterations),output.baseAddress!.assumingMemoryBound(to:UInt8.self),32) } } }
        guard result == kCCSuccess else { throw DataError.invalidBackup }; return SymmetricKey(data:key)
    }
    private static func temporary() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarBackup-\(UUID())"); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); return url }
    static func encodeArchive(_ files: [String:Data]) throws -> Data {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }; let url = directory.appendingPathComponent("archive.aar")
        guard let bytes = ArchiveByteStream.fileStream(path:FilePath(url.path),mode:.writeOnly,options:[.create,.truncate],permissions:.ownerReadWrite), let archive = ArchiveStream.encodeStream(writingTo:bytes) else { throw DataError.invalidBackup }
        do {
            for (path,data) in files.sorted(by: { $0.key < $1.key }) {
                let header = ArchiveHeader(); header.append(.uint(key:.init("TYP"),value:UInt64(UInt8(ascii:"F")))); header.append(.string(key:.init("PAT"),value:path)); header.append(.blob(key:.init("DAT"),size:UInt64(data.count)))
                try archive.writeHeader(header); try data.withUnsafeBytes { try archive.writeBlob(key:.init("DAT"),from:$0) }
            }
            try archive.close(); try bytes.close(); return try Data(contentsOf:url)
        } catch { try? archive.close(); try? bytes.close(); throw error }
    }
    static func decodeArchive(_ data: Data) throws -> [String:Data] {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }; let url = directory.appendingPathComponent("archive.aar"); try data.write(to:url)
        guard let bytes = ArchiveByteStream.fileStream(path:FilePath(url.path),mode:.readOnly,options:[],permissions:.ownerReadWrite), let archive = ArchiveStream.decodeStream(readingFrom:bytes) else { throw DataError.invalidBackup }
        defer { try? archive.close(); try? bytes.close() }; var files: [String:Data] = [:]; var total = 0
        while let header = try archive.readHeader() {
            guard case .string(_,let path) = header.field(forKey:.init("PAT")), case .uint(_,let type) = header.field(forKey:.init("TYP")), type == UInt64(UInt8(ascii:"F")), case .blob(_,let size,_) = header.field(forKey:.init("DAT")), size <= maximumBytes, !path.hasPrefix("/"), !path.split(separator:"/").contains(".."), files[path] == nil, files.count < 100000 else { throw DataError.invalidBackup }
            total += Int(size); guard total <= maximumBytes else { throw DataError.invalidBackup }
            var payload = Data(count:Int(size)); try payload.withUnsafeMutableBytes { try archive.readBlob(key:.init("DAT"),into:$0) }; files[path] = payload
        }
        return files
    }
}
@MainActor public enum BackupRestore {
    /// Verified merge into an isolated context. A replace of existing user data requires the higher-level automatic-backup/snapshot coordinator.
    @discardableResult public static func merge(_ backup: ValidatedBackup, into context: ModelContext) throws -> Int {
        do {
            let existing = try RecordBridge.all(context); var combined = existing
            for incoming in backup.records {
                if let i = combined.firstIndex(where: { $0.model == incoming.model && $0.id == incoming.id && $0.fields["mergedInto"] == incoming.fields["mergedInto"] }) {
                    if combined[i] == incoming { continue }
                    combined[i] = try RowMerger.mergeVersions(combined[i],incoming)
                } else { combined.append(incoming) }
            }
            let reconciled = try RowMerger.reconciled(combined); let changes = reconciled.filter { !existing.contains($0) }
            for row in changes { try RecordBridge.upsert(row,in:context) }
            if !changes.isEmpty { try context.save() }; return changes.count
        } catch { context.rollback(); throw error }
    }
}
