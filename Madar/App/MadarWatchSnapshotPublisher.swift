#if os(iOS)
import Foundation
import WatchConnectivity
import MadarSnapshots

/// Sends one compact latest-value dashboard. The Watch never opens SwiftData or writes to Madar.
@MainActor final class MadarWatchSnapshotPublisher: NSObject, WCSessionDelegate {
    static let shared = MadarWatchSnapshotPublisher()
    private let session = WCSession.default
    private var latestSnapshot: Data?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func publish(_ envelope: SnapshotEnvelope<WatchDashboardSnapshot>) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        latestSnapshot = try encoder.encode(envelope)
        sendIfReady()
    }

    private func sendIfReady() {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let latestSnapshot else { return }
        try? session.updateApplicationContext(["dashboard": latestSnapshot])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.sendIfReady() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
