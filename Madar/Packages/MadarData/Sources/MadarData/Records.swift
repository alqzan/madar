import Foundation
import CryptoKit

public enum DataError: Error, Equatable { case unknownModel(String), invalidValue(String), newerStore, legacyStoreRequiresAdoption, missingAppGroup, undoExpired, invalidBackup, authenticationFailed, unsupportedBackup }
public enum JSONValue: Codable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .bool(let v): try c.encode(v); case .number(let v): try c.encode(v); case .string(let v): try c.encode(v); case .array(let v): try c.encode(v); case .object(let v): try c.encode(v) }
    }
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: canonicalData()) }
    public func canonicalData() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try e.encode(self) }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
}
public struct DataRecord: Codable, Hashable, Sendable {
    public var model: String
    public var fields: [String: JSONValue]
    public init(model: String, fields: [String: JSONValue]) { self.model = model; self.fields = fields }
    public var id: UUID { UUID(uuidString: fields["id"]?.string ?? "") ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) }
    public var deletedAt: Date? { try? fields["deletedAt"]?.decode(Date.self) }
    public var isLive: Bool { deletedAt == nil && fields["mergedInto"]?.string == nil }
    public func decode<T: Decodable>(_ field: String, as type: T.Type) throws -> T { guard let value = fields[field] else { throw DataError.invalidValue("\(model).\(field) missing") }; return try value.decode(type) }
    public mutating func set<T: Encodable>(_ value: T, for field: String) throws { fields[field] = try JSONValue.encode(value) }
    public func date(_ field: String) -> Date? { try? fields[field]?.decode(Date.self) }
}
public enum StableIdentity {
    public static let namespace = UUID(uuidString: "2103b223-aa33-4c73-bab6-b2adaed8603e")!
    public static func uuid(for name: String) -> UUID {
        var ns = namespace.uuid
        let bytes = withUnsafeBytes(of: &ns) { Data($0) } + Data(name.utf8)
        var digest = Array(Insecure.SHA1.hash(data: bytes).prefix(16)); digest[6] = (digest[6] & 0x0f) | 0x50; digest[8] = (digest[8] & 0x3f) | 0x80
        return UUID(uuid: (digest[0],digest[1],digest[2],digest[3],digest[4],digest[5],digest[6],digest[7],digest[8],digest[9],digest[10],digest[11],digest[12],digest[13],digest[14],digest[15]))
    }
    public static func dayOneBranch(canonicalSource: Data) -> String { SHA256.hash(data: canonicalSource).map { String(format: "%02x", $0) }.joined() }
    public static func monotonic(now: Date, previous: Date) -> Date { max(now, previous.addingTimeInterval(0.001)) }
}
