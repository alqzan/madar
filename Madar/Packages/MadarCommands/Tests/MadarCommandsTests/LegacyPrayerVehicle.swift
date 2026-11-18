import Foundation
import SwiftData
@testable import MadarCommands

/// Prayer logging is closed in production (owner, 17 Nov 2026). The replay, inbox, undo and diary-freeze mechanics below were
/// proven with the prayer handler as their vehicle; these factories reopen it for those tests only. Production paths use the plain init.
@MainActor func legacyPrayerAdapter(container: ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }, generationProvider: @escaping @MainActor () throws -> UUID? = { nil }) -> DurableCommandAdapter {
    let a = DurableCommandAdapter(container: container, lockDirectory: lockDirectory, transactionClock: transactionClock, generationProvider: generationProvider)
    a.prayerLoggingRetired = false
    return a
}
@MainActor func legacyPrayerAdapter(containerProvider: @escaping @MainActor () throws -> ModelContainer, lockDirectory: URL, transactionClock: @escaping @Sendable (Date) -> Date = { _ in Date() }, generationProvider: @escaping @MainActor () throws -> UUID? = { nil }) -> DurableCommandAdapter {
    let a = DurableCommandAdapter(containerProvider: containerProvider, lockDirectory: lockDirectory, transactionClock: transactionClock, generationProvider: generationProvider)
    a.prayerLoggingRetired = false
    return a
}
