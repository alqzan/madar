import Foundation
import MadarCore
import MadarInbox

/// One coordinator per app session. Extensions never link this writable command package.
@MainActor public final class InboxDrainer {
    public private(set) var isDraining = false
    private let inbox: PendingInbox
    private let bus: CommandBus
    private let generation: @MainActor () throws -> InboxGeneration
    private let hasReceipt: @MainActor (UUID) throws -> Bool
    private let refresh: @MainActor () async throws -> Void
    private let shouldPause: @MainActor () -> Bool
    private let authorization: @MainActor (CommandEnvelope) -> CommandOutcome?
    public init(inbox: PendingInbox, bus: CommandBus, generation: @escaping @MainActor () throws -> InboxGeneration,
                hasReceipt: @escaping @MainActor (UUID) throws -> Bool, refresh: @escaping @MainActor () async throws -> Void,
                shouldPause: @escaping @MainActor () -> Bool = { false },
                authorization: @escaping @MainActor (CommandEnvelope) -> CommandOutcome? = { _ in nil }) {
        self.inbox = inbox; self.bus = bus; self.generation = generation
        self.hasReceipt = hasReceipt; self.refresh = refresh; self.shouldPause = shouldPause; self.authorization = authorization
    }
    public func drain(now: Date = Date()) async throws {
        guard !isDraining, !shouldPause() else { return }
        isDraining = true; defer { isDraining = false }
        try Task.checkCancellation()
        let recovering = Set(try inbox.processingFiles().map(\.path))
        let files = try inbox.claimBatch()
        var records: [(URL, InboxRecord)] = []
        for file in files {
            do { records.append((file, try inbox.read(file))) }
            catch InboxError.malformedRecord { try inbox.quarantine(file, reason: "malformedRecord") }
            catch InboxError.unknownVersion { try inbox.quarantine(file, reason: "unknownVersion") }
        }
        // Preserve processing recovery priority, then deterministic order inside each batch.
        records.sort {
            let leftRecovery = recovering.contains($0.0.path), rightRecovery = recovering.contains($1.0.path)
            if leftRecovery != rightRecovery { return leftRecovery }
            if $0.1.command.issuedAt != $1.1.command.issuedAt { return $0.1.command.issuedAt < $1.1.command.issuedAt }
            if $0.1.command.commandID != $1.1.command.commandID { return $0.1.command.commandID.uuidString < $1.1.command.commandID.uuidString }
            return $0.1.deliveryID.uuidString < $1.1.deliveryID.uuidString
        }
        for (file, record) in records {
            try Task.checkCancellation()
            guard !shouldPause() else { return }
            let active = try generation()
            guard active.permits(record) else {
                try inbox.retainForResolution(file, reason: "generationChanged"); continue
            }
            // The embedded source is a value, never proof of a user-authorized app call.
            // Foundation app-only writes use the direct UI bus; transport cannot disable locks.
            let appOnly = ["settings.set", "settings.applyPreset", "preset.save", "core.completeOnboarding", "system.undo"]
            if appOnly.contains(record.command.name) { continue } // needsApp; retain for explicit app resolution
            if let denial = authorization(record.command) {
                if denial.status == .rejected { try inbox.quarantine(file, reason: "invalidCommand") }
                continue // needsUnlock/needsApp preserve the accepted delivery
            }
            if try inbox.wasCommitted(commandID: record.command.commandID, generationID: active.generationID), !(try hasReceipt(record.command.commandID)) {
                try inbox.retainForResolution(file, reason: "legacyIdentityAmbiguous"); continue
            }
            let outcome = try await bus.execute(record.command, now: now, generationID: active.generationID)
            switch outcome.status {
            case .needsApp, .needsUnlock:
                if outcome.reason == "receiptGenerationMismatch" { try inbox.retainForResolution(file, reason: "generationChanged") }
                else if outcome.reason == "receiptGenerationUnknown" { try inbox.retainForResolution(file, reason: "legacyIdentityAmbiguous") }
                continue // recoverable; no deletion or false success
            case .rejected: try inbox.quarantine(file, reason: "invalidCommand")
            case .applied, .duplicate:
                try Task.checkCancellation()
                try await refresh()
                try Task.checkCancellation()
                // Restore cannot run during an app drain, but guard unexpected rebinding too.
                guard try generation().generationID == active.generationID else {
                    try inbox.retainForResolution(file, reason: "generationChanged"); continue
                }
                try inbox.markCommitted(commandID: record.command.commandID, generationID: active.generationID)
                try inbox.acknowledge(file)
            }
        }
    }
}
