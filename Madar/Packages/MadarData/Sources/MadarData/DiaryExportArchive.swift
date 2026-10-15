import Foundation

/// Plain, open diary bundles. Reuses the bounded ZIP writer without exporting the store.
public enum DiaryExportArchive {
    public static func encode(_ files: [String: Data]) throws -> Data { try PortableZIP.encode(files) }
    public static func files(_ data: Data) throws -> [String: Data] { try PortableZIP.decode(data) }
}
