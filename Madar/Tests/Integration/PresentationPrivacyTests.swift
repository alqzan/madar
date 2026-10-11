import XCTest
import SwiftUI
import UIKit
@testable import Madar

@MainActor final class PresentationPrivacyTests: XCTestCase {
    private final class Service: MadarLockService {
        var bindings: [MadarProtectedFeature] = []
        var purges = 0
        func redactProtectedData() async throws { purges += 1; bindings.removeAll() }
        func authorizeAccess(to feature: MadarProtectedFeature) async throws { bindings.append(feature) }
        func privacyScopeDidChange(to scope: MadarLockScope) async throws { }
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
