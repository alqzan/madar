import Foundation
import Compression

public enum ZIPReaderError: Error, Equatable, Sendable {
    case notZIP, corrupt, unsupportedMethod(UInt16), encrypted, tooLarge, unsafePath, checksum
}

/// Read-only ZIP access for imported archives (Day One exports, Madar's own V10 bundles).
/// Reads the central directory (sizes in local headers are unreliable with data descriptors), supports
/// stored and raw-DEFLATE members, ZIP64 sizes/offsets, and inflates one member at a time into a bounded buffer.
/// The archive bytes are memory-mapped, never copied whole into memory.
public struct ZIPReader: Sendable {
    public struct Member: Equatable, Sendable {
        public let path: String
        public let size: Int
        public let compressedSize: Int
        public let method: UInt16
        let crc: UInt32
        let localOffset: Int
        public let flags: UInt16
        public let externalAttributes: UInt32
        public let isSymbolicLink: Bool
        public var isEncrypted: Bool { flags & (0x0001 | 0x0040 | 0x2000) != 0 }
        public var isDirectory: Bool { path.hasSuffix("/") }
    }
    private let data: Data
    public let members: [Member]
    private let index: [String: Int]
    /// Largest single member Madar will inflate into memory (one file at a time on a phone); anything above is
    /// refused and reported, never truncated.
    public static let memberLimit = 512 * 1024 * 1024

    public init(url: URL) throws {
        let mapped = try Data(contentsOf: url, options: .alwaysMapped)
        try self.init(data: mapped)
    }

