import XCTest
import SwiftUI
import UIKit
@testable import Madar

@MainActor final class PresentationPrivacyTests: XCTestCase {
    func test_M0P1a_sceneCoverLockSymbolExists() { XCTAssertNotNil(UIImage(systemName: "lock")) }
    private final class Service: MadarLockService {
        var bindings: [MadarProtectedFeature] = []
        var purges = 0
        var delayNextBinding = false
        var bindingContinuation: CheckedContinuation<Void, Never>?
        var delayScope = false
        var scopeContinuation: CheckedContinuation<Void, Error>?
        var bindingHook: (@MainActor () -> Void)?
        var persistedScope: MadarLockScope = .app
        var persistThenFail = false
        func redactProtectedData() async throws { purges += 1; bindings.removeAll() }
        func authorizeAccess(to feature: MadarProtectedFeature) async throws {
            if delayNextBinding {
                delayNextBinding = false
                await withCheckedContinuation { bindingContinuation = $0 }
            }
            bindings.append(feature)
            bindingHook?()
        }
        func privacyScopeDidChange(to scope: MadarLockScope) async throws {
            if delayScope { try await withCheckedThrowingContinuation { scopeContinuation = $0 } }
            persistedScope = scope
            if persistThenFail { throw HarnessError.persistenceFailed }
        }
        func persistedPrivacyScope() throws -> MadarLockScope { persistedScope }
    }
    private final class Authenticator: MadarDeviceAuthenticator {
        var calls = 0
        var invalidations = 0
        var delayed = false
        var continuation: CheckedContinuation<Bool, Never>?
        func verify() async throws -> Bool {
            calls += 1
            if delayed { return await withCheckedContinuation { continuation = $0 } }
            return true
        }
        func invalidate() { invalidations += 1 }
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private enum HarnessError: Error { case timeout, persistenceFailed }
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
            await Task.yield()
        }
    }

    func test_M0P1a_inactiveAtAuthorizationCommitRejectsAndCleansBinding() async throws {
        let service = Service()
        var observed: MadarLockController?
        var interrupt = true
        let lock = MadarLockController(scope: .app, service: service, authenticator: { Authenticator() }, authorizationCommitBoundary: {
            if interrupt { interrupt = false; observed?.sceneChanged(.inactive) }
        })
        observed = lock
        do { _ = try await lock.authorize([.app]); XCTFail("Inactive completion committed authorization") } catch { }
        XCTAssertTrue(lock.covered); XCTAssertTrue(lock.unlocked.isEmpty); XCTAssertFalse(lock.canPresent(.app))
        try await waitUntil { service.bindings.isEmpty && service.purges > 0 }
        lock.sceneChanged(.active)
        let fresh = try await lock.authorize([.app])
        XCTAssertEqual(service.bindings, [.app]); XCTAssertNoThrow(try lock.validate(fresh))
    }

    private func scopeLifecycleProbe(disconnect: Bool, outcome: Int, cancel: Bool = false) async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        let service = Service(); service.delayScope = true; service.persistThenFail = outcome == 2
        let origin = MadarLockController(scope: .app, service: service, authenticator: { Authenticator() })
        let peer = MadarLockController(scope: .app, service: Service(), authenticator: { Authenticator() })
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
        let presenter = ScenePrivacyPresenter(controller: peer, activationState: { _ in .foregroundActive })
        presenter.attach(to: window); defer { presenter.detach() }
        _ = try await origin.authorize([.app])
        let oldTicket = try await peer.authorize([.notes])
        let request = Task { try await origin.changeScope(.notesOnly) }
        try await waitUntil { service.scopeContinuation != nil }
        if disconnect { origin.disconnect() } else { origin.sceneChanged(.background) }
        if cancel { request.cancel() }
        // An overlapping writer cannot persist behind the disconnected origin.
        do { try await peer.changeScope(.none); XCTFail("Concurrent scope writer accepted") } catch { }
        if outcome == 1 { service.scopeContinuation?.resume(throwing: HarnessError.persistenceFailed) }
        else { service.scopeContinuation?.resume() }
        service.scopeContinuation = nil
        if outcome == 0 && !cancel { try await request.value }
        else { do { try await request.value; XCTFail("Expected persistence failure") } catch { } }
        await settle()
        let expected: MadarLockScope = outcome == 1 ? .app : .none
        XCTAssertEqual(service.persistedScope, expected); XCTAssertEqual(origin.scope, expected); XCTAssertEqual(peer.scope, expected)
        XCTAssertTrue(peer.covered, "Scope completion must not reopen a revoked presentation")
        XCTAssertThrowsError(try peer.validate(oldTicket)); XCTAssertFalse(peer.canPresent(.notes))
        XCTAssertTrue(origin.covered); XCTAssertFalse(origin.canPresent(.app))
        let fresh = try await peer.authorize([.notes])
        XCTAssertNoThrow(try peer.validate(fresh))
    }

    func test_M0P1a_scopeBackgroundDoesNotStrandPeers() async throws {
        for outcome in 0...2 { try await scopeLifecycleProbe(disconnect: false, outcome: outcome) }
    }

    func test_M0P1a_scopeDisconnectDoesNotStrandPeers() async throws {
        for outcome in 0...2 { try await scopeLifecycleProbe(disconnect: true, outcome: outcome) }
    }

    func test_M0P1a_scopeCancelledPersistenceReconcilesCommittedSetting() async throws {
        try await scopeLifecycleProbe(disconnect: false, outcome: 0, cancel: true)
    }

    func test_M0P1a_scopeFinalizationCannotClearNewerRequest() async throws {
        let controller = MadarLockController(scope: .app, service: Service(), authenticator: { Authenticator() })
        let old = UUID(), newer = UUID()
        controller.receiveScopeRevocation(old); controller.receiveScopeRevocation(newer)
        controller.finishScopeTransition(old, persisted: MadarLockScope.none, failed: false)
        XCTAssertEqual(controller.scope, .app); XCTAssertTrue(controller.covered)
        do { _ = try await controller.authorize([.app]); XCTFail("Older completion cleared newer pending scope") } catch { }
        controller.finishScopeTransition(newer, persisted: .app, failed: true)
        let ticket = try await controller.authorize([.app]); XCTAssertNoThrow(try controller.validate(ticket))
    }

    func test_M0P1a_lateBackgroundAttachmentStartsStableLeaseAtObservedBoundary() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        for elapsed: TimeInterval in [59, 60] {
            var now = Date(timeIntervalSince1970: 2_000)
            let auth = Authenticator()
            let lock = MadarLockController(scope: .app, service: Service(), clock: { now }, authenticator: { auth })
            _ = try await lock.authorize([.app])
            let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
            let presenter = ScenePrivacyPresenter(controller: lock, activationState: { owning in
                XCTAssertTrue(owning === scene); return .background
            })
            presenter.attach(to: window)
            defer { presenter.detach() }
            XCTAssertTrue(lock.covered)
            now = now.addingTimeInterval(50); presenter.transition(.background)
            now = Date(timeIntervalSince1970: 2_000 + elapsed); presenter.transition(.active)
            try await waitUntil { !lock.covered }
            XCTAssertEqual(lock.canPresent(.app), elapsed < 60)
            XCTAssertEqual(auth.calls, 1)
        }
    }

    func test_M0P1a_lateBackgroundAttachmentInvalidatesPendingAuthAndUnattachedClearsLease() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        let auth = Authenticator(); auth.delayed = true
        let service = Service()
        let lock = MadarLockController(scope: .app, service: service, authenticator: { auth })
        let old = Task { try await lock.authorize([.app]) }
        try await waitUntil { auth.continuation != nil }
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
        let presenter = ScenePrivacyPresenter(controller: lock, activationState: { _ in .background })
        presenter.attach(to: window)
        defer { presenter.detach() }
        XCTAssertEqual(auth.invalidations, 1); XCTAssertTrue(lock.covered)
        auth.continuation?.resume(returning: true); auth.continuation = nil
        do { _ = try await old.value; XCTFail("Background attachment accepted late auth") } catch { }
        XCTAssertTrue(service.bindings.isEmpty)
        let other = MadarLockController(scope: .app, service: Service(), authenticator: { Authenticator() })
        _ = try await other.authorize([.app])
        let unattached = ScenePrivacyPresenter(controller: other, activationState: { _ in .unattached })
        unattached.attach(to: window)
        defer { unattached.detach() }
        XCTAssertTrue(other.covered); XCTAssertTrue(other.unlocked.isEmpty)
        unattached.transition(.active); try await waitUntil { !other.covered }
        XCTAssertFalse(other.canPresent(.app))
    }

    func test_M0P1a_cancelledVerifierReleasesRequestWithoutWaitingForLateResult() async throws {
        let first = Authenticator(), second = Authenticator(), service = Service(); first.delayed = true
        var next = first
        let lock = MadarLockController(scope: .app, service: service, authenticator: { next })
        let old = Task { try await lock.authorize([.app]) }
        try await waitUntil { first.continuation != nil }
        old.cancel()
        try await waitUntil { first.invalidations == 1 && !lock.authenticating }
        next = second
        let ticket = try await lock.authorize([.app])
        first.continuation?.resume(returning: true); first.continuation = nil
        do { _ = try await old.value; XCTFail("Cancelled request succeeded") } catch { }
        XCTAssertEqual(service.bindings, [.app]); XCTAssertNoThrow(try lock.validate(ticket))
        XCTAssertFalse(lock.covered)
    }

    func test_M0P1a_cancelledInactiveWaiterIsWokenAndNewRequestCanAuthorize() async throws {
        let auth = Authenticator(); auth.delayed = true
        let lock = MadarLockController(scope: .app, service: Service(), authenticator: { auth })
        let old = Task { try await lock.authorize([.app]) }
        try await waitUntil { auth.continuation != nil }
        lock.sceneChanged(.inactive)
        auth.continuation?.resume(returning: true); auth.continuation = nil
        await settle(); XCTAssertTrue(lock.authenticating)
        old.cancel()
        try await waitUntil { auth.invalidations == 1 && !lock.authenticating }
        // The old task finishes while the scene is still inactive, without an active notification.
        do { _ = try await old.value; XCTFail("Cancelled inactive waiter succeeded") } catch { }
        auth.delayed = false; lock.sceneChanged(.active)
        let ticket = try await lock.authorize([.app])
        XCTAssertNoThrow(try lock.validate(ticket)); XCTAssertEqual(auth.calls, 2)
    }

    func test_M0P1a_cancellationAtBindingCompletionPurgesBeforeNewBinding() async throws {
        let service = Service()
        let lock = MadarLockController(scope: .app, service: service, authenticator: { Authenticator() })
        var request: Task<PrivacyAuthorization, Error>?
        service.bindingHook = { request?.cancel() }
        request = Task { try await lock.authorize([.app]) }
        do { _ = try await request?.value; XCTFail("Cancellation at binding completion succeeded") } catch { }
        service.bindingHook = nil
        try await waitUntil { service.purges > 0 && service.bindings.isEmpty && !lock.authenticating }
        XCTAssertFalse(lock.canPresent(.app))
        let fresh = try await lock.authorize([.app])
        XCTAssertEqual(service.bindings, [.app]); XCTAssertNoThrow(try lock.validate(fresh))
    }

    func test_M0P1a_scopeChangeImmediatelyRevokesOtherScene() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        let firstService = Service(); firstService.delayScope = true
        let first = MadarLockController(scope: .app, service: firstService, authenticator: { Authenticator() })
        let second = MadarLockController(scope: .app, service: Service(), authenticator: { Authenticator() })
        let firstWindow = UIWindow(windowScene: scene), secondWindow = UIWindow(windowScene: scene)
        firstWindow.rootViewController = UIViewController(); secondWindow.rootViewController = UIViewController()
        let firstPresenter = ScenePrivacyPresenter(controller: first), secondPresenter = ScenePrivacyPresenter(controller: second)
        firstPresenter.attach(to: firstWindow); secondPresenter.attach(to: secondWindow)
        firstPresenter.transition(.active); secondPresenter.transition(.active)
        defer { firstPresenter.detach(); secondPresenter.detach() }
        _ = try await first.authorize([.app])
        let ticket = try await second.authorize([.app])
        // Observer runs synchronously in the sender's pre-await notification prefix.
        var revokedBeforePersistence = false
        let observer = second.observeRevocation { _ in
            revokedBeforePersistence = second.covered && firstService.scopeContinuation == nil
        }
        defer { second.removeObserver(observer) }
        let request = Task { try await first.changeScope(.notesOnly) }
        try await waitUntil { firstService.scopeContinuation != nil }
        XCTAssertTrue(revokedBeforePersistence); XCTAssertTrue(second.covered)
        XCTAssertFalse(try XCTUnwrap(secondPresenter.coverWindow).isHidden)
        XCTAssertThrowsError(try second.validate(ticket)); XCTAssertEqual(second.scope, .app)
        firstService.scopeContinuation?.resume(throwing: HarnessError.persistenceFailed); firstService.scopeContinuation = nil
        do { try await request.value; XCTFail("Persistence unexpectedly succeeded") } catch { }
        await settle(); XCTAssertTrue(second.covered); XCTAssertTrue(second.redactionFailed)
        XCTAssertEqual(second.scope, .app); XCTAssertThrowsError(try second.validate(ticket))
    }

    func test_M0P1a_staleVerifierCannotPurgeNewAuthorization() async throws {
        let first = Authenticator(), second = Authenticator(), service = Service(); first.delayed = true
        var next = first
        let lock = MadarLockController(scope: .app, service: service, authenticator: { next })
        let old = Task { try await lock.authorize([.app]) }
        await settle(); XCTAssertNotNil(first.continuation)
        lock.sceneChanged(.background); lock.sceneChanged(.active)
        next = second
        let ticket = try await lock.authorize([.app])
        let purges = service.purges
        first.continuation?.resume(returning: true); first.continuation = nil
        do { _ = try await old.value; XCTFail("Stale verifier succeeded") } catch { }
        await settle()
        XCTAssertEqual(service.purges, purges); XCTAssertEqual(service.bindings, [.app])
        XCTAssertFalse(lock.covered); XCTAssertNoThrow(try lock.validate(ticket))
    }

    func test_M0P1a_staleBindingCleanupPrecedesNewAuthorization() async throws {
        let service = Service(); service.delayNextBinding = true
        let lock = MadarLockController(scope: .app, service: service, authenticator: { Authenticator() })
        let old = Task { try await lock.authorize([.app]) }
        await settle(); XCTAssertNotNil(service.bindingContinuation)
        lock.sceneChanged(.background); lock.sceneChanged(.active)
        let fresh = Task { try await lock.authorize([.app]) }
        await settle(); XCTAssertTrue(lock.covered); XCTAssertTrue(service.bindings.isEmpty)
        service.bindingContinuation?.resume(); service.bindingContinuation = nil
        do { _ = try await old.value; XCTFail("Stale binding succeeded") } catch { }
        let ticket = try await fresh.value
        XCTAssertEqual(service.bindings, [.app]); XCTAssertFalse(lock.covered)
        XCTAssertNoThrow(try lock.validate(ticket)); XCTAssertGreaterThan(service.purges, 0)
    }

    func testPrivateNoteFollowsWholeAppLockAndTicketHasSceneOwner() async throws {
        let auth = Authenticator(), service = Service()
        let first = MadarLockController(scope: .none, service: service, authenticator: { auth })
        let second = MadarLockController(scope: .none, service: Service())
        XCTAssertTrue(first.canPresent(.app)); XCTAssertTrue(first.canPresent(.privateNote))
        let ticket = try await first.authorize([.privateNote])
        XCTAssertEqual(auth.calls, 0); XCTAssertEqual(service.bindings, [.privateNote])
        XCTAssertNoThrow(try first.validate(ticket))
        XCTAssertThrowsError(try second.validate(ticket))
        first.sceneChanged(.inactive)
        XCTAssertTrue(first.covered); XCTAssertThrowsError(try first.validate(ticket))
        XCTAssertTrue(second.canPresent(.app), "One controller cannot cover another scene")
    }

    func testPrivateNoteSharesTheWholeAppUnlock() async throws {
        let auth = Authenticator(), service = Service()
        let lock = MadarLockController(scope: .app, service: service, authenticator: { auth })
        XCTAssertFalse(lock.canPresent(.privateNote))
        _ = try await lock.authorize([.app])
        XCTAssertTrue(lock.canPresent(.privateNote))
        _ = try await lock.authorize([.privateNote])
        XCTAssertEqual(auth.calls, 1)
        XCTAssertEqual(service.bindings, [.app, .privateNote])
    }

    func testBackgroundLeaseUsesFirstTimestampAndExpiresAtSixtySeconds() async throws {
        let auth = Authenticator()
        let lock = MadarLockController(scope: .app, service: Service(), authenticator: { auth })
        let start = Date(timeIntervalSince1970: 1_000)
        _ = try await lock.authorize([.app])
        lock.sceneChanged(.background, now: start)
        lock.sceneChanged(.background, now: start.addingTimeInterval(50))
        lock.sceneChanged(.active, now: start.addingTimeInterval(59)); await settle()
        XCTAssertTrue(lock.canPresent(.app)); XCTAssertEqual(auth.calls, 1)
        lock.sceneChanged(.background, now: start)
        lock.sceneChanged(.background, now: start.addingTimeInterval(59))
        lock.sceneChanged(.active, now: start.addingTimeInterval(60)); await settle()
        XCTAssertFalse(lock.canPresent(.app)); XCTAssertTrue(lock.unlocked.isEmpty)
    }

    func testLateDeviceSuccessAfterBackgroundCannotBindProtectedRows() async throws {
        let auth = Authenticator(), service = Service(); auth.delayed = true
        let lock = MadarLockController(scope: .app, service: service, authenticator: { auth })
        let request = Task { try await lock.authorize([.app]) }
        await settle(); XCTAssertNotNil(auth.continuation)
        lock.sceneChanged(.background)
        auth.continuation?.resume(returning: true); auth.continuation = nil
        do { _ = try await request.value; XCTFail("Stale authentication succeeded") } catch { }
        XCTAssertEqual(auth.invalidations, 1); XCTAssertTrue(service.bindings.isEmpty)
        XCTAssertFalse(lock.canPresent(.app))
    }

    /// Real UIWindowScene/controller objects with a controlled native adapter.
    /// This proves revocation ordering, not an OS activity/switcher capture.
    @MainActor private final class ActivityProbe {
        var presentations = 0
        var retirements = 0
        var completion: (@MainActor @Sendable () -> Void)?
        func present(_ host: UIViewController, _ activity: UIActivityViewController) { presentations += 1 }
        func retire(_ activity: UIActivityViewController, _ completion: @escaping @MainActor @Sendable () -> Void) {
            retirements += 1; self.completion = completion
        }
        func finishRetirement() { let callback = completion; completion = nil; callback?() }
    }
    private func activeShareRevocation(scope: MadarLockScope, scopeChange: Bool) async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        let oldKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible(); root.loadViewIfNeeded()
        let service = Service(), auth = Authenticator(), probe = ActivityProbe()
        service.persistedScope = scope
        let lock = MadarLockController(scope: scope, service: service, authenticator: { auth })
        let presenter = ScenePrivacyPresenter(controller: lock, activationState: { _ in .foregroundActive },
            presentActivity: { probe.present($0, $1) }, retireActivity: { probe.retire($0, $1) })
        presenter.attach(to: window)
        let file = FileManager.default.temporaryDirectory.appending(path: "MadarPrivateShare-\(UUID()).zip")
        try Data("synthetic private export".utf8).write(to: file)
        defer {
            presenter.detach(); probe.finishRetirement(); window.isHidden = true; oldKey?.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: file)
        }
        let ticket = try await lock.authorize([.export, .privateNote])
        try presenter.present(file: file, authorization: ticket)
        XCTAssertTrue(presenter.hasActivityRequest); XCTAssertEqual(probe.presentations, 1)
        if scopeChange {
            service.delayScope = true
            let change = Task { try await lock.changeScope(scope == .none ? .notesOnly : .none) }
            try await waitUntil { service.scopeContinuation != nil }
            // Owning-controller revocation occurs before persistence suspends.
            XCTAssertFalse(presenter.hasActivityRequest); XCTAssertEqual(probe.retirements, 1)
            XCTAssertEqual(presenter.coverWindow?.isHidden, false)
            service.scopeContinuation?.resume(); service.scopeContinuation = nil
            try await change.value
        } else {
            lock.lock()
            // No Task/settle is needed to retire the active presentation request.
            XCTAssertFalse(presenter.hasActivityRequest); XCTAssertEqual(probe.retirements, 1)
            XCTAssertEqual(presenter.coverWindow?.isHidden, false)
        }
        XCTAssertThrowsError(try lock.validate(ticket))
        _ = try await lock.authorize([.app])
        XCTAssertEqual(probe.presentations, 1); XCTAssertFalse(presenter.hasActivityRequest)
        XCTAssertEqual(presenter.coverWindow?.isHidden, false, "Cover must outlive native dismissal")
        probe.finishRetirement()
        XCTAssertEqual(presenter.coverWindow?.isHidden, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(probe.presentations, 1, "Generic authorization cannot reopen sharing")
        // An explicit share tap with fresh payload authorization remains usable.
        let fresh = try await lock.authorize([.export, .privateNote])
        try presenter.present(file: file, authorization: fresh)
        XCTAssertEqual(probe.presentations, 2)
    }
    func test_M0P1b_03_activeLockRetiresPrivateShareIncludingScopeNone() async throws {
        for scope: MadarLockScope in [.none, .notesOnly, .app] { try await activeShareRevocation(scope: scope, scopeChange: false) }
    }
    func test_M0P1b_03_localScopeChangeRetiresPrivateShareBeforeGenericAuthorization() async throws {
        for scope: MadarLockScope in [.none, .notesOnly, .app] { try await activeShareRevocation(scope: scope, scopeChange: true) }
    }

    func testNativeInactiveCoverIsSynchronousNonKeyAndAbovePresentedController() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Requires an app-host UIWindowScene")
        }
        let oldKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        let modal = UIViewController()
        root.present(modal, animated: false)
        let lock = MadarLockController(scope: .none, service: Service())
        let presenter = ScenePrivacyPresenter(controller: lock); presenter.attach(to: window)
        defer {
            presenter.detach(); root.dismiss(animated: false); window.isHidden = true
            oldKey?.makeKeyAndVisible()
        }
        NotificationCenter.default.post(name: UIWindowScene.willDeactivateNotification, object: scene)
        let cover = try XCTUnwrap(presenter.coverWindow)
        XCTAssertFalse(cover.isHidden); XCTAssertFalse(cover.isKeyWindow)
        XCTAssertTrue(window.isKeyWindow); XCTAssertGreaterThan(cover.windowLevel, window.windowLevel)
        XCTAssertTrue(window.accessibilityElementsHidden); XCTAssertTrue(lock.covered)
        XCTAssertTrue(root.presentedViewController === modal)
    }
}
