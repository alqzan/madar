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
    case completeDiaryWelcome
    case diaryEditor(DiaryEditorCommand)
    case habit(HabitCommand)
    case money(name: String, payload: [String: JSONValue])
    case book(BookCommand)
    case quran(name: String, payload: [String: JSONValue])
    case diary(text: String, day: String, targetDay: String?)
    case freezeDiaryDay(String)
    case logPrayer(dayKey: String, prayer: Prayer, status: String, heart: String?, shortened: Bool?, fridayKind: String?)
    case makeUpPrayer(dayKey: String, prayer: Prayer, at: Date, fridayKind: String?)
    case resolvePrayerGap([PrayerGapResolution])
    case answerPrayerHeart(PrayerReference, PrayerHeart?)
    case addOldMissedPrayer(PrayerReference, fridayKind: FridayPrayerKind?, restoreDeleted: Bool)
    case recordQiyamNight(night: GregorianDay, rakaat: Int, witr: Bool, restoreDeleted: Bool)
    case editPrayerTrackingStart(GregorianDay)
    case startPrayerTrip(city: String, country: String, place: ActivePlace, homeKm: Double?)
    case continuePrayerTrip(city: String, country: String, place: ActivePlace, homeKm: Double?)
    case endPrayerTrip(UUID)
    case logPrayerPair(day: GregorianDay, pair: PrayerPair, status: PrayerStoredStatus, shortened: Bool, mode: PrayerPairMode)
    case stagePrayerMutation(PrayerMutation)
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
    /// App transaction namespace, never part of the producer's command identity.
    public let generationID: UUID?
    public init(envelope: CommandEnvelope, operation: CommandOperation, semantics: CommandSemantics, payloadHash: String, naturalKey: String?, generationID: UUID? = nil) {
        self.envelope = envelope; self.operation = operation; self.semantics = semantics
        self.payloadHash = payloadHash; self.naturalKey = naturalKey; self.generationID = generationID
    }
    /// Expiry permits later garbage collection; it does not erase an on-disk replay identity.
    /// The inbox coordinator pins receipts until every delivery has been acknowledged.
    public func replayOutcome(receipts: [CoreCommandReceipt]) -> CommandOutcome? {
        guard let receipt = receipts.first(where: { $0.commandID == envelope.commandID }) else { return nil }
        guard receipt.name == envelope.name, receipt.payloadHash == payloadHash else {
            return .init(status: .rejected, reason: "commandIdentityMismatch")
        }
        return receipt.outcome
    }
    public func decision(receipts: [CoreCommandReceipt], existingNaturalPayloadHash: String?, now: Date) -> CommandDecision {
        if let outcome = replayOutcome(receipts: receipts) { return .replay(outcome) }
        let live = receipts.filter { $0.expiresAt > now }
        if semantics == .upsert, naturalKey != nil, existingNaturalPayloadHash == payloadHash { return .duplicate }
        if semantics == .append, live.contains(where: { $0.name == envelope.name && $0.payloadHash == payloadHash && now >= $0.appliedAt && now.timeIntervalSince($0.appliedAt) <= 10 }) { return .duplicate }
        return .apply
    }
}
/// Adapter MUST decide, mutate, store inverse + receipt, and commit in ONE serialized store
/// transaction in the app process. Extensions enqueue value envelopes only. In-memory bus state is never authoritative.
public protocol CommandStoreAdapter: Sendable {
    func transact(_ request: CommandTransactionRequest, now: Date) async throws -> CommandOutcome
}
public struct CommandBus: Sendable {
    // Names implemented by this milestone. Unknown and later-room names are invalid
    // before authorization, so they cannot become indefinitely recoverable needsApp work.
    public static let appOnlyCommandNames: Set<String> = Set(["settings.set", "settings.applyPreset", "preset.save", "core.completeOnboarding", "system.undo", "prayer.setHeart", "prayer.logQiyam", "prayer.editTrackingStart", "prayer.startTrip", "prayer.continueTrip", "prayer.endTrip", "prayer.logPair"]).union(MoneyCommandPayload.names.subtracting(transportBlindWriteNames)).union(HabitCommand.names.subtracting(transportBlindWriteNames)).union(BookCommand.names).union(QuranCommandPayload.names).union(DiaryEditorCommand.names).union(["diary.appendLine", "diary.addMargin", "diary.freezeDay", "diary.completeWelcome"])
    /// §16 blindWrite commands that Shortcuts, widgets and Controls may queue through the inbox.
    /// They reveal nothing and carry an explicit day or period, so a late drain cannot misdate them.
    public static let transportBlindWriteNames: Set<String> = ["prayer.log", "habit.complete", "money.ingestBankMessage", "money.logExpense"]
    public static let supportedCommandNames = appOnlyCommandNames.union(transportBlindWriteNames).union(["diary.appendLine", "diary.addMargin"])
    private let adapter: any CommandStoreAdapter
    public init(adapter: any CommandStoreAdapter) { self.adapter = adapter }
    public func execute(_ envelope: CommandEnvelope, now: Date = Date(), generationID: UUID? = nil) async throws -> CommandOutcome {
        guard envelope.schemaVersion == 1, envelope.issuedAt <= now.addingTimeInterval(300), case .object(let payload) = envelope.payload else { return .init(status: .rejected, reason: "invalidCommand") }
        guard Self.supportedCommandNames.contains(envelope.name) else { return .init(status: .rejected, reason: "unavailableInM0") }
        if Self.appOnlyCommandNames.contains(envelope.name), envelope.source != .app {
            return .init(status: .needsApp, reason: "appOnlyFoundationCommand")
        }
        let operation: CommandOperation; let semantics: CommandSemantics; let naturalKey: String?
        switch envelope.name {
        case let name where BookCommand.names.contains(name):
            guard let parsed = BookCommand.parse(name, payload) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .book(parsed); semantics = .upsert; naturalKey = nil
        case let name where MoneyCommandPayload.names.contains(name):
            guard MoneyCommandPayload.validate(name: name, payload: payload) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .money(name: name, payload: payload); semantics = .upsert; naturalKey = nil
        case let name where HabitCommand.names.contains(name):
            guard let parsed = HabitCommand.parse(name, payload) else { return .init(status: .rejected, reason: "invalidPayload") }
            // A queued completion freezes its day or names a period; legacy period-only requests reject a closed period.
            if envelope.source != .app, case .complete(_, _, nil, nil, _) = parsed { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .habit(parsed); semantics = .upsert; naturalKey = nil
        case let name where DiaryEditorCommand.names.contains(name):
            guard let parsed = DiaryEditorCommand.parse(name, payload) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .diaryEditor(parsed); semantics = name == "diary.appendMedia" ? .append : .upsert; naturalKey = nil
        case "diary.completeWelcome":
            guard payload.isEmpty else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .completeDiaryWelcome; semantics = .upsert; naturalKey = "sys.diaryWelcomeSeen"
        case "diary.freezeDay":
            guard Set(payload.keys) == ["dayKey"], case .string(let day) = payload["dayKey"], (try? GregorianDay(day)) != nil else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .freezeDiaryDay(day); semantics = .upsert; naturalKey = day
        case "diary.appendLine", "diary.addMargin":
            guard Set(payload.keys).isSubset(of: envelope.name == "diary.appendLine" ? ["text", "day"] : ["text", "targetDayKey"]),
                  case .string(let text) = payload["text"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 2000 else { return .init(status: .rejected, reason: "invalidPayload") }
            if envelope.name == "diary.appendLine" {
                guard case .string(let day) = payload["day"], ["today", "yesterday"].contains(day) else { return .init(status: .rejected, reason: "invalidPayload") }
                operation = .diary(text: text, day: day, targetDay: nil)
            } else {
                guard envelope.source == .app, case .string(let target) = payload["targetDayKey"], (try? GregorianDay(target)) != nil else { return .init(status: .rejected, reason: "invalidPayload") }
                operation = .diary(text: text, day: "today", targetDay: target)
            }
            semantics = .append; naturalKey = nil
        case let name where QuranCommandPayload.names.contains(name):
            guard QuranCommandPayload.validate(name: name, payload: payload) else { return .init(status: .rejected, reason: "invalidPayload") }
            operation = .quran(name: name, payload: payload)
            semantics = name == "quran.savePlan" ? .append : .upsert
            naturalKey = name
        case "prayer.log":
            guard Set(payload.keys).isSubset(of: ["dayKey", "prayer", "status", "heart", "shortened", "fridayKind"]),
                  case .string(let dayKey) = payload["dayKey"], (try? GregorianDay(dayKey)) != nil,
                  case .string(let prayerRaw) = payload["prayer"], let prayer = Prayer(rawValue: prayerRaw),
                  case .string(let status) = payload["status"], ["jamaah", "alone", "qada"].contains(status) else { return .init(status: .rejected, reason: "invalidPayload") }
            var heart: String?, shortened: Bool?
            if let value = payload["heart"], value != .null {
                guard case .string(let h) = value, ["distracted", "present", "khashi"].contains(h) else { return .init(status: .rejected, reason: "invalidPayload") }
                heart = h
            }
            if let value = payload["shortened"] {
                guard case .bool(let b) = value else { return .init(status: .rejected, reason: "invalidPayload") }
                shortened = b
            }
            var fridayKind: String?
            if let value = payload["fridayKind"], value != .null {
                guard case .string(let raw) = value, FridayPrayerKind(rawValue: raw) != nil else { return .init(status: .rejected, reason: "invalidPayload") }
                fridayKind = raw
            }
            if shortened == true && (prayer == .fajr || prayer == .maghrib) { return .init(status: .rejected, reason: "invalidShortening") }
            operation = .logPrayer(dayKey: dayKey, prayer: prayer, status: status, heart: heart, shortened: shortened, fridayKind: fridayKind)
            semantics = .upsert; naturalKey = "prayer." + dayKey + "." + prayer.rawValue
        case "prayer.editTrackingStart":
            do {
                let (mutation, key) = try PrayerMutation.parse(name: envelope.name, payload: payload)
                guard case .editTrackingStart(let day) = mutation else { return .init(status: .rejected, reason: "invalidPayload") }
                operation = .editPrayerTrackingStart(day); semantics = .upsert; naturalKey = key
            } catch { return .init(status: .rejected, reason: "invalidPayload") }
        case "prayer.startTrip", "prayer.continueTrip", "prayer.endTrip", "prayer.logPair":
            do {
                let (mutation, key) = try PrayerMutation.parse(name: envelope.name, payload: payload)
                switch mutation {
                case .startTrip(let city, let country, let place, let homeKm): operation = .startPrayerTrip(city: city, country: country, place: place, homeKm: homeKm); semantics = .append
                case .continueTrip(let city, let country, let place, let homeKm): operation = .continuePrayerTrip(city: city, country: country, place: place, homeKm: homeKm); semantics = .append
                case .endTrip(let id): operation = .endPrayerTrip(id); semantics = .upsert
                case .logPair(let day, let pair, let status, let shortened, let mode): operation = .logPrayerPair(day: day, pair: pair, status: status, shortened: shortened, mode: mode); semantics = .upsert
                default: return .init(status: .rejected, reason: "invalidPayload")
                }
                naturalKey = key
            } catch { return .init(status: .rejected, reason: "invalidPayload") }
        case "prayer.logQiyam":
            do {
                let (mutation, key) = try PrayerMutation.parse(name: envelope.name, payload: payload)
                switch mutation {
                case .logQiyam(let night, let rakaat, let witr): operation = .recordQiyamNight(night: night, rakaat: rakaat, witr: witr, restoreDeleted: false)
                case .restoreQiyam(let night, let rakaat, let witr): operation = .recordQiyamNight(night: night, rakaat: rakaat, witr: witr, restoreDeleted: true)
                default: return .init(status: .rejected, reason: "invalidPayload")
                }
                semantics = .upsert; naturalKey = key
            } catch { return .init(status: .rejected, reason: "invalidPayload") }
        case "prayer.setHeart":
            do {
                let (mutation, key) = try PrayerMutation.parse(name: "prayer.answerHeart", payload: payload)
                guard case .answerHeart(let reference, let heart) = mutation else { return .init(status: .rejected, reason: "invalidPayload") }
                operation = .answerPrayerHeart(reference, heart)
                semantics = .upsert; naturalKey = key
            } catch { return .init(status: .rejected, reason: "invalidPayload") }
        case "prayer.resolveGap":
            return .init(status: .rejected, reason: "unavailableInM0")
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
        return try await adapter.transact(CommandTransactionRequest(envelope: envelope, operation: operation, semantics: semantics, payloadHash: try envelope.payload.sha256(), naturalKey: naturalKey, generationID: generationID), now: now)
    }
}
