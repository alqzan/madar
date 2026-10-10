import Foundation
import SwiftData
import Darwin
import MadarCore
import MadarData

private struct SettingsInverse: Codable {
    var settings: [String: MadarData.JSONValue]
    var afterSettings: [String: MadarData.JSONValue]
    var layouts: [String: Data?]
    var afterLayouts: [String: Data]
    var prayerBefore: DataRecord? = nil
    var prayerAfter: DataRecord? = nil
}
private struct ReceiptWire: Codable {
    var commandID: UUID
    var name: String
    var payloadHash: String
    var source: CommandSource
    var issuedAt: Date
    var appliedAt: Date
    var expiresAt: Date
    var undoExpiresAt: Date
    var undoJSON: Data?
    var outcome: CommandOutcome
}

/// App-only adapter. The lease excludes app maintenance; each transaction uses a fresh context.
/// No actor suspension occurs between lock, dedupe, mutations and durable receipt save.
@MainActor public final class DurableCommandAdapter: CommandStoreAdapter {
    private let containerProvider: @MainActor () throws -> ModelContainer
    let lockDirectory: URL
    private let transactionClock: @Sendable (Date) -> Date
    /// Production refreshes time after waiting for the lock and before writing the receipt.
    /// Tests using a virtual timeline may inject `{ $0 }`.
    public init(container: ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }) {
        self.containerProvider = { container }; self.lockDirectory = lockDirectory; self.transactionClock = transactionClock
    }
    /// Resolve the active generation only after acquiring the shared transaction lease.
    /// Long maintenance fails immediately; ordinary command contention waits cooperatively.
    public init(containerProvider: @escaping @MainActor () throws -> ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }) {
        self.containerProvider = containerProvider; self.lockDirectory = lockDirectory; self.transactionClock = transactionClock
    }
    public func transact(_ request: CommandTransactionRequest, now arrivalDate: Date) async throws -> CommandOutcome {
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appending(path: "CommandBus.lock")
        let lease = StoreLease(lockURL: lockURL)
        let waitingUntil = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            try Task.checkCancellation()
            try StoreLease.checkMaintenance(lockURL: lockURL)
            do { try lease.acquire(); break }
            catch BackupOperationError.busy {
                guard ContinuousClock.now < waitingUntil else { throw BackupOperationError.busy }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { lease.release() }
        let container = try containerProvider()
        let now = transactionClock(arrivalDate)
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            let store = SettingsStore(context: context, schema: try SettingsSchema.bundled())
            let receiptRows = try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            let receipts = try receiptRows.compactMap { row -> CoreCommandReceipt? in
                guard let id = row.commandID else { return nil }
                let wire = ReceiptWire(commandID: id, name: row.name, payloadHash: row.payloadHash,
                                       source: CommandSource(rawValue: row.source) ?? .app,
                                       issuedAt: row.issuedAt, appliedAt: row.createdAt, expiresAt: row.expiresAt,
                                       undoExpiresAt: row.undoExpiresAt ?? row.createdAt,
                                       undoJSON: row.undoJSON,
                                       outcome: .init(status: CommandStatus(rawValue: row.status) ?? .rejected,
                                                      undoToken: row.status == "applied" && ["prayer.log", "settings.set", "settings.applyPreset"].contains(row.name) ? id : nil))
                return try JSONDecoder().decode(CoreCommandReceipt.self, from: JSONEncoder().encode(wire))
            }
            // Receipt identity is authoritative even after undo/deletion or retention expiry.
            if let replay = request.replayOutcome(receipts: receipts) { return replay }
            var existingHash: String?
            if case .replaceSettings(let settings) = request.operation {
                var existing: [String: MadarCore.JSONValue] = [:]
                for key in settings.keys {
                    existing[key] = try JSONDecoder().decode(MadarCore.JSONValue.self, from: store.value(for: key).canonicalData())
                }
                existingHash = try MadarCore.JSONValue.object(["settings": .object(existing)]).sha256()
            } else if case .logPrayer(let dayKey, let prayer, let status, let heart, let shortened) = request.operation {
                let matches = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == dayKey && $0.prayer == prayer.rawValue && $0.mergedInto == nil }
                if matches.contains(where: { $0.deletedAt != nil }) { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                if let row = matches.max(by: { $0.updatedAt < $1.updatedAt }), row.status == status,
                   (heart == nil || row.heart == heart), (shortened == nil || row.shortened == shortened) {
                    existingHash = request.payloadHash
                }
            }
            switch request.decision(receipts: receipts, existingNaturalPayloadHash: existingHash, now: now) {
            case .replay(let outcome): return outcome
            case .duplicate:
                let outcome = CommandOutcome(status: .duplicate)
                let writer = try store.writerIDForWrite(now: now)
                try saveReceipt(request, outcome: outcome, inverseJSON: nil, writer: writer, at: now, context: context)
                return outcome
            case .apply: break
            }
            let writer = try store.writerIDForWrite(now: now)
            var inverse: SettingsInverse?
            switch request.operation {
            case .logPrayer(let dayKey, let prayer, let status, let heart, let shortened):
                let existing = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == dayKey && $0.prayer == prayer.rawValue && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }
                guard existing?.deletedAt == nil else { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                let before = try existing?.record()
                let placeValue = try store.value(for: "core.homeCity")
                guard case .object(let placeFields) = placeValue,
                      case .number(let lat) = placeFields["lat"], case .number(let lon) = placeFields["lon"],
                      case .string(let tzID) = placeFields["tz"], let date = try? GregorianDay(dayKey),
                      let place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: tzID),
                      let times = PrayerTimesEngine.calculate(day: date, place: place) else { return .init(status: .rejected, reason: "placeUnavailable") }
                let row = existing ?? PrayerLog()
                row.id = existing?.id ?? StableIdentity.uuid(for: "PrayerLog:\(dayKey):\(prayer.rawValue)")
                row.dayKey = dayKey; row.prayer = prayer.rawValue; row.status = status
                if let heart { row.heart = heart }; if let shortened { row.shortened = shortened }
                row.eventAt = times.time(for: prayer); row.tzID = tzID; row.dayPolicy = "prayerDay@1"
                row.loggedAt = now; row.source = request.envelope.source.rawValue
                row.writerID = writer
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
                if existing == nil { context.insert(row) }
                inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerBefore: before, prayerAfter: try row.record())
            case .replaceSettings(let values):
                let typed = try convert(values)
                inverse = SettingsInverse(settings: try store.stage(typed, now: now), afterSettings: typed, layouts: [:], afterLayouts: [:])
            case .applyPreset(let values, let layouts):
                let typed = try convert(values)
                // Validate all layouts before touching any setting.
                var dataLayouts: [String: Data] = [:]
                for (room, value) in layouts {
                    let data = try value.canonicalData()
                    let typed = try JSONDecoder().decode(MadarData.JSONValue.self, from: data)
                    try store.schema.validate(typed, for: room + ".layout")
                    dataLayouts[room] = data
                }
                let allowedRooms: Set<String> = ["bahw", "salah", "quran", "notes", "mal", "mihbara"]
                guard Set(dataLayouts.keys).isSubset(of: allowedRooms) else { return .init(status: .rejected, reason: "invalidRoom") }
                inverse = SettingsInverse(settings: try store.stage(typed, presetOnly: true, now: now), afterSettings: typed, layouts: [:], afterLayouts: dataLayouts)
                for (room, data) in dataLayouts {
                    let rows = try context.fetch(FetchDescriptor<LayoutState>()).filter { $0.room == room && $0.deletedAt == nil && $0.mergedInto == nil }
                    let row = rows.max { $0.updatedAt < $1.updatedAt }
                    inverse?.layouts[room] = .some(row?.blocksJSON)
                    let target = row ?? LayoutState()
                    target.room = room; target.blocksJSON = data
                    target.writerID = writer
                    target.updatedAt = StableIdentity.monotonic(now: now, previous: target.updatedAt)
                    if row == nil { context.insert(target) }
                }
                // Applying another preset invalidates its prior undo, not its dedupe receipt.
                for row in receiptRows where row.name == "settings.applyPreset" { row.undoJSON = nil; row.undoExpiresAt = now }
            case .undo(let token):
                guard let previous = receipts.first(where: { $0.commandID == token }), previous.canUndo(at: now),
                      let row = receiptRows.first(where: { $0.commandID == token }), let data = row.undoJSON else {
                    return .init(status: .rejected, reason: "undoExpired")
                }
                let state = try JSONDecoder().decode(SettingsInverse.self, from: data)
                if let after = state.prayerAfter {
                    guard let current = try context.fetch(FetchDescriptor<PrayerLog>()).first(where: { $0.id == after.id && $0.mergedInto == nil }), try current.record() == after else { throw DataError.invalidValue("undo superseded: prayer") }
                    if let before = state.prayerBefore {
                        try current.apply(before); current.updatedAt = StableIdentity.monotonic(now: now, previous: current.updatedAt)
                    } else {
                        current.deletedAt = now; current.deletionBarrierAt = now
                        current.updatedAt = StableIdentity.monotonic(now: now, previous: current.updatedAt)
                    }
                    current.writerID = writer
                }
                for (key, after) in state.afterSettings where try store.value(for: key) != after {
                    throw DataError.invalidValue("undo superseded: \(key)")
                }
                for (room, after) in state.afterLayouts {
                    let current = try store.value(for: room + ".layout").canonicalData()
                    guard current == after else { throw DataError.invalidValue("undo superseded: \(room).layout") }
                }
                _ = try store.stage(state.settings, now: now)
                for (room, old) in state.layouts {
                    let rows = try context.fetch(FetchDescriptor<LayoutState>()).filter { $0.room == room && $0.deletedAt == nil && $0.mergedInto == nil }
                    if let old {
                        let row = rows.first ?? LayoutState(); row.room = room; row.blocksJSON = old
                        row.writerID = writer
                        row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
                        if rows.isEmpty { context.insert(row) }
                    } else {
                        for row in rows { row.deletedAt = now; row.deletionBarrierAt = now; row.writerID = writer; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt) }
                    }
                }
                row.undoJSON = nil; row.undoExpiresAt = now; row.writerID = writer
            case .savePreset(let name, let settings, let layouts):
                let typed = try convert(settings)
                for (key, value) in typed {
                    guard try store.schema.definition(for: key).preset else { throw DataError.invalidValue("non-preset \(key)") }
                    try store.schema.validate(value, for: key)
                }
                for (room, value) in try convert(layouts) { try store.schema.validate(value, for: room + ".layout") }
                let preset = Preset(); preset.name = name
                preset.writerID = writer
                preset.createdAt = now; preset.updatedAt = now
                preset.payloadJSON = try MadarCore.JSONValue.object(["v": .number(1), "settings": .object(settings), "layouts": .object(layouts)]).canonicalData()
                context.insert(preset)
            case .completeOnboarding:
                let existing = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.onboardingCompleted" && $0.mergedInto == nil }
                let row = existing ?? DeviceSetting(); row.key = "sys.onboardingCompleted"
                row.writerID = writer
                row.valueJSON = Data("true".utf8); row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
                if existing == nil { context.insert(row) }
            }
            let outcome = CommandOutcome(status: .applied, undoToken: inverse == nil ? nil : request.envelope.commandID)
            try saveReceipt(request, outcome: outcome, inverseJSON: try inverse.map { try JSONEncoder().encode($0) }, writer: writer, at: transactionClock(arrivalDate), context: context)
            return outcome
        } catch {
            context.rollback()
            throw error
        }
    }
    private func saveReceipt(_ request: CommandTransactionRequest, outcome: CommandOutcome, inverseJSON: Data?, writer: String, at appliedAt: Date, context: ModelContext) throws {
        let receipt = MadarData.CommandReceipt()
        receipt.writerID = writer
        receipt.commandID = request.envelope.commandID; receipt.name = request.envelope.name
        receipt.payloadHash = request.payloadHash; receipt.source = request.envelope.source.rawValue
        receipt.issuedAt = request.envelope.issuedAt; receipt.createdAt = appliedAt; receipt.updatedAt = appliedAt
        receipt.status = outcome.status.rawValue
        receipt.expiresAt = appliedAt.addingTimeInterval(7 * 86400)
        receipt.undoExpiresAt = appliedAt.addingTimeInterval(request.semantics == .preset ? 60 : 600)
        receipt.undoJSON = inverseJSON
        context.insert(receipt)
        try context.save()
    }
    public func hasReceipt(commandID: UUID) throws -> Bool {
        let lease = StoreLease(lockURL: lockDirectory.appending(path: "CommandBus.lock"))
        try lease.acquire(); defer { lease.release() }
        return try ModelContext(containerProvider()).fetch(FetchDescriptor<MadarData.CommandReceipt>()).contains { $0.commandID == commandID && $0.deletedAt == nil && $0.mergedInto == nil }
    }
    /// Called only after the inbox acknowledges its durable files. Malformed/unresolved files
    /// conservatively block collection; inverse expiry remains independent of replay identity.
    public func purgeExpiredReceipts(pinnedIDs: Set<UUID>, now: Date = Date()) throws {
        let lease = StoreLease(lockURL: lockDirectory.appending(path: "CommandBus.lock"))
        try lease.acquire(); defer { lease.release() }
        let context = ModelContext(try containerProvider()); context.autosaveEnabled = false
        for row in try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()) {
            guard let id = row.commandID, row.expiresAt <= now, !pinnedIDs.contains(id) else { continue }
            context.delete(row)
        }
        try context.save()
    }
    private func convert(_ values: [String: MadarCore.JSONValue]) throws -> [String: MadarData.JSONValue] {
        try values.mapValues { try JSONDecoder().decode(MadarData.JSONValue.self, from: $0.canonicalData()) }
    }
}
