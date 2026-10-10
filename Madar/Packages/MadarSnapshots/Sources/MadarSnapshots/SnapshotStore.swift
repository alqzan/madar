import Foundation

public struct SnapshotPrivacy: Codable, Sendable, Equatable {
    public var moneyHidden: Bool
    public var notesLocked: Bool
    public init(moneyHidden: Bool = true, notesLocked: Bool = true) {
        self.moneyHidden = moneyHidden; self.notesLocked = notesLocked
    }
}

public struct SnapshotEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public var name: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var validUntil: Date
    public var dayKey: String
    public var tzID: String
    public var privacy: SnapshotPrivacy
    public var payload: Payload
    public init(name: String, schemaVersion: Int = 1, generatedAt: Date, validUntil: Date, dayKey: String, tzID: String, privacy: SnapshotPrivacy, payload: Payload) {
        self.name = name; self.schemaVersion = schemaVersion; self.generatedAt = generatedAt
        self.validUntil = validUntil; self.dayKey = dayKey; self.tzID = tzID
        self.privacy = privacy; self.payload = payload
    }
}

/// Widgets read complete files only. They never open SwiftData or request location.
public struct SnapshotStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func appGroup(_ identifier: String) throws -> Self {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SnapshotError.appGroupUnavailable
        }
        return Self(directory: root.appending(path: "Snapshots", directoryHint: .isDirectory))
    }
    private func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            throw SnapshotError.invalidName
        }
        return directory.appending(path: name + ".json")
    }
    public func write<P>(_ snapshot: SnapshotEnvelope<P>) throws {
        let url = try file(snapshot.name)
        guard snapshot.schemaVersion == 1, snapshot.validUntil >= snapshot.generatedAt,
              TimeZone(identifier: snapshot.tzID) != nil else { throw SnapshotError.invalidEnvelope }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func read<P>(_ name: String, as: P.Type, now: Date = Date()) -> SnapshotEnvelope<P>? {
        guard let url = try? file(name), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(SnapshotEnvelope<P>.self, from: data),
              value.name == name, value.schemaVersion == 1,
              value.generatedAt <= now, value.validUntil > now,
              TimeZone(identifier: value.tzID) != nil else { return nil }
        return value
    }
    public func remove(_ name: String) throws {
        let url = try file(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
public enum SnapshotError: Error { case appGroupUnavailable, invalidName, invalidEnvelope }

/// Foundation-only snapshot contains no room content and no personal records.
public struct FoundationSnapshot: Codable, Sendable, Equatable {
    public var firstCalendar: String
    public var numerals: String
    public init(firstCalendar: String, numerals: String) {
        self.firstCalendar = firstCalendar; self.numerals = numerals
    }
}
