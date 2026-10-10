import Foundation
import CryptoKit

public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { guard v.isFinite else { throw CoreError.invalidCommand }; self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .bool(let v): try c.encode(v); case .number(let v): try c.encode(v); case .string(let v): try c.encode(v); case .array(let v): try c.encode(v); case .object(let v): try c.encode(v) }
    }
    public func canonicalData() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try e.encode(self) }
    public func sha256() throws -> String { SHA256.hash(data: try canonicalData()).map { String(format: "%02x", $0) }.joined() }
}
public enum CommandSource: String, Codable, Sendable { case app, widget, control, siri, shortcut, notification, spotlight, system }
public struct CommandEnvelope: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let name: String
    public let payload: JSONValue
    public let source: CommandSource
    public let issuedAt: Date
    public let schemaVersion: Int
    public init(commandID: UUID = UUID(), name: String, payload: JSONValue, source: CommandSource = .app, issuedAt: Date = Date(), schemaVersion: Int = 1) { self.commandID = commandID; self.name = name; self.payload = payload; self.source = source; self.issuedAt = issuedAt; self.schemaVersion = schemaVersion }
}
public enum CommandStatus: String, Codable, Sendable { case applied, duplicate, rejected, needsUnlock, needsApp }
public struct CommandOutcome: Codable, Equatable, Sendable {
    public let status: CommandStatus
    public let reason: String?
    public let undoToken: UUID?
    public init(status: CommandStatus, reason: String? = nil, undoToken: UUID? = nil) { self.status = status; self.reason = reason; self.undoToken = undoToken }
}
public enum CommandSemantics: String, Codable, Sendable { case append, upsert, preset, undo }
public enum CommandOperation: Codable, Equatable, Sendable {
    case replaceSettings([String: JSONValue])
    case applyPreset(settings: [String: JSONValue], layouts: [String: JSONValue])
    case undo(token: UUID)
    case savePreset(name: String, settings: [String: JSONValue], layouts: [String: JSONValue])
    case completeOnboarding
    case logPrayer(dayKey: String, prayer: Prayer, status: String, heart: String?, shortened: Bool?)
}
public struct CoreCommandReceipt: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let name: String
    public let payloadHash: String
    public let source: CommandSource
    public let issuedAt: Date
    public let appliedAt: Date
    public let expiresAt: Date
    public let undoExpiresAt: Date
    public let undoJSON: Data?
    public let outcome: CommandOutcome
    public init(request: CommandTransactionRequest, now: Date, undoJSON: Data?, outcome: CommandOutcome) {
        commandID = request.envelope.commandID; name = request.envelope.name; payloadHash = request.payloadHash
        source = request.envelope.source; issuedAt = request.envelope.issuedAt; appliedAt = now
        expiresAt = now.addingTimeInterval(7 * 86400)
        undoExpiresAt = now.addingTimeInterval(request.semantics == .preset ? 60 : 600)
        self.undoJSON = undoJSON; self.outcome = outcome
    }
    public func canUndo(at now: Date) -> Bool { undoJSON != nil && outcome.status == .applied && now >= appliedAt && now < undoExpiresAt }
}
public enum CommandDecision: Equatable, Sendable { case replay(CommandOutcome), duplicate, apply }
public struct CommandTransactionRequest: Sendable {
    public let envelope: CommandEnvelope
    public let operation: CommandOperation
    public let semantics: CommandSemantics
    public let payloadHash: String
    public let naturalKey: String?
    public func decision(receipts: [CoreCommandReceipt], existingNaturalPayloadHash: String?, now: Date) -> CommandDecision {
        let live = receipts.filter { $0.expiresAt > now }
        if let receipt = live.first(where: { $0.commandID == envelope.commandID }) { return .replay(receipt.outcome) }
        if semantics == .upsert, naturalKey != nil, existingNaturalPayloadHash == payloadHash { return .duplicate }
        if semantics == .append, live.contains(where: { $0.name == envelope.name && $0.payloadHash == payloadHash && now >= $0.appliedAt && now.timeIntervalSince($0.appliedAt) <= 10 }) { return .duplicate }
        return .apply
    }
}
/// Adapter MUST decide, mutate, store inverse + receipt, and commit in ONE serialized store
/// transaction, including across app/Intent contexts. In-memory bus state is never authoritative.
public protocol CommandStoreAdapter: Sendable {
    func transact(_ request: CommandTransactionRequest, now: Date) async throws -> CommandOutcome
}
public struct CommandBus: Sendable {
    private let adapter: any CommandStoreAdapter
    public init(adapter: any CommandStoreAdapter) { self.adapter = adapter }
    public func execute(_ envelope: CommandEnvelope, now: Date = Date()) async throws -> CommandOutcome {
        guard envelope.schemaVersion == 1, envelope.issuedAt <= now.addingTimeInterval(300), case .object(let payload) = envelope.payload else { return .init(status: .rejected, reason: "invalidCommand") }
        let externalPrayerCommands = ["prayer.log", "prayer.makeUp", "prayer.answerHeart", "prayer.logQiyam"]
        let systemPrayerCommands = ["prayer.agePending", "prayer.initializeTracking"]
        if !externalPrayerCommands.contains(envelope.name), envelope.source != .app,
           !(envelope.source == .system && systemPrayerCommands.contains(envelope.name)) {
            return .init(status: .needsApp, reason: "appOnlyFoundationCommand")
        }
        let operation: CommandOperation; let semantics: CommandSemantics; let naturalKey: String?
        switch envelope.name {
        case "prayer.log":
            guard Set(payload.keys).isSubset(of: ["dayKey", "prayer", "status", "heart", "shortened"]),
                  case .string(let dayKey) = payload["dayKey"], (try? GregorianDay(dayKey)) != nil,
                  case .string(let prayerRaw) = payload["prayer"], let prayer = Prayer(rawValue: prayerRaw),
                  case .string(let status) = payload["status"], ["jamaah", "alone", "qada", "missed"].contains(status) else { return .init(status: .rejected, reason: "invalidPayload") }
            var heart: String?, shortened: Bool?
            if let value = payload["heart"], value != .null {
                guard case .string(let h) = value, ["distracted", "present", "khashi"].contains(h) else { return .init(status: .rejected, reason: "invalidPayload") }
                heart = h
            }
            if let value = payload["shortened"] {
                guard case .bool(let b) = value else { return .init(status: .rejected, reason: "invalidPayload") }
                shortened = b
            }
            if shortened == true && (prayer == .fajr || prayer == .maghrib) { return .init(status: .rejected, reason: "invalidShortening") }
            operation = .logPrayer(dayKey: dayKey, prayer: prayer, status: status, heart: heart, shortened: shortened)
            semantics = .upsert; naturalKey = "prayer." + dayKey + "." + prayer.rawValue
        case "settings.set":
            guard Set(payload.keys) == ["settings"], case .object(let settings) = payload["settings"], !settings.isEmpty else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .replaceSettings(settings); semantics = .upsert
            naturalKey = "settings:" + settings.keys.sorted().joined(separator: ",")
        case "settings.applyPreset":
            guard Set(payload.keys).isSubset(of: ["settings", "layouts"]), case .object(let settings) = payload["settings"], case .object(let layouts) = payload["layouts"] ?? .object([:]) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .applyPreset(settings: settings, layouts: layouts); semantics = .preset; naturalKey = nil
        case "preset.save":
            guard Set(payload.keys) == ["name", "settings", "layouts"], case .string(let name) = payload["name"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, case .object(let settings) = payload["settings"], case .object(let layouts) = payload["layouts"] else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .savePreset(name: name, settings: settings, layouts: layouts); semantics = .append; naturalKey = nil
        case "core.completeOnboarding":
            guard payload.isEmpty else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .completeOnboarding; semantics = .upsert; naturalKey = "sys.onboardingCompleted"
        case "system.undo":
            guard Set(payload.keys) == ["undoToken"], case .string(let token) = payload["undoToken"], let id = UUID(uuidString: token) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .undo(token: id); semantics = .undo; naturalKey = nil
        default: return .init(status: .rejected, reason: "unavailableInM0")
        }
        return try await adapter.transact(CommandTransactionRequest(envelope: envelope, operation: operation, semantics: semantics, payloadHash: try envelope.payload.sha256(), naturalKey: naturalKey), now: now)
    }
}
