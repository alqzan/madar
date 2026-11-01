import SwiftUI

/// AU-97: the one lock for a sheet while it saves. Each sheet used to pair `.interactiveDismissDisabled(saving)` with
/// `.disabled(saving)` on its close button, and missing one of the two was a card of its own (M5-V03 to V26). The lock
/// also reads the session's write counter, so a sheet whose own flag is late or missing still waits for a running save.
extension View {
    /// Swipe-down waits while `saving`, while any write the user started is running, or while `draft` holds unsaved
    /// input. Close controls marked with `madarWaitsForSave()` dim for the saving part only, so a draft can still be closed.
    func madarSheetLock(saving: Bool, draft: Bool = false) -> some View {
        modifier(MadarSheetLock(saving: saving, draft: draft))
    }
    /// A close or cancel control that waits for the sheet's running save.
    func madarWaitsForSave() -> some View { modifier(MadarWaitsForSave()) }
}

private struct MadarSheetLock: ViewModifier {
    let saving: Bool
    let draft: Bool
    @Environment(AppSession.self) private var app: AppSession?
    func body(content: Content) -> some View {
        let writing = saving || app?.userWriteInProgress == true
        content.environment(\.madarSheetSaving, writing).interactiveDismissDisabled(writing || draft)
    }
}

private struct MadarWaitsForSave: ViewModifier {
    @Environment(\.madarSheetSaving) private var saving
    func body(content: Content) -> some View { content.disabled(saving) }
}

extension EnvironmentValues {
    @Entry var madarSheetSaving = false
}
