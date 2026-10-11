import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import MadarDesign

enum MadarLockScope: String, Sendable { case app, notesOnly, none }
enum MadarProtectedFeature: Hashable, Sendable { case app, notes, privateNote, export }

/// The adapter purges protected view models before returning and regenerates redacted external surfaces.
/// Protected rows are fetched only in authorizeAccess, after successful device authentication.
@MainActor protocol MadarLockService: AnyObject {
    func redactProtectedData() async throws
    func authorizeAccess(to feature: MadarProtectedFeature) async throws
    func privacyScopeDidChange(to scope: MadarLockScope) async throws
}

@MainActor protocol MadarDeviceAuthenticator: AnyObject {
    func verify() async throws -> Bool
    func invalidate()
}
@MainActor final class SystemDeviceAuthenticator: MadarDeviceAuthenticator {
    private let context = LAContext()
    func verify() async throws -> Bool {
        context.localizedCancelTitle = "إلغاء"; context.localizedFallbackTitle = "رمز الجهاز"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw PrivacyAuthorizationError.refused }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح بيانات مدار المحمية")
    }
    func invalidate() { context.invalidate() }
}
enum PrivacyAuthorizationError: Error { case refused, stale, busy }
struct PrivacyAuthorization {
    let owner: UUID; let generation: Int; let epoch: Int; let features: Set<MadarProtectedFeature>
}

