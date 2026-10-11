import SwiftUI
import UIKit

/// A non-key window in the exact hosting scene; app sheets remain below it.
@MainActor final class ScenePrivacyPresenter {
    let controller: MadarLockController
    private(set) weak var scene: UIWindowScene?
    private(set) var coverWindow: UIWindow?
    private weak var hostWindow: UIWindow?
    private var hiddenAccessibility: [(UIWindow, Bool)] = []
    private var notifications: [NSObjectProtocol] = []
    private var stateID: UUID?
    private var activity: UIActivityViewController?
    private var activityID: UUID?
    private let activationState: @MainActor (UIWindowScene) -> UIScene.ActivationState
    init(controller: MadarLockController,
         activationState: @escaping @MainActor (UIWindowScene) -> UIScene.ActivationState = { $0.activationState }) {
        self.controller = controller; self.activationState = activationState
    }
    func attach(to window: UIWindow) {
        guard let owningScene = window.windowScene else { return }
        guard scene !== owningScene else { hostWindow = window; return }
        detach(invalidate: false); scene = owningScene; hostWindow = window
        let cover = NonKeyPrivacyWindow(windowScene: owningScene)
        cover.windowLevel = .alert + 1
        cover.rootViewController = UIHostingController(rootView: ScenePrivacyCover(controller: controller))
        cover.accessibilityIdentifier = "scene-privacy-cover"
        coverWindow = cover
        stateID = controller.observeState { [weak self] in self?.synchronize() }
        observe(UIWindowScene.willDeactivateNotification, phase: .inactive)
        observe(UIScene.didEnterBackgroundNotification, phase: .background)
        observe(UIScene.didActivateNotification, phase: .active)
        notifications.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: owningScene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.detach() }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.transition(.background) }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: .madarPrivacyScopeChanged, object: nil, queue: .main) { [weak self] note in
            // Notification's object/userInfo are not Sendable. Snapshot only values
            // before the synchronous main-actor boundary; never transfer the note.
            let sourceID = (note.object as? MadarLockController).map(ObjectIdentifier.init)
            guard let raw = note.userInfo?["scope"] as? String,
                  let scope = MadarLockScope(rawValue: raw) else { return }
            MainActor.assumeIsolated {
                guard let self, sourceID != ObjectIdentifier(self.controller) else { return }
                self.coverNow(); self.controller.receiveScope(scope)
            }
        })
        for name in [Notification.Name.madarPrivacyScopeWillChange, .madarPrivacyScopeChangeFailed] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sourceID = (note.object as? MadarLockController).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, sourceID != ObjectIdentifier(self.controller) else { return }
                    self.coverNow(); self.dismissActivity()
                    if name == .madarPrivacyScopeWillChange { self.controller.receiveScopeRevocation() }
                    else { self.controller.receiveScopeFailure() }
                }
            })
        }
        switch activationState(owningScene) {
        case .foregroundActive: transition(.active)
        case .foregroundInactive: transition(.inactive)
        case .background: transition(.background)
        case .unattached: transition(.background); controller.lock()
        @unknown default: transition(.background); controller.lock()
        }
        synchronize()
    }
    private func observe(_ name: Notification.Name, phase: ScenePhase) {
        notifications.append(NotificationCenter.default.addObserver(forName: name, object: scene, queue: .main) { [weak self] _ in
            // UIKit scene notifications are delivered on the main queue. The synchronous
            // prefix is the snapshot boundary: never put this cover behind a Task.
            MainActor.assumeIsolated { self?.transition(phase) }
        })
    }
    func transition(_ phase: ScenePhase) {
        if phase != .active { coverNow(); dismissActivity() }
        controller.sceneChanged(phase)
        synchronize()
    }
    private func coverNow() {
        guard let scene, let coverWindow else { return }
        for window in scene.windows where window !== coverWindow {
            if !hiddenAccessibility.contains(where: { $0.0 === window }) { hiddenAccessibility.append((window, window.accessibilityElementsHidden)) }
            window.accessibilityElementsHidden = true
        }
        coverWindow.isHidden = false
    }
    private func synchronize() {
        if controller.covered || !controller.canPresent(.app) { coverNow() }
        else {
            coverWindow?.isHidden = true
            for (window, previous) in hiddenAccessibility { window.accessibilityElementsHidden = previous }
            hiddenAccessibility.removeAll()
        }
    }
    func present(file: URL, authorization: PrivacyAuthorization) throws {
        try controller.validate(authorization)
        guard scene != nil, coverWindow?.isHidden == true, let hostWindow,
              hostWindow.windowScene === scene, var top = hostWindow.rootViewController,
              activity == nil else { throw PrivacyAuthorizationError.stale }
        while let presented = top.presentedViewController { top = presented }
        guard top.viewIfLoaded?.window === hostWindow else { throw PrivacyAuthorizationError.stale }
        let id = UUID(); let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = top.view
        share.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        share.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor in if self?.activityID == id { self?.activity = nil; self?.activityID = nil } }
        }
        activity = share; activityID = id
        top.present(share, animated: true)
    }
    private func dismissActivity() { activity?.dismiss(animated: false); activity = nil; activityID = nil }
    func detach(invalidate: Bool = true) {
        if invalidate { coverNow(); controller.disconnect() }
        dismissActivity()
        if let stateID { controller.removeObserver(stateID) }; stateID = nil
        for token in notifications { NotificationCenter.default.removeObserver(token) }; notifications.removeAll()
        for (window, previous) in hiddenAccessibility { window.accessibilityElementsHidden = previous }; hiddenAccessibility.removeAll()
        coverWindow?.isHidden = true; coverWindow?.rootViewController = nil; coverWindow = nil; scene = nil; hostWindow = nil
    }
}
private final class NonKeyPrivacyWindow: UIWindow { override var canBecomeKey: Bool { false } }
private struct ScenePrivacyCover: View {
    @Bindable var controller: MadarLockController
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.closed").font(.largeTitle).accessibilityHidden(true)
            Text("محتوى مدار محمي")
            if !controller.authenticating { Button("افتح القفل") { controller.authenticate(for: .app) }.accessibilityIdentifier("scene-lock-authenticate") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
    }
}
struct ScenePrivacyBridge: UIViewRepresentable {
    let session: AppSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> SceneProbe {
        let view = SceneProbe(); view.attached = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }; return view
    }
    func updateUIView(_ uiView: SceneProbe, context: Context) { if let window = uiView.window { context.coordinator.attach(window) } }
    static func dismantleUIView(_ uiView: SceneProbe, coordinator: Coordinator) { coordinator.presenter?.detach() }
    @MainActor final class Coordinator {
        weak var session: AppSession?
        var presenter: ScenePrivacyPresenter?
        init(session: AppSession) { self.session = session }
        func attach(_ window: UIWindow) {
            guard let session, let lock = session.lockController else { return }
            if presenter == nil { presenter = ScenePrivacyPresenter(controller: lock); session.privacyPresenter = presenter }
            presenter?.attach(to: window)
        }
    }
}
final class SceneProbe: UIView {
    var attached: (@MainActor (UIWindow) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if let window { attached?(window) } }
}
