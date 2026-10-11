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

@MainActor @Observable final class MadarLockController {
    private(set) var scope: MadarLockScope
    private(set) var covered = false
    private(set) var authenticating = false
    private(set) var statusMessage: String?
    private(set) var unlocked: Set<MadarProtectedFeature> = []
    private(set) var redactionFailed = false
    private let service: any MadarLockService
    private var context: LAContext?
    private var backgroundAt: Date?
    private var authorizedFeature: MadarProtectedFeature?
    private var privacyGeneration = 0
    private var lifecycleEpoch = 0
    private var isSceneActive = true
    private var redactionTask: Task<Void, Error>?
    init(scope: MadarLockScope, service: any MadarLockService) { self.scope = scope; self.service = service }
    private func requiredFeature(for feature: MadarProtectedFeature) -> MadarProtectedFeature? {
        if feature == .privateNote { return .privateNote }
        if scope == .app { return .app }
        if scope == .notesOnly && (feature == .notes || feature == .export) { return .notes }
        return nil
    }
    func requiresProtection(_ feature: MadarProtectedFeature) -> Bool { requiredFeature(for: feature) != nil }
    func canPresent(_ feature: MadarProtectedFeature) -> Bool {
        guard let required = requiredFeature(for: feature) else { return true }
        guard !covered, !redactionFailed else { return false }
        return unlocked.contains(required)
    }
    func authenticate(for feature: MadarProtectedFeature) {
        guard !authenticating, !covered else { return }
        guard let required = requiredFeature(for: feature) else { return }
        if redactionFailed { enqueueRedaction() }
        authenticating = true; statusMessage = nil
        let local = LAContext(); local.localizedCancelTitle = "إلغاء"
        local.localizedFallbackTitle = "رمز الجهاز"
        context = local
        let generation = privacyGeneration
        Task { [self] in
            defer { authenticating = false; context = nil }
            var error: NSError?
            guard local.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                statusMessage = "مصادقة الجهاز غير متاحة. تبقى البيانات مقفلة."; return
            }
            do {
                let verified = try await local.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح بيانات مدار المحمية")
                guard verified, !covered, privacyGeneration == generation else { return }
                try await redactionTask?.value
                try await service.authorizeAccess(to: feature)
                guard !covered, privacyGeneration == generation else {
                    try await service.redactProtectedData(); return
                }
                unlocked.insert(required); authorizedFeature = feature; redactionFailed = false
            } catch {
                unlocked.remove(required)
                statusMessage = "لم يُفتح القفل. يمكنك المحاولة مرة أخرى."
            }
        }
    }
    func lock() {
        privacyGeneration += 1; context?.invalidate(); unlocked.removeAll(); authorizedFeature = nil
        enqueueRedaction()
        Task { [self] in
            do { try await redactionTask?.value; redactionFailed = false }
            catch { redactionFailed = true; statusMessage = "تعذّر تحديث حماية البيانات. تبقى البيانات مقفلة." }
        }
    }
    func changeScope(_ newScope: MadarLockScope) async throws {
        privacyGeneration += 1; context?.invalidate(); unlocked.removeAll(); authorizedFeature = nil
        covered = true
        do {
            enqueueRedaction()
            try await redactionTask?.value
            try await service.privacyScopeDidChange(to: newScope)
            scope = newScope; redactionFailed = false; covered = !isSceneActive
        } catch {
            redactionFailed = true; statusMessage = "لم يتغيّر القفل؛ حماية البيانات باقية."; throw error
        }
    }
    private func enqueueRedaction() {
        let previous = redactionTask
        redactionTask = Task { [service] in
            // Even after a previous failure, attempt a fresh redaction and remain fail-closed on its failure.
            _ = try? await previous?.value
            try await service.redactProtectedData()
        }
    }
    func sceneChanged(_ phase: ScenePhase, now: Date = Date()) {
        lifecycleEpoch += 1
        isSceneActive = phase == .active
        switch phase {
        case .inactive:
            covered = true
            // Keep the one-minute authorization lease, but purge rendered rows and snippets immediately.
            enqueueRedaction()
            Task { [self] in
                do { try await redactionTask?.value }
                catch { redactionFailed = true; unlocked.removeAll() }
            }
        case .background:
            covered = true; backgroundAt = now; privacyGeneration += 1
            context?.invalidate()
        case .active:
            let expired = backgroundAt.map { now.timeIntervalSince($0) >= 60 } ?? false
            backgroundAt = nil
            if expired { lock(); covered = false; return }
            guard !redactionFailed, let authorizedFeature, requiredFeature(for: authorizedFeature).map({ unlocked.contains($0) }) == true else { covered = false; return }
            let epoch = lifecycleEpoch
            Task { [self] in
                do {
                    try await redactionTask?.value
                    guard isSceneActive, lifecycleEpoch == epoch else { return }
                    try await service.authorizeAccess(to: authorizedFeature)
                    guard isSceneActive, lifecycleEpoch == epoch else { enqueueRedaction(); return }
                    covered = false
                } catch { unlocked.removeAll(); redactionFailed = true; statusMessage = "تعذّر فتح البيانات المحمية." }
            }
        @unknown default: covered = true; lock()
        }
    }
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