@MainActor @Observable final class MadarLockController {
    private(set) var scope: MadarLockScope
    private(set) var covered = false
    private(set) var authenticating = false
    private(set) var statusMessage: String?
    private(set) var unlocked: Set<MadarProtectedFeature> = []
    private(set) var redactionFailed = false
    let identity = UUID()
    private let service: any MadarLockService
    private let clock: @MainActor () -> Date
    private let authenticator: @MainActor () -> any MadarDeviceAuthenticator
    private var currentAuth: (UUID, any MadarDeviceAuthenticator)?
    private var backgroundAt: Date?
    private var authorizedFeatures: Set<MadarProtectedFeature> = []
    private var generation = 0
    private var epoch = 0
    private var phase: ScenePhase = .active
    private var disconnected = false
    private var scopeTransitionPending = false
    private var redactionTask: Task<Void, Error>?
    private var activeWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var stateObservers: [UUID: @MainActor () -> Void] = [:]
    private var revokeObservers: [UUID: @MainActor (Bool) -> Void] = [:]
    init(scope: MadarLockScope, service: any MadarLockService, clock: @escaping @MainActor () -> Date = Date.init,
         authenticator: @escaping @MainActor () -> any MadarDeviceAuthenticator = { SystemDeviceAuthenticator() }) {
        self.scope = scope; self.service = service; self.clock = clock; self.authenticator = authenticator
    }
    private func requiredFeature(for feature: MadarProtectedFeature) -> MadarProtectedFeature? {
        if feature == .privateNote { return .privateNote }
        if scope == .app { return .app }
        if scope == .notesOnly && (feature == .notes || feature == .export) { return .notes }
        return nil
    }
    func requiresProtection(_ feature: MadarProtectedFeature) -> Bool { requiredFeature(for: feature) != nil }
    func canPresent(_ feature: MadarProtectedFeature) -> Bool {
        guard phase == .active, !disconnected, !covered, !redactionFailed, !scopeTransitionPending else { return false }
        return requiredFeature(for: feature).map { unlocked.contains($0) } ?? true
    }
    func validate(_ ticket: PrivacyAuthorization) throws {
        guard !Task.isCancelled, ticket.owner == identity, ticket.generation == generation, ticket.epoch == epoch,
              ticket.features.allSatisfy({ canPresent($0) }) else { throw PrivacyAuthorizationError.stale }
    }
    func observeState(_ handler: @escaping @MainActor () -> Void) -> UUID { let id = UUID(); stateObservers[id] = handler; return id }
    func observeRevocation(_ handler: @escaping @MainActor (Bool) -> Void) -> UUID { let id = UUID(); revokeObservers[id] = handler; return id }
    func removeObserver(_ id: UUID) { stateObservers.removeValue(forKey: id); revokeObservers.removeValue(forKey: id) }
    private func notify() { for handler in Array(stateObservers.values) { handler() } }
    private func revoke(cancelRequests: Bool) {
        for handler in Array(revokeObservers.values) { handler(cancelRequests) }; notify()
    }
    private func invalidateAuth() {
        currentAuth?.1.invalidate(); currentAuth = nil; authenticating = false
        let waiters = activeWaiters; activeWaiters.removeAll(); for waiter in waiters.values { waiter.resume() }
    }
    private func cancelAuthorization(_ id: UUID) {
        guard currentAuth?.0 == id else { return }
        generation += 1; covered = true; invalidateAuth()
        revoke(cancelRequests: true); enqueueRedaction(); recoverActive()
    }
    private func enqueueRedaction() {
        let previous = redactionTask
        redactionTask = Task { [service] in _ = try? await previous?.value; try await service.redactProtectedData() }
    }
    /// All service mutations share the same queue. A stale binding is purged
    /// under the cover before any newer binding can start.
    private func bind(_ features: Set<MadarProtectedFeature>, valid: @escaping @MainActor () -> Bool) async throws {
        let previous = redactionTask
        let operation = Task { [self] in
            try await previous?.value
            guard valid() else { throw PrivacyAuthorizationError.stale }
            var started = false
            do {
                for feature in features {
                    guard valid() else { throw PrivacyAuthorizationError.stale }
                    started = true
                    try await service.authorizeAccess(to: feature)
                    guard valid() else { throw PrivacyAuthorizationError.stale }
                }
            } catch {
                if started {
                    covered = true; revoke(cancelRequests: false)
                    do { try await service.redactProtectedData() }
                    catch { redactionFailed = true; notify(); throw error }
                }
                throw error
            }
        }
        redactionTask = operation
        try await operation.value
    }
    func authorize(_ features: Set<MadarProtectedFeature>) async throws -> PrivacyAuthorization {
        guard phase == .active, !disconnected, !scopeTransitionPending else { throw PrivacyAuthorizationError.stale }
        guard currentAuth == nil else { throw PrivacyAuthorizationError.busy }
        let id = UUID(), stamp = generation
        let needed = Set(features.compactMap { requiredFeature(for: $0) })
        let device = authenticator(); currentAuth = (id, device)
        defer {
            // Cancellation can win immediately after a completed service binding,
            // before its asynchronously dispatched handler reaches the actor.
            if Task.isCancelled { cancelAuthorization(id) }
            if currentAuth?.0 == id { currentAuth = nil; authenticating = false; notify(); if covered && phase == .active { recoverActive() } }
        }
        return try await withTaskCancellationHandler {
            try await performAuthorization(features, id: id, stamp: stamp, needed: needed, device: device)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelAuthorization(id) }
        }
    }
    private func performAuthorization(_ features: Set<MadarProtectedFeature>, id: UUID, stamp: Int,
                                      needed: Set<MadarProtectedFeature>, device: any MadarDeviceAuthenticator) async throws -> PrivacyAuthorization {
        func current() throws {
            try Task.checkCancellation()
            guard currentAuth?.0 == id, generation == stamp, !disconnected else { throw PrivacyAuthorizationError.stale }
        }
        do {
            try current()
            if !needed.isSubset(of: unlocked) {
                authenticating = true; statusMessage = nil; notify()
                guard try await device.verify() else { throw PrivacyAuthorizationError.refused }
                try current()
            }
            // LA may temporarily deactivate its owning scene. Keep this request through that
            // transition, but background/scope/disconnect invalidates it and wakes the waiter.
            while phase != .active { await withCheckedContinuation { activeWaiters[id] = $0 }; try current() }
            if redactionFailed { enqueueRedaction() }
            try await redactionTask?.value; try current()
            guard phase == .active else { throw PrivacyAuthorizationError.stale }
            let activeEpoch = epoch
            try await bind(features) { [self] in
                currentAuth?.0 == id && generation == stamp && !disconnected && phase == .active && epoch == activeEpoch
            }
            try current()
            unlocked.formUnion(needed); authorizedFeatures.formUnion(features); redactionFailed = false; covered = false; notify()
            return .init(owner: identity, generation: generation, epoch: epoch, features: features)
        } catch {
            if currentAuth?.0 == id {
                statusMessage = "لم يُفتح القفل. يمكنك المحاولة مرة أخرى."
                if !(error is PrivacyAuthorizationError) && !(error is CancellationError) { redactionFailed = true; covered = true; notify() }
            }
            throw error
        }
    }
    func authenticate(for feature: MadarProtectedFeature) {
        guard phase == .active, currentAuth == nil else { return }
        Task { [self] in _ = try? await authorize([feature]) }
    }
    func lock() {
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        revoke(cancelRequests: true); enqueueRedaction(); recoverActive()
    }
    func changeScope(_ newScope: MadarLockScope) async throws {
        scopeTransitionPending = true
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        let stamp = generation; revoke(cancelRequests: true)
        // Every scene revokes before the first suspension, independently of persistence.
        NotificationCenter.default.post(name: .madarPrivacyScopeWillChange, object: self)
        enqueueRedaction()
        do {
            try await redactionTask?.value
            guard generation == stamp, !disconnected else { throw PrivacyAuthorizationError.stale }
            try await service.privacyScopeDidChange(to: newScope)
            guard generation == stamp, !disconnected else { throw PrivacyAuthorizationError.stale }
            scope = newScope; scopeTransitionPending = false; redactionFailed = false; recoverActive()
            NotificationCenter.default.post(name: .madarPrivacyScopeChanged, object: self, userInfo: ["scope": newScope.rawValue])
        } catch {
            if generation == stamp {
                scopeTransitionPending = false; redactionFailed = true; covered = true; notify()
                NotificationCenter.default.post(name: .madarPrivacyScopeChangeFailed, object: self)
            }
            throw error
        }
    }
    func receiveScopeRevocation() {
        scopeTransitionPending = true
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        revoke(cancelRequests: true); enqueueRedaction()
    }
    func receiveScopeFailure() { scopeTransitionPending = false; redactionFailed = true; covered = true; notify() }
    func receiveScope(_ newScope: MadarLockScope) { scopeTransitionPending = false; scope = newScope; lock() }
    func disconnect() { disconnected = true; epoch += 1; phase = .background; lock() }
    func sceneChanged(_ next: ScenePhase, now: Date? = nil) {
        guard !disconnected, next != phase else { return }
        epoch += 1; phase = next
        switch next {
        case .inactive:
            covered = true; revoke(cancelRequests: false); enqueueRedaction()
        case .background:
            covered = true; backgroundAt = backgroundAt ?? now ?? clock(); generation += 1; invalidateAuth()
            revoke(cancelRequests: true); enqueueRedaction()
        case .active:
            let expired = backgroundAt.map { (now ?? clock()).timeIntervalSince($0) >= 60 } ?? false
            backgroundAt = nil
            let waiters = activeWaiters; activeWaiters.removeAll(); for waiter in waiters.values { waiter.resume() }
            if expired { lock() } else { recoverActive() }
        @unknown default: lock()
        }
    }
    private func recoverActive() {
        guard phase == .active, !disconnected, !scopeTransitionPending else { return }
        let stamp = generation, activeEpoch = epoch
        Task { [self] in
            do {
                try await redactionTask?.value
                guard generation == stamp, epoch == activeEpoch, phase == .active, !disconnected, !scopeTransitionPending else { return }
                // The auth request owns its binding and exposure commit.
                guard currentAuth == nil else { return }
                try await bind(authorizedFeatures) { [self] in
                    generation == stamp && epoch == activeEpoch && phase == .active && !disconnected && currentAuth == nil
                }
                guard generation == stamp, epoch == activeEpoch, phase == .active, !disconnected else { return }
                redactionFailed = false; covered = false; notify()
            } catch {
                guard generation == stamp, epoch == activeEpoch else { return }
                unlocked.removeAll(); authorizedFeatures.removeAll(); redactionFailed = true; covered = true; notify()
            }
        }
    }
}
extension Notification.Name {
    static let madarPrivacyScopeWillChange = Notification.Name("MadarPrivacyScopeWillChange")
    static let madarPrivacyScopeChanged = Notification.Name("MadarPrivacyScopeChanged")
    static let madarPrivacyScopeChangeFailed = Notification.Name("MadarPrivacyScopeChangeFailed")
}

