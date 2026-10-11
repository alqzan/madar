import Foundation
import CoreSpotlight
import UserNotifications
import WidgetKit
import MadarSnapshots
import MadarData

@MainActor final class AppPrivacyService: MadarLockService {
    private weak var session: AppSession?
    init(session: AppSession) { self.session = session }
    func redactProtectedData() async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        session.redactProtectedData()
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
    func authorizeAccess(to feature: MadarProtectedFeature) async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        // Room view models fetch only after this authorization and their own lock gate.
        try session.reload(); session.authorizeProtectedData()
    }
    func privacyScopeDidChange(to scope: MadarLockScope) async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        try await session.applySettingsAndWait(["core.faceIDLock": .string(scope.rawValue)])
    }
    func persistedPrivacyScope() throws -> MadarLockScope {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        try session.reload() // Settings only; no protected room text is fetched.
        guard let scope = MadarLockScope(rawValue: session.string("core.faceIDLock")) else {
            throw DataError.invalidValue("privacy scope")
        }
        return scope
    }
}
