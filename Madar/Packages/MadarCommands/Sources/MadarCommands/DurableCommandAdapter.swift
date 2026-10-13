import Foundation
import SwiftData
import Darwin
import MadarCore
import MadarData
import MadarPrayer

private struct SettingsInverse: Codable {
    var settings: [String: MadarData.JSONValue]
    var afterSettings: [String: MadarData.JSONValue]
    var layouts: [String: Data?]
    var afterLayouts: [String: Data]
    var prayerBefore: DataRecord? = nil
    var prayerAfter: DataRecord? = nil
    var prayerMutation: Data? = nil
}
private struct ReceiptNamespace: Codable {
    let version: Int
    let generationID: UUID
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
    private let generationProvider: @MainActor () throws -> UUID?
    /// Production refreshes time after waiting for the lock and before writing the receipt.
    /// Tests using a virtual timeline may inject `{ $0 }`.
    public init(container: ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }, generationProvider: @escaping @MainActor () throws -> UUID? = { nil }) {
        self.containerProvider = { container }; self.lockDirectory = lockDirectory; self.transactionClock = transactionClock; self.generationProvider = generationProvider
    }
    /// Resolve the active generation only after acquiring the shared transaction lease.
    /// Long maintenance fails immediately; ordinary command contention waits cooperatively.
    public init(containerProvider: @escaping @MainActor () throws -> ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }, generationProvider: @escaping @MainActor () throws -> UUID? = { nil }) {
        self.containerProvider = containerProvider; self.lockDirectory = lockDirectory; self.transactionClock = transactionClock; self.generationProvider = generationProvider
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
            let activeGeneration = try generationProvider()
            if let expected = request.generationID, let activeGeneration, expected != activeGeneration {
                return .init(status: .needsApp, reason: "receiptGenerationMismatch")
            }
            // Fixed-container callers have no replacement pointer. Their local namespace is
            // stable across reopen; managed production callers always supply the real pointer.
            let generationID = activeGeneration ?? request.generationID ?? StableIdentity.uuid(for: "CommandGeneration:\(lockDirectory.standardizedFileURL.resolvingSymlinksInPath().path)")
            let namespaces = try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key.hasPrefix("sys.commandReceiptScope:") && $0.deletedAt == nil && $0.mergedInto == nil }
            func namespace(_ row: MadarData.CommandReceipt) -> ReceiptNamespace? {
                let matches = namespaces.filter { $0.key == "sys.commandReceiptScope:\(row.id.uuidString)" }
                guard matches.count == 1, let value = try? JSONDecoder().decode(ReceiptNamespace.self, from: matches[0].valueJSON), value.version == 1 else { return nil }
                return value
            }
            let allReceiptRows = try context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            // Existing identities from another or unknown generation are unresolved, even
            // when the newly delivered envelope bears today's snapshot stamp.
            for row in allReceiptRows where row.commandID == request.envelope.commandID {
                guard let scope = namespace(row) else { return .init(status: .needsApp, reason: "receiptGenerationUnknown") }
                guard scope.generationID == generationID else { return .init(status: .needsApp, reason: "receiptGenerationMismatch") }
            }
            let receiptRows = allReceiptRows.filter { namespace($0)?.generationID == generationID }
            let receipts = try receiptRows.compactMap { row -> CoreCommandReceipt? in
                guard let id = row.commandID else { return nil }
                let wire = ReceiptWire(commandID: id, name: row.name, payloadHash: row.payloadHash,
                                       source: CommandSource(rawValue: row.source) ?? .app,
                                       issuedAt: row.issuedAt, appliedAt: row.createdAt, expiresAt: row.expiresAt,
                                       undoExpiresAt: row.undoExpiresAt ?? row.createdAt,
                                       undoJSON: row.undoJSON,
                                       outcome: .init(status: CommandStatus(rawValue: row.status) ?? .rejected,
                                                      undoToken: row.status == "applied" && ["prayer.log", "prayer.makeUp", "prayer.resolveGap", "prayer.setHeart", "prayer.logQiyam", "settings.set", "settings.applyPreset"].contains(row.name) ? id : nil))
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
            } else if case .logPrayer(let dayKey, let prayer, let status, let heart, let shortened, let fridayKind) = request.operation {
                let matches = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == dayKey && $0.prayer == prayer.rawValue && $0.mergedInto == nil }
                if matches.contains(where: { $0.deletedAt != nil }) { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                if let row = matches.max(by: { $0.updatedAt < $1.updatedAt }), row.status == status,
                   (heart == nil || row.heart == heart), (shortened == nil || row.shortened == shortened),
                   (fridayKind == nil || row.fridayKind == fridayKind) {
                    existingHash = request.payloadHash
                }
            } else if case .recordQiyamNight(let night, let rakaat, let witr, let restoring) = request.operation {
                let rows = try context.fetch(FetchDescriptor<QiyamNight>()).filter { $0.nightKey == night.description && $0.mergedInto == nil }
                if let row = rows.max(by: { $0.updatedAt < $1.updatedAt }) {
                    if row.deletedAt != nil && !restoring { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                    if row.deletedAt == nil && row.rakaat == rakaat && row.witr == witr { existingHash = request.payloadHash }
                }
            } else if case .answerPrayerHeart(let reference, let heart) = request.operation {
                let rows = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == reference.day.description && $0.prayer == reference.prayer.rawValue && $0.mergedInto == nil }
                if rows.contains(where: { $0.deletedAt != nil }) { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                if let row = rows.max(by: { $0.updatedAt < $1.updatedAt }), ["jamaah", "alone", "qada"].contains(row.status), row.heart == heart?.rawValue {
                    existingHash = request.payloadHash
                }
            } else if case .makeUpPrayer(let dayKey, let prayer, _, let fridayKind) = request.operation {
                let logs = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.dayKey == dayKey && $0.prayer == prayer.rawValue && $0.mergedInto == nil }
                if logs.contains(where: { $0.deletedAt != nil }) { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                let debts = try context.fetch(FetchDescriptor<QadaItem>()).filter { $0.originalDayKey == dayKey && $0.prayer == prayer.rawValue && $0.mergedInto == nil }
                if let log = logs.filter({ $0.deletedAt == nil }).max(by: { $0.updatedAt < $1.updatedAt }),
                   let debt = debts.filter({ $0.deletedAt == nil }).max(by: { $0.updatedAt < $1.updatedAt }),
                   log.status == "qada", debt.madeUpAt != nil,
                   (fridayKind == nil || log.fridayKind == fridayKind) {
                    existingHash = request.payloadHash
                }
            } else if case .resolvePrayerGap(let resolutions) = request.operation {
                let logs = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.mergedInto == nil }
                let debts = try context.fetch(FetchDescriptor<QadaItem>()).filter { $0.mergedInto == nil }
                if resolutions.contains(where: { resolution in
                    logs.contains(where: { $0.dayKey == resolution.reference.day.description && $0.prayer == resolution.reference.prayer.rawValue && $0.deletedAt != nil })
                }) { return .init(status: .rejected, reason: "explicitRestoreRequired") }
                let alreadyResolved = resolutions.allSatisfy { resolution in
                    let dayKey = resolution.reference.day.description, prayer = resolution.reference.prayer.rawValue
                    let log = logs.filter { $0.dayKey == dayKey && $0.prayer == prayer && $0.deletedAt == nil }.max { $0.updatedAt < $1.updatedAt }
                    let debt = debts.filter { $0.originalDayKey == dayKey && $0.prayer == prayer && $0.deletedAt == nil }.max { $0.updatedAt < $1.updatedAt }
                    let debtMatches = resolution.status == .missed ? debt?.madeUpAt == nil : debt == nil
                    let fridayMatches = [.unrecordedHistory, .excused].contains(resolution.status) || log?.fridayKind == resolution.fridayKind?.rawValue
                    return log?.status == resolution.status.rawValue && log?.heart == nil && log?.shortened != true && debtMatches && fridayMatches
                }
                if alreadyResolved { existingHash = request.payloadHash }
            }
            switch request.decision(receipts: receipts, existingNaturalPayloadHash: existingHash, now: now) {
            case .replay(let outcome): return outcome
            case .duplicate:
                let outcome = CommandOutcome(status: .duplicate)
                let writer = try store.writerIDForWrite(now: now)
                try saveReceipt(request, outcome: outcome, inverseJSON: nil, writer: writer, generationID: generationID, at: now, context: context)
                return outcome
            case .apply: break
            }
            let writer = try store.writerIDForWrite(now: now)
            var inverse: SettingsInverse?
            switch request.operation {
            case .logPrayer(let dayKey, let prayer, let status, let heart, let shortened, let fridayKind):
                guard let referenceDay = try? GregorianDay(dayKey), let storedStatus = PrayerStoredStatus(rawValue: status) else {
                    return .init(status: .rejected, reason: "invalidPrayer")
                }
                let mutation = PrayerMutation.record(.init(day: referenceDay, prayer: prayer), status: storedStatus,
                    heart: heart.flatMap(PrayerHeart.init(rawValue:)), shortened: shortened,
                    fridayKind: fridayKind.flatMap(FridayPrayerKind.init(rawValue:)))
                do {
                    if let undo = try PrayerMutationHandler.stage(operation: mutation, in: context, now: now, writer: writer, source: request.envelope.source) {
                        inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerMutation: undo)
                    }
                } catch let error as PrayerDomainError {
                    return .init(status: .rejected, reason: String(describing: error))
                }
            case .recordQiyamNight(let night, let rakaat, let witr, let restoring):
                let mutation: PrayerMutation = restoring ? .restoreQiyam(night: night, rakaat: rakaat, witr: witr) : .logQiyam(night: night, rakaat: rakaat, witr: witr)
                do {
                    if let undo = try PrayerMutationHandler.stage(operation: mutation, in: context, now: now, writer: writer, source: request.envelope.source) {
                        inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerMutation: undo)
                    }
                } catch let error as PrayerDomainError {
                    return .init(status: .rejected, reason: String(describing: error))
                }
            case .answerPrayerHeart(let reference, let heart):
                do {
                    if let undo = try PrayerMutationHandler.stage(operation: .answerHeart(reference, heart), in: context, now: now, writer: writer, source: request.envelope.source) {
                        inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerMutation: undo)
                    }
                } catch let error as PrayerDomainError {
                    return .init(status: .rejected, reason: String(describing: error))
                }
            case .makeUpPrayer(let dayKey, let prayer, let at, let fridayKind):
                guard let referenceDay = try? GregorianDay(dayKey) else { return .init(status: .rejected, reason: "invalidPrayer") }
                do {
                    let mutation = PrayerMutation.makeUp(.init(day: referenceDay, prayer: prayer), at: at, fridayKind: fridayKind.flatMap(FridayPrayerKind.init(rawValue:)))
                    if let undo = try PrayerMutationHandler.stage(operation: mutation, in: context, now: now, writer: writer, source: request.envelope.source) {
                        inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerMutation: undo)
                    }
                } catch let error as PrayerDomainError {
                    return .init(status: .rejected, reason: String(describing: error))
                }
            case .resolvePrayerGap(let resolutions):
                do {
                    if let undo = try PrayerMutationHandler.stage(operation: .resolveGap(resolutions), in: context, now: now, writer: writer, source: request.envelope.source) {
                        inverse = SettingsInverse(settings: [:], afterSettings: [:], layouts: [:], afterLayouts: [:], prayerMutation: undo)
                    }
                } catch let error as PrayerDomainError {
                    return .init(status: .rejected, reason: String(describing: error))
                }
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
                if let mutation = state.prayerMutation {
                    try PrayerMutationHandler.undo(mutation, in: context, now: now, writer: writer)
                } else if let after = state.prayerAfter {
                    guard let current = try context.fetch(FetchDescriptor<PrayerLog>()).first(where: { $0.id == after.id && $0.mergedInto == nil }), normalizedPrayerRecord(try current.record()) == normalizedPrayerRecord(after) else { throw DataError.invalidValue("undo superseded: prayer") }
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
            try saveReceipt(request, outcome: outcome, inverseJSON: try inverse.map { try JSONEncoder().encode($0) }, writer: writer, generationID: generationID, at: transactionClock(arrivalDate), context: context)
            return outcome
        } catch {
            context.rollback()
            throw error
        }
    }
    private func saveReceipt(_ request: CommandTransactionRequest, outcome: CommandOutcome, inverseJSON: Data?, writer: String, generationID: UUID, at appliedAt: Date, context: ModelContext) throws {
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
        // Namespace and effect commit together. A filesystem completion marker is later
        // refresh provenance and must never be the source of receipt generation identity.
        let scope = DeviceSetting()
        scope.key = "sys.commandReceiptScope:\(receipt.id.uuidString)"
        scope.id = StableIdentity.uuid(for: "DeviceSetting:\(scope.key)")
        scope.valueJSON = try JSONEncoder().encode(ReceiptNamespace(version: 1, generationID: generationID))
        scope.writerID = writer; scope.createdAt = appliedAt; scope.updatedAt = appliedAt
        context.insert(scope)
        try context.save()
    }
    private func normalizedPrayerRecord(_ record: DataRecord) -> DataRecord {
        guard record.model == "PrayerLog" else { return record }
        var normalized = record
        if normalized.fields["fridayKind"] == nil { normalized.fields["fridayKind"] = .null }
        return normalized
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
            for scope in try context.fetch(FetchDescriptor<DeviceSetting>()) where scope.key == "sys.commandReceiptScope:\(row.id.uuidString)" { context.delete(scope) }
            context.delete(row)
        }
        try context.save()
    }
    private func convert(_ values: [String: MadarCore.JSONValue]) throws -> [String: MadarData.JSONValue] {
        try values.mapValues { try JSONDecoder().decode(MadarData.JSONValue.self, from: $0.canonicalData()) }
    }
}