/// Caller must not fetch protected rows before canPresent succeeds. This closure is evaluated only after the guard.
struct MadarLockGate<Content: View>: View {
    @Bindable var controller: MadarLockController
    let feature: MadarProtectedFeature
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Group {
            if !controller.requiresProtection(feature) {
                // The unprotected shell stays mounted across system prompts and app switching.
                // Protected child gates still remove their content and the adapter purges its rows.
                content()
                    .allowsHitTesting(!controller.covered)
                    .accessibilityHidden(controller.covered)
                    .overlay { if controller.covered { privacyCover } }
            } else if controller.canPresent(feature) { content() }
            else { lockedContent }
        }
    }
    private var privacyCover: some View {
        ZStack { theme.background.ignoresSafeArea(); Image(systemName: "lock.closed").font(.largeTitle).foregroundStyle(theme.ink) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
    private var lockedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.closed").font(.largeTitle).accessibilityHidden(true)
            Text(feature == .notes ? "المذكرات مقفلة" : "مدار مقفل").font(MadarTypography.title())
            if let message = controller.statusMessage { Text(message).font(MadarTypography.caption()) }
            if controller.authenticating { ProgressView("يفتح القفل…") }
            else if !controller.covered {
                Button("افتح القفل") { controller.authenticate(for: feature) }
                    .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("lock-authenticate")
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(theme.ink).background(theme.background)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("protected-lock-screen")
    }
}
