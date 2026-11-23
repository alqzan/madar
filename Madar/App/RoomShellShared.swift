import SwiftUI
import MadarDesign

// Room-shell pieces shared by the iPhone/iPad shell (`TabShell`) and the Mac window (`MacRootView`).

struct FoundationTab: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}


/// Only built destinations enter this shell. Future rooms supply destinations at their milestone.
/// RL8: the one tab bar is the native glass `TabView`; no alternate style is built.
extension EnvironmentValues {
    /// Counts how many times this room has come to the front. Rooms stay alive between visits (no rebuild on every tap), so a room
    /// that refreshed itself on appear refreshes on `.task(id: roomVisit)` instead.
    @Entry var roomVisit = 0
    /// False for a room kept alive behind the one on screen: its refresh triggers (a write elsewhere, a return to the app) wait,
    /// and `roomVisit` catches it up when it comes to the front, so four rooms never refresh at once.
    @Entry var isFrontRoom = true
}


extension View {
    /// A screen's own undo line: while it shows, the root one stays away, so a removal never shows two.
    func hostsUndo(_ session: AppSession) -> some View {
        onAppear { session.localUndoHosts += 1 }.onDisappear { session.localUndoHosts = max(0, session.localUndoHosts - 1) }
    }
}


extension View {
    /// Hides the room accessory while this full-screen flow is on screen (see `TabShell.accessorized`).
    func hidesRoomAccessory(_ session: AppSession, id: String) -> some View {
        modifier(RoomAccessoryHider(session: session, id: id))
    }
}


private struct RoomAccessoryHider: ViewModifier {
    let session: AppSession
    let id: String
    func body(content: Content) -> some View {
        content
        .onAppear { session.accessoryHiders.insert(id) }
        .onDisappear { session.accessoryHiders.remove(id) }
    }
}


extension View {
    /// AU-36/37: the root alert cannot show over a sheet, so a sheet carries its own for `session.errorMessage`.
    func madarSheetErrorAlert(_ session: AppSession) -> some View { modifier(SheetErrorAlert(session: session)) }
}

private struct SheetErrorAlert: ViewModifier {
    let session: AppSession
    @State private var id = UUID()
    func body(content: Content) -> some View {
        let readingSaveCoordinator = MihbaraReadingSaveCoordinator.forSession(session)
        content
        .onAppear { session.sheetErrorHosts.removeAll { $0 == id }; session.sheetErrorHosts.append(id) }
        .onDisappear { session.sheetErrorHosts.removeAll { $0 == id } }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { session.errorMessage != nil && session.sheetErrorHosts.last == id }, set: { if !$0 { session.errorMessage = nil } })) {
            if readingSaveCoordinator.canRetryPendingWriteErrorNow {
                Button("إعادة المحاولة") {
                    readingSaveCoordinator.dismissPendingWriteError()
                    readingSaveCoordinator.retryPendingWritesNow()
                }
                .accessibilityIdentifier("mihbara-reading-save-retry")
            }
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }
}


/// Owner, 5 Nov 2026: the chip that jumped up beside the finger after every tap is gone. A removal (the only thing that still offers undo)
/// shows one quiet glass line just above the bottom bar; it glides in, leaves on its own after four seconds, and a swipe down puts it away.
struct AnchoredUndo: View {
    let session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack {
            Spacer()
            if session.undoToastVisible && session.localUndoHosts == 0 {
                session.undoToast()
                .fixedSize(horizontal: dynamicType.isAccessibilitySize ? false : true, vertical: false)
                .padding(.bottom, session.tabBarHeight + 10)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(session.undoToastVisible)
    }
}


extension View {
    /// Owner, 6 Nov 2026: «مشطوف». The hard cut under the clock is gone: the system's soft scroll edge fades the ink out under the status bar.
    func madarTopClipped() -> some View { scrollEdgeEffectStyle(.soft, for: .top) }
}


extension AppSession {
    /// The one undo pill every screen shows (mockup «أ», owner 22 Nov 2026): the latest removal with its draining line,
    /// and the one before it peeking behind.
    func undoToast(undo customUndo: (() -> Void)? = nil) -> UndoToast {
        UndoToast(message: undoMessage, undo: customUndo ?? { [weak self] in self?.undo() }, dismiss: { [weak self] in self?.hideUndoToast() },
                  seconds: Self.undoToastSeconds, tokenID: undoToken?.id, earlier: undoEarlierMessage)
    }
}
