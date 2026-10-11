import Foundation

/// An open ZIP of UTF-8 JSONL and original media. It contains personal data without encryption.
public struct PortableExportManifest: Codable, Sendable {
    public let magic: String
    public let formatVersion: Int
    public let storeSchemaVersion: Int
    public let createdAt: Date
    public let counts: [String: Int]
    public let files: [BackupManifest.File]
}

public enum PortableExportCodec {
    public static func export(records: [DataRecord], now: Date = Date(), cancellation: BackupCancellation = BackupCancellation()) throws -> Data {
        try cancellation.check()
        try RecordValidator.validate(records)
        var files = try BackupCodec.contentFiles(records: records, now: now)
        let logical = try JSONDecoder().decode(BackupManifest.self, from: files["manifest.json"]!)
        let manifest = PortableExportManifest(magic: "MADAR-PLAIN", formatVersion: 1,
            storeSchemaVersion: logical.storeSchemaVersion, createdAt: now, counts: logical.counts, files: logical.files)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        files["manifest.json"] = try encoder.encode(manifest)
        return try PortableZIP.encode(files, cancellation: cancellation)
    }

    /// Validates in memory and in an isolated container. This never opens or mutates a live store.
    @MainActor public static func validate(_ data: Data) throws -> ValidatedBackup {
        let result = try validateContents(data)
        try BackupCodec.validateTypedRows(result.records)
        return result
    }

    static func validateContents(_ data: Data, cancellation: BackupCancellation = BackupCancellation()) throws -> ValidatedBackup {
        let files = try PortableZIP.decode(data, cancellation: cancellation)
        guard let bytes = files["manifest.json"] else { throw DataError.invalidBackup }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PortableExportManifest.self, from: bytes)
        guard manifest.magic == "MADAR-PLAIN", manifest.formatVersion == 1 else { throw DataError.unsupportedBackup }
        guard manifest.storeSchemaVersion <= MadarSchema.version else { throw DataError.newerStore }
        // The initial plain format starts with the corrected model names; legacy encrypted backups keep their own decoder.
        guard manifest.storeSchemaVersion == MadarSchema.version else { throw DataError.unsupportedBackup }
        let logical = BackupManifest(formatVersion: 1, storeSchemaVersion: manifest.storeSchemaVersion,
            createdAt: manifest.createdAt, counts: manifest.counts, files: manifest.files)
        return try BackupCodec.validateFiles(files, manifest: logical, sourceModels: MadarSchema.syncedNames, cancellation: cancellation)
    }
}

/// ZIP method 0 (stored), with standard central directory and CRC-32. External tools can unpack it.
/// The bounded reader accepts this format only; it never extracts paths to the filesystem.
enum PortableZIP {
    private static let maximumBytes = 512 * 1024 * 1024
    private struct Entry: Equatable {
        let path: String; let size: Int; let crc: UInt32; let offset: Int
    }
    static func encode(_ files: [String: Data], cancellation: BackupCancellation = BackupCancellation()) throws -> Data {
        guard files.count < 65535 else { throw DataError.invalidBackup }
        var output = Data(); var entries: [Entry] = []
        for (path, bytes) in files.sorted(by: { $0.key < $1.key }) {
            try cancellation.check()
            let name = Data(path.utf8)
            guard safe(path), name.count <= 65535, bytes.count <= maximumBytes,
                  output.count <= maximumBytes - bytes.count - name.count - 30 else { throw DataError.invalidBackup }
            let entry = Entry(path: path, size: bytes.count, crc: crc32(bytes), offset: output.count); entries.append(entry)
            output += le(0x04034b50, 4) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(33, 2)
            output += le(UInt64(entry.crc), 4) + le(UInt64(bytes.count), 4) + le(UInt64(bytes.count), 4)
            output += le(UInt64(name.count), 2) + le(0, 2) + name + bytes
        }
        let centralStart = output.count
        for entry in entries {
            try cancellation.check()
            let name = Data(entry.path.utf8)
            output += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(33, 2)
            output += le(UInt64(entry.crc), 4) + le(UInt64(entry.size), 4) + le(UInt64(entry.size), 4)
            output += le(UInt64(name.count), 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 4) + le(UInt64(entry.offset), 4) + name
        }
        let centralSize = output.count - centralStart
        output += le(0x06054b50, 4) + le(0, 2) + le(0, 2) + le(UInt64(entries.count), 2) + le(UInt64(entries.count), 2)
        output += le(UInt64(centralSize), 4) + le(UInt64(centralStart), 4) + le(0, 2)
        guard output.count <= maximumBytes else { throw DataError.invalidBackup }
        try cancellation.check(); return output
    }
    static func decode(_ data: Data, cancellation: BackupCancellation = BackupCancellation()) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumBytes else { throw DataError.invalidBackup }
        var cursor = 0
        func take(_ count: Int) throws -> Data {
            guard count >= 0, cursor <= data.count - count else { throw DataError.invalidBackup }
            defer { cursor += count }; return data.subdata(in: cursor..<cursor + count)
        }
        func number(_ count: Int) throws -> UInt64 {
            try take(count).enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        func name(_ count: Int) throws -> String {
            guard let path = String(data: try take(count), encoding: .utf8), safe(path) else { throw DataError.invalidBackup }
            return path
        }
        var entries: [Entry] = []; var files: [String: Data] = [:]
        var signature = try number(4)
        while signature == 0x04034b50 {
            try cancellation.check()
            let offset = cursor - 4
            guard try number(2) == 20, try number(2) == 0x800, try number(2) == 0 else { throw DataError.invalidBackup }
            _ = try number(4) // DOS date/time is metadata only.
            let crc = UInt32(try number(4)); let size = Int(try number(4)); let uncompressed = Int(try number(4))
            let length = Int(try number(2)); let extra = try number(2)
            guard size == uncompressed, size <= maximumBytes, extra == 0, entries.count < 65535 else { throw DataError.invalidBackup }
            let path = try name(length)
            guard files[path] == nil else { throw DataError.invalidBackup }
            let payload = try take(size)
            guard crc32(payload) == crc else { throw DataError.invalidBackup }
            files[path] = payload; entries.append(.init(path: path, size: size, crc: crc, offset: offset))
            signature = try number(4)
        }
        let centralStart = cursor - 4
        for entry in entries {
            try cancellation.check()
            guard signature == 0x02014b50, try number(2) == 20, try number(2) == 20,
                  try number(2) == 0x800, try number(2) == 0 else { throw DataError.invalidBackup }
            _ = try number(4)
            let crc = UInt32(try number(4)); let size = Int(try number(4)); let uncompressed = Int(try number(4))
            let length = Int(try number(2)); let extra = try number(2); let comment = try number(2)
            guard try number(2) == 0 else { throw DataError.invalidBackup }
            _ = try number(2); _ = try number(4)
            let offset = Int(try number(4)); let path = try name(length)
            guard extra == 0, comment == 0, uncompressed == size,
                  Entry(path: path, size: size, crc: crc, offset: offset) == entry else { throw DataError.invalidBackup }
            signature = try number(4)
        }
        let centralSize = cursor - 4 - centralStart
        guard signature == 0x06054b50, try number(2) == 0, try number(2) == 0,
              try number(2) == UInt64(entries.count), try number(2) == UInt64(entries.count),
              try number(4) == UInt64(centralSize), try number(4) == UInt64(centralStart),
              try number(2) == 0, cursor == data.count else { throw DataError.invalidBackup }
        return files
    }
    private static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func le(_ value: UInt64, _ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        return crc
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
}
