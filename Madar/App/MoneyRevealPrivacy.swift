import SwiftUI

/// FB-45: a money screen that keeps its own «أظهر الأرقام» state hides the figures again when the app leaves the screen,
/// as the money home already does (`core.hideMoneyUntilTouch`).
extension View {
    func hidesMoneyInBackground(_ revealed: Binding<Bool>) -> some View { modifier(MoneyRevealReset(revealed: revealed)) }
}
private struct MoneyRevealReset: ViewModifier {
    @Binding var revealed: Bool
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
    }
}