    public init(data input: Data) throws {
        let data = input.startIndex == 0 ? input : Data(input)
        self.data = data
        guard data.count >= 22 else { throw ZIPReaderError.notZIP }
        // End of central directory: search the last 64 KiB + record size.
        var eocd = -1
        var cursor = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while cursor >= floor { if Self.u32(data, cursor) == 0x06054b50 { eocd = cursor; break }; cursor -= 1 }
        guard eocd >= 0 else { throw ZIPReaderError.notZIP }
        var count = Int(Self.u16(data, eocd + 10))
        var centralSize = Int(Self.u32(data, eocd + 12))
        var centralOffset = Int(Self.u32(data, eocd + 16))
        if count == 0xFFFF || centralSize == 0xFFFF_FFFF || centralOffset == 0xFFFF_FFFF {
            // ZIP64 end-of-central-directory locator sits 20 bytes before the classic record.
            let locator = eocd - 20
            guard locator >= 0, Self.u32(data, locator) == 0x07064b50 else { throw ZIPReaderError.corrupt }
            let record = Int(Self.u64(data, locator + 8))
            guard record >= 0, record + 56 <= data.count, Self.u32(data, record) == 0x06064b50 else { throw ZIPReaderError.corrupt }
            count = Int(Self.u64(data, record + 32)); centralSize = Int(Self.u64(data, record + 40)); centralOffset = Int(Self.u64(data, record + 48))
        }
        guard centralOffset >= 0, centralSize >= 0, centralOffset + centralSize <= data.count, count < 1_000_000 else { throw ZIPReaderError.corrupt }
        var members: [Member] = []; members.reserveCapacity(count)
        var at = centralOffset
        var seen = Set<String>()
        for _ in 0..<count {
            guard at + 46 <= data.count, Self.u32(data, at) == 0x02014b50 else { throw ZIPReaderError.corrupt }
            let madeBy = Self.u16(data, at + 4)
            let flags = Self.u16(data, at + 8), method = Self.u16(data, at + 10), crc = Self.u32(data, at + 16)
            let externalAttributes = Self.u32(data, at + 38)
            var compressed = Int(Self.u32(data, at + 20)), size = Int(Self.u32(data, at + 24))
            let nameLength = Int(Self.u16(data, at + 28)), extraLength = Int(Self.u16(data, at + 30)), commentLength = Int(Self.u16(data, at + 32))
            var offset = Int(Self.u32(data, at + 42))
            let nameStart = at + 46
            guard nameStart + nameLength + extraLength + commentLength <= data.count else { throw ZIPReaderError.corrupt }
            let nameBytes = data.subdata(in: nameStart..<nameStart + nameLength)
            // Bit 11 = UTF-8. Older tools write CP437; Day One writes UTF-8 either way, so fall back to Latin-1 rather than fail.
            let path = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
            // ZIP64 extended information: only the fields saturated in the fixed record are present, in this order.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let tag = Self.u16(data, extra), length = Int(Self.u16(data, extra + 2))
                if tag == 0x0001 {
                    var field = extra + 4
                    if size == 0xFFFF_FFFF, field + 8 <= extra + 4 + length { size = Int(Self.u64(data, field)); field += 8 }
                    if compressed == 0xFFFF_FFFF, field + 8 <= extra + 4 + length { compressed = Int(Self.u64(data, field)); field += 8 }
                    if offset == 0xFFFF_FFFF, field + 8 <= extra + 4 + length { offset = Int(Self.u64(data, field)) }
                }
                extra += 4 + length
            }
            at = extraEnd + commentLength
            guard Self.safe(path) else { throw ZIPReaderError.unsafePath }
            guard size >= 0, compressed >= 0, offset >= 0, offset < data.count, seen.insert(path).inserted else { throw ZIPReaderError.corrupt }
            let host = madeBy >> 8
            let unixMode = UInt16((externalAttributes >> 16) & 0xFFFF)
            let isSymbolicLink = (host == 3 || host == 19) && unixMode & 0xF000 == 0xA000
            members.append(.init(path: path, size: size, compressedSize: compressed, method: method, crc: crc,
                                 localOffset: offset, flags: flags, externalAttributes: externalAttributes, isSymbolicLink: isSymbolicLink))
        }
        self.members = members
        self.index = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($1.path, $0) })
    }

    public func member(_ path: String) -> Member? { index[path].map { members[$0] } }

    /// Inflates one member and verifies its size and CRC-32. Never returns a partial file.
    public func read(_ member: Member) throws -> Data {
        guard !member.isEncrypted else { throw ZIPReaderError.encrypted }
        guard member.size <= Self.memberLimit, member.compressedSize <= data.count else { throw ZIPReaderError.tooLarge }
        let local = member.localOffset
        guard local + 30 <= data.count, Self.u32(data, local) == 0x04034b50 else { throw ZIPReaderError.corrupt }
        let localFlags = Self.u16(data, local + 6), localMethod = Self.u16(data, local + 8)
        let nameLength = Int(Self.u16(data, local + 26)), extraLength = Int(Self.u16(data, local + 28))
        guard localFlags == member.flags, localMethod == member.method,
              local + 30 + nameLength + extraLength <= data.count else { throw ZIPReaderError.corrupt }
        let localName = data.subdata(in: (local + 30)..<(local + 30 + nameLength))
        let localPath = String(data: localName, encoding: .utf8) ?? String(data: localName, encoding: .isoLatin1) ?? ""
        guard localPath == member.path else { throw ZIPReaderError.corrupt }
        let start = local + 30 + nameLength + extraLength
        guard start + member.compressedSize <= data.count else { throw ZIPReaderError.corrupt }
        let output: Data
        switch member.method {
        case 0:
            guard member.compressedSize == member.size else { throw ZIPReaderError.corrupt }
            output = data.subdata(in: start..<start + member.size)
        case 8:
            output = try Self.inflate(data, range: start..<start + member.compressedSize, expected: member.size)
        default: throw ZIPReaderError.unsupportedMethod(member.method)
        }
        guard output.count == member.size, CRC32.checksum(output) == member.crc else { throw ZIPReaderError.checksum }
        return output
    }

    /// Raw DEFLATE (RFC 1951) through Apple's Compression framework, bounded by the declared size so a lying
    /// header cannot inflate past it.
    static func inflate(_ data: Data, range: Range<Int>, expected: Int) throws -> Data {
        if expected == 0 { return Data() }
        var output = Data(count: expected)
        let status: compression_status = data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
                defer { stream.deallocate() }
                guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return COMPRESSION_STATUS_ERROR }
                defer { compression_stream_destroy(stream) }
                stream.pointee.src_ptr = source.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: range.lowerBound)
                stream.pointee.src_size = range.count
                stream.pointee.dst_ptr = target.baseAddress!.assumingMemoryBound(to: UInt8.self)
                stream.pointee.dst_size = expected
                var result = COMPRESSION_STATUS_OK
                while result == COMPRESSION_STATUS_OK {
                    result = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    if stream.pointee.dst_size == 0 && result == COMPRESSION_STATUS_OK {
                        // Output is full but the stream claims more: the header lied about the size.
                        return stream.pointee.src_size == 0 ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_ERROR
                    }
                }
                return result == COMPRESSION_STATUS_END && stream.pointee.dst_size == 0 ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_ERROR
            }
        }
        guard status == COMPRESSION_STATUS_END else { throw ZIPReaderError.corrupt }
        return output
    }

    static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.contains(":")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
    private static func u16(_ d: Data, _ i: Int) -> UInt16 { guard i + 2 <= d.count else { return 0 }; return UInt16(d[i]) | UInt16(d[i + 1]) << 8 }
    private static func u32(_ d: Data, _ i: Int) -> UInt32 { guard i + 4 <= d.count else { return 0 }; return (0..<4).reduce(0) { $0 | UInt32(d[i + $1]) << (8 * $1) } }
    private static func u64(_ d: Data, _ i: Int) -> UInt64 { guard i + 8 <= d.count else { return 0 }; return (0..<8).reduce(0) { $0 | UInt64(d[i + $1]) << (8 * $1) } }
}

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n); for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }; return c
    }
    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
