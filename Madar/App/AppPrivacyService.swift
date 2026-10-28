import Foundation
import CoreSpotlight
import UserNotifications
import WidgetKit
import MadarSnapshots
import MadarData
import UniformTypeIdentifiers

struct AppSpotlightBookRecord: Equatable {
    let id: UUID
    let title: String
}

typealias AppSpotlightIndexOperation = @MainActor (Bool, [AppSpotlightBookRecord]) async throws -> Void

enum AppSpotlightIndexing {
    static let bookDomain = "madar.books"
    static let appDomains = [bookDomain, "madar.notes", "madar.privateNotes"]

    static func records(from books: [Book]) -> [AppSpotlightBookRecord] {
        books
            .filter { $0.deletedAt == nil && $0.mergedInto == nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { .init(id: $0.id, title: $0.title) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func searchableItem(for record: AppSpotlightBookRecord) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = record.title
        return CSSearchableItem(uniqueIdentifier: record.id.uuidString, domainIdentifier: bookDomain, attributeSet: attributes)
    }

    static func removeAppItems(from index: CSSearchableIndex = .default()) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: appDomains)
    }

    static func replaceBookItems(_ records: [AppSpotlightBookRecord], in index: CSSearchableIndex = .default()) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [bookDomain])
        guard !records.isEmpty else { return }
        try await index.indexSearchableItems(records.map(searchableItem(for:)))
    }
}

@MainActor final class AppPrivacyService: MadarLockService {
    private weak var session: AppSession?
    init(session: AppSession) { self.session = session }
    func redactProtectedData() async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        session.redactProtectedData()
        if session.string("core.faceIDLock") == "app" {
            try session.redactSensitiveWidgetSnapshots()
            await redactProtectedRoomNotifications()
            await session.refreshPrayerNotifications()
        }
        let snapshots = session.snapshotStore
        for name in ["notes", "notesToday", "privateNote", "notesMemory"] { try snapshots.remove(name) }
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let ids = requests.filter { $0.identifier.hasPrefix("madar.notes.") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("madar.notes.") }.map { $0.request.identifier })
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["madar.notes", "madar.privateNotes"])
        WidgetCenter.shared.reloadAllTimelines()
    }
    func redactQuranWidgetSnapshotIfLocked() throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        guard session.string("core.faceIDLock") == "app" else { return }
        try session.redactQuranWidgetSnapshot()
    }
    func authorizeAccess(to feature: MadarProtectedFeature) async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        // Room view models fetch only after this authorization and their own lock gate.
        try session.reload(); session.authorizeProtectedData()
    }
    func privacyScopeDidChange(to scope: MadarLockScope) async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        session.beginPrivacyScopeTransition()
        do {
            try session.redactSensitiveWidgetSnapshots()
            if scope.effective == .app { await redactProtectedRoomNotifications() }
            try await session.applySettingsAndWait(["core.faceIDLock": .string(scope.rawValue)])
            try session.finishPrivacyScopeTransition()
        } catch {
            try? session.reload()
            if session.string("core.faceIDLock") == "app" {
                session.beginPrivacyScopeTransition()
                try? session.redactSensitiveWidgetSnapshots()
            } else {
                try? session.finishPrivacyScopeTransition()
            }
            throw error
        }
    }
    static func protectedRoomNotificationIdentifiers(in identifiers: [String]) -> [String] {
        identifiers.filter(RoomNotificationContent.isRoomRequest)
    }
    private func redactProtectedRoomNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: Self.protectedRoomNotificationIdentifiers(in: pending.map(\.identifier)))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: Self.protectedRoomNotificationIdentifiers(in: delivered.map { $0.request.identifier }))
    }
    func persistedPrivacyScope() throws -> MadarLockScope {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        try session.reload() // Settings only; no protected room text is fetched.
        guard let scope = MadarLockScope(rawValue: session.string("core.faceIDLock")) else {
            throw DataError.invalidValue("privacy scope")
        }
        return scope.effective
    }
}
