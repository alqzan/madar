import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import MadarDesign

enum MadarLockScope: String, Sendable { case app, notesOnly, none
    // Read compatibility only: the owner removed the diary-only lock on 15 October.
    var effective: Self { self == .notesOnly ? .none : self }
}
enum MadarProtectedFeature: Hashable, Sendable { case app, notes, privateNote, export }

/// The adapter purges protected view models before returning and regenerates redacted external surfaces.
/// Protected rows are fetched only in authorizeAccess, after successful device authentication.
@MainActor protocol MadarLockService: AnyObject {
    func redactProtectedData() async throws
    func authorizeAccess(to feature: MadarProtectedFeature) async throws
    func privacyScopeDidChange(to scope: MadarLockScope) async throws
    func persistedPrivacyScope() throws -> MadarLockScope
}

@MainActor protocol MadarDeviceAuthenticator: AnyObject {
    func verify() async throws -> Bool
    func invalidate()
}
@MainActor final class SystemDeviceAuthenticator: MadarDeviceAuthenticator {
    private let context = LAContext()
    func verify() async throws -> Bool {
        context.localizedCancelTitle = "إلغاء"; context.localizedFallbackTitle = ""
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "افتح مدار")
        }
        // Owner 1 Nov: when Face ID is unavailable (permission off, no face, lockout) the iPhone passcode opens Madar, and only then.
        let code = (error as? LAError)?.code
        guard code == .biometryNotAvailable || code == .biometryNotEnrolled || code == .biometryLockout,
              context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { throw PrivacyAuthorizationError.refused }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "تعذّر Face ID، افتح مدار برمز iPhone")
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
    private let authorizationCommitBoundary: @MainActor () -> Void
    private var currentAuth: (UUID, any MadarDeviceAuthenticator)?
    private var authorizedFeatures: Set<MadarProtectedFeature> = []
    private var generation = 0
    private var epoch = 0
    private var phase: ScenePhase = .active
    var isSceneActive: Bool { phase == .active }
    private var disconnected = false
    private static var activeScopeRequest: UUID?
    private var scopeTransitionID: UUID?
    private var scopeTransitionPending: Bool { scopeTransitionID != nil }
    private var scopeReconciliationRequired = false
    private var scopePresentationRevoked = false
    private var redactionTask: Task<Void, Error>?
    private var activeRecoveryID: UUID?
    private var activeRecovery: Task<Void, Never>?
    private var activeWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var stateObservers: [UUID: @MainActor () -> Void] = [:]
    private var revokeObservers: [UUID: @MainActor (Bool) -> Void] = [:]
    init(scope: MadarLockScope, service: any MadarLockService, clock: @escaping @MainActor () -> Date = Date.init,
         authenticator: @escaping @MainActor () -> any MadarDeviceAuthenticator = { SystemDeviceAuthenticator() },
         authorizationCommitBoundary: @escaping @MainActor () -> Void = {}) {
        self.scope = scope.effective; self.service = service; self.clock = clock; self.authenticator = authenticator
        self.authorizationCommitBoundary = authorizationCommitBoundary
    }
    private func requiredFeature(for _: MadarProtectedFeature) -> MadarProtectedFeature? {
        if scope == .app { return .app }
        return nil
    }
    func requiresProtection(_ feature: MadarProtectedFeature) -> Bool { requiredFeature(for: feature) != nil }
    func canPresent(_ feature: MadarProtectedFeature) -> Bool {
        guard phase == .active, !disconnected, !covered, !redactionFailed, !scopeTransitionPending, !scopeReconciliationRequired else { return false }
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
        if let activeRecovery { await activeRecovery.value }
        guard phase == .active, !disconnected, !scopeTransitionPending else { throw PrivacyAuthorizationError.stale }
        guard currentAuth == nil else { throw PrivacyAuthorizationError.busy }
        if scopeReconciliationRequired {
            scope = try service.persistedPrivacyScope().effective; scopeReconciliationRequired = false
        }
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
            // Controlled host seam for the child-completion/caller-resumption
            // boundary. Production has no override and never skips the checks.
            authorizationCommitBoundary()
            try current()
            guard phase == .active, epoch == activeEpoch else {
                covered = true; revoke(cancelRequests: false); enqueueRedaction()
                throw PrivacyAuthorizationError.stale
            }
            unlocked.formUnion(needed); authorizedFeatures.formUnion(features); redactionFailed = false; scopePresentationRevoked = false; covered = false; notify()
            return .init(owner: identity, generation: generation, epoch: epoch, features: features)
        } catch {
            if currentAuth?.0 == id {
                statusMessage = "لم يفتح Face ID. حاول مرة أخرى."
                if !(error is PrivacyAuthorizationError) && !(error is CancellationError) { redactionFailed = true; covered = true; notify() }
            }
            throw error
        }
    }
    @discardableResult func authenticate(for feature: MadarProtectedFeature) -> Bool {
        guard phase == .active, currentAuth == nil else { return false }
        Task { [self] in _ = try? await authorize([feature]) }
        return true
    }
    func lock() {
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        revoke(cancelRequests: true); enqueueRedaction(); recoverActive()
    }
    func changeScope(_ newScope: MadarLockScope) async throws {
        guard Self.activeScopeRequest == nil, !scopeTransitionPending else { throw PrivacyAuthorizationError.busy }
        // Scope persistence owns a separate request, not the scene authorization
        // generation. Serialize writers even if the initiating scene disconnects.
        let id = UUID(); Self.activeScopeRequest = id; scopeTransitionID = id
        scopePresentationRevoked = true
        defer { if Self.activeScopeRequest == id { Self.activeScopeRequest = nil } }
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        revoke(cancelRequests: true)
        // Every scene revokes before the first suspension, independently of persistence.
        NotificationCenter.default.post(name: .madarPrivacyScopeWillChange, object: self, userInfo: ["requestID": id])
        enqueueRedaction()
        do {
            try await redactionTask?.value
            try Task.checkCancellation()
            try await service.privacyScopeDidChange(to: newScope.effective)
            let persisted = try service.persistedPrivacyScope()
            if scopeTransitionID == id {
                finishScopeTransition(id, persisted: persisted, failed: false)
                NotificationCenter.default.post(name: .madarPrivacyScopeChanged, object: self, userInfo: ["requestID": id, "scope": persisted.rawValue])
            }
            try Task.checkCancellation()
        } catch {
            if scopeTransitionID == id {
                // Persistence may throw after saving (e.g. snapshot refresh). Read
                // the actual setting; an unreadable scope stays closed until retry.
                let persisted = try? service.persistedPrivacyScope()
                finishScopeTransition(id, persisted: persisted, failed: true)
                var info: [String: Any] = ["requestID": id]
                if let persisted { info["scope"] = persisted.rawValue }
                NotificationCenter.default.post(name: .madarPrivacyScopeChangeFailed, object: self, userInfo: info)
            }
            throw error
        }
    }
    func receiveScopeRevocation(_ id: UUID) {
        scopeTransitionID = id
        scopePresentationRevoked = true
        generation += 1; invalidateAuth(); unlocked.removeAll(); authorizedFeatures.removeAll(); covered = true
        revoke(cancelRequests: true); enqueueRedaction()
    }
    func finishScopeTransition(_ id: UUID, persisted: MadarLockScope?, failed: Bool) {
        guard scopeTransitionID == id else { return }
        scopeTransitionID = nil; scopeReconciliationRequired = persisted == nil
        if let persisted { scope = persisted.effective }
        covered = true; redactionFailed = failed || persisted == nil; notify()
    }
    func disconnect() { disconnected = true; epoch += 1; phase = .background; lock() }
    func sceneChanged(_ next: ScenePhase, now _: Date? = nil) {
        guard !disconnected, next != phase else { return }
        epoch += 1; phase = next
        switch next {
        case .inactive:
            covered = true; revoke(cancelRequests: false); enqueueRedaction()
        case .background:
            covered = true; generation += 1; invalidateAuth()
            revoke(cancelRequests: true); enqueueRedaction()
        case .active:
            let waiters = activeWaiters; activeWaiters.removeAll(); for waiter in waiters.values { waiter.resume() }
            recoverActive()
        @unknown default: lock()
        }
    }
    private func recoverActive() {
        guard phase == .active, !disconnected, !scopeTransitionPending, !scopeReconciliationRequired,
              !scopePresentationRevoked, currentAuth == nil, activeRecovery == nil else { return }
        let stamp = generation, activeEpoch = epoch
        let id = UUID(); activeRecoveryID = id
        activeRecovery = Task { [self] in
            defer {
                if activeRecoveryID == id { activeRecoveryID = nil; activeRecovery = nil }
            }
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
                guard generation == stamp, epoch == activeEpoch, currentAuth == nil else { return }
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
    @State private var promptedAtStartup = false
    var body: some View {
        // One container, not a transparent Group: modifiers on the gate (its startup
        // task and the scene privacy bridge behind it) must keep their identity when
        // the branch flips between locked and unlocked. A Group hands them to each
        // branch, so unlocking dismantled the bridge and disconnected this controller.
        ZStack {
            if !controller.requiresProtection(feature) {
                // The unprotected shell stays mounted across system prompts and app switching.
                // Protected child gates still remove their content and the adapter purges its rows.
                content()
                    .allowsHitTesting(!controller.covered)
                    .accessibilityHidden(controller.covered)
                    .overlay { if controller.covered && controller.redactionFailed { privacyCover } }
            } else if controller.canPresent(feature) { content() }
            else { lockedContent }
        }
        .task {
            attemptStartupAuthentication()
        }
        .onChange(of: controller.isSceneActive) { _, isActive in
            guard isActive, !promptedAtStartup else { return }
            attemptStartupAuthentication()
        }
    }
    private func attemptStartupAuthentication() {
        guard !promptedAtStartup,
              controller.requiresProtection(feature),
              !controller.canPresent(feature),
              !controller.authenticating else { return }
        promptedAtStartup = controller.authenticate(for: feature)
    }
    private var privacyCover: some View {
        ZStack { theme.background.ignoresSafeArea(); Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(theme.ink) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
    private var lockedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
            Text("مدار مقفل").font(MadarTypography.title())
            if let message = controller.statusMessage { Text(message).font(MadarTypography.caption()) }
            if controller.authenticating { ProgressView("يتحقق Face ID…") }
            else if !controller.covered {
                Button("افتح مدار") { controller.authenticate(for: feature) }
                    .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("lock-authenticate")
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(theme.ink).background(theme.background)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("protected-lock-screen")
    }
}
