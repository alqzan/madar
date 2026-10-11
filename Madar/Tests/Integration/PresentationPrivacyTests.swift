import XCTest
import SwiftUI
import UIKit
@testable import Madar

@MainActor final class PresentationPrivacyTests: XCTestCase {
    private final class Service: MadarLockService {
        var bindings: [MadarProtectedFeature] = []
        var purges = 0
        var delayNextBinding = false
        var bindingContinuation: CheckedContinuation<Void, Never>?
        var delayScope = false
        var scopeContinuation: CheckedContinuation<Void, Error>?
        func redactProtectedData() async throws { purges += 1; bindings.removeAll() }
        func authorizeAccess(to feature: MadarProtectedFeature) async throws {
            if delayNextBinding {
                delayNextBinding = false
                await withCheckedContinuation { bindingContinuation = $0 }
            }
            bindings.append(feature)
        }
        func privacyScopeDidChange(to scope: MadarLockScope) async throws {
            if delayScope { try await withCheckedThrowingContinuation { scopeContinuation = $0 } }
        }
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

    func testPrivateNoteAlwaysRequiresDeviceAuthenticationAndTicketHasSceneOwner() async throws {
        let auth = Authenticator(), service = Service()
        let first = MadarLockController(scope: .none, service: service, authenticator: { auth })
        let second = MadarLockController(scope: .none, service: Service())
        XCTAssertTrue(first.canPresent(.app)); XCTAssertFalse(first.canPresent(.privateNote))
        let ticket = try await first.authorize([.privateNote])
        XCTAssertEqual(auth.calls, 1); XCTAssertEqual(service.bindings, [.privateNote])
        XCTAssertNoThrow(try first.validate(ticket))
        XCTAssertThrowsError(try second.validate(ticket))
        first.sceneChanged(.inactive)
        XCTAssertTrue(first.covered); XCTAssertThrowsError(try first.validate(ticket))
        XCTAssertTrue(second.canPresent(.app), "One controller cannot cover another scene")
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
