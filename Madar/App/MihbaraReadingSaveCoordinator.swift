import Foundation
import Observation
import MadarCore
import MadarData
import MadarCommands
#if os(iOS)
import ReadiumShared
#endif

// Shared by the iPhone/iPad reader (Readium) and the Mac readers: one queue of reading-session and position writes per session.

/// Retained by the app session, rather than a reader subtree that an app lock can remove.
@MainActor final class MihbaraReadingSaveCoordinator {
    private static let owners = NSMapTable<AppSession, MihbaraReadingSaveCoordinator>.weakToStrongObjects()
    private weak var app: AppSession?
    private var sessions = PendingReadingSessionQueue()
    private struct LocatorWrite {
        let bookID: UUID
        let commandID: UUID
        let payload: [String: MadarCore.JSONValue]
    }
    private var pendingLocators: [UUID: LocatorWrite] = [:]
    private var failedLocatorEpoch: Int?
    private var lastWriteError: String?
    private var writing: Task<Void, Never>?
    private var wasAuthorized = false

    static func forSession(_ app: AppSession) -> MihbaraReadingSaveCoordinator {
        if let existing = owners.object(forKey: app) { return existing }
        let coordinator = MihbaraReadingSaveCoordinator(app: app)
        owners.setObject(coordinator, forKey: app)
        return coordinator
    }

    static func storeMaintenanceEnded(for app: AppSession) {
        owners.object(forKey: app)?.retryPendingWritesAfterMaintenance()
    }

    private init(app: AppSession) {
        self.app = app
        observeAuthorization()
    }

    var canWrite: Bool {
        guard let app else { return false }
        return app.protectedDataAuthorized
    }
    var hasPending: Bool { !sessions.isEmpty || !pendingLocators.isEmpty }
    var canRetryPendingWritesNow: Bool {
        hasPending && canWrite && app?.maintenanceInProgress != true
    }
    var canRetryPendingWriteErrorNow: Bool {
        canRetryPendingWritesNow && lastWriteError != nil && app?.errorMessage == lastWriteError
    }
    private var canAttempt: Bool {
        sessions.canAttempt || (sessions.isEmpty && !pendingLocators.isEmpty && failedLocatorEpoch != sessions.authorizationEpoch)
    }

    private func observeAuthorization() {
        let authorized = withObservationTracking {
            canWrite
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAuthorization() }
        }
        if authorized && !wasAuthorized {
            sessions.authorizedForegroundReturned()
        }
        wasAuthorized = authorized
        if authorized { flush() }
    }

    func enqueue(sessionID: UUID, payload: [String: MadarCore.JSONValue]) {
        sessions.enqueue(sessionID: sessionID, payload: payload)
        flush()
    }

    #if os(iOS)
    func enqueueLocator(_ locator: Locator, bookID: UUID) {
        do {
            let json = try locator.jsonString()
            enqueueLocatorJSON(json, bookID: bookID)
        } catch { app?.errorMessage = madarUserMessage(error) }
    }
    #endif

    func enqueueLocatorJSON(_ json: String, bookID: UUID) {
        pendingLocators[bookID] = LocatorWrite(bookID: bookID, commandID: UUID(), payload: ["id": .string(bookID.uuidString), "locator": .string(json)])
        flush()
    }

    func waitForCurrentAttempt() async { await writing?.value }

    func retryPendingWritesAfterMaintenance() {
        sessions.authorizedForegroundReturned()
        failedLocatorEpoch = nil
        flush()
    }

    func retryPendingWritesNow() {
        guard canRetryPendingWritesNow else { return }
        sessions.retryRequested()
        failedLocatorEpoch = nil
        flush()
    }

    func dismissPendingWriteError() {
        guard let app, let lastWriteError, app.errorMessage == lastWriteError else { return }
        app.errorMessage = nil
    }

    private func clearRecoveredWriteError(in app: AppSession) {
        guard let lastWriteError else { return }
        self.lastWriteError = nil
        if app.errorMessage == lastWriteError { app.errorMessage = nil }
    }

    func flush() {
        guard writing == nil, canWrite, canAttempt, let app else { return }
        writing = Task { @MainActor [self] in
            defer {
                writing = nil
                // An authorization return during an in-flight failure grants a fresh attempt.
                if canWrite && canAttempt { flush() }
            }
            while canWrite {
                if let write = sessions.beginNext() {
                    do {
                        try await app.executeBookCommand("reading.saveSession", payload: write.payload, id: write.commandID)
                        sessions.finish(commandID: write.commandID, acknowledged: true)
                        clearRecoveredWriteError(in: app)
                    } catch {
                        sessions.finish(commandID: write.commandID, acknowledged: false)
                        lastWriteError = madarUserMessage(error)
                        app.errorMessage = lastWriteError
                        break
                    }
                } else if !sessions.isEmpty {
                    break
                } else if let locator = pendingLocators.values.first, failedLocatorEpoch != sessions.authorizationEpoch {
                    let epoch = sessions.authorizationEpoch
                    do {
                        try await app.executeBookCommand("book.setLocator", payload: locator.payload, id: locator.commandID)
                        if pendingLocators[locator.bookID]?.commandID == locator.commandID {
                            pendingLocators[locator.bookID] = nil
                        }
                        failedLocatorEpoch = nil
                        clearRecoveredWriteError(in: app)
                    } catch {
                        failedLocatorEpoch = epoch
                        lastWriteError = madarUserMessage(error)
                        app.errorMessage = lastWriteError
                        break
                    }
                } else { break }
            }
        }
    }
}
