import Foundation
import WatchConnectivity
import MadarSnapshots

@MainActor final class WatchSnapshotStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var envelope: SnapshotEnvelope<WatchDashboardSnapshot>?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        accept(session.receivedApplicationContext)
        session.activate()
    }

    private func accept(_ context: [String: Any]) {
        guard let data = context["dashboard"] as? Data else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let next = try? decoder.decode(SnapshotEnvelope<WatchDashboardSnapshot>.self, from: data),
              next.name == "watchDashboard", next.schemaVersion == 1,
              TimeZone(identifier: next.tzID) != nil else { return }
        envelope = next
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["dashboard"] as? Data else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let next = try? decoder.decode(SnapshotEnvelope<WatchDashboardSnapshot>.self, from: data),
              next.name == "watchDashboard", next.schemaVersion == 1,
              TimeZone(identifier: next.tzID) != nil else { return }
        Task { @MainActor [weak self] in self?.envelope = next }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }
}
