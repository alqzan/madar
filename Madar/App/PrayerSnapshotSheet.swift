import SwiftUI
import MadarDesign
import MadarPrayer

/// Keeps a failed read visible and retryable instead of presenting an empty prayer sheet.
struct PrayerSnapshotSheet<Content: View>: View {
    let revision: Int
    let load: () throws -> PrayerSnapshot
    let close: () -> Void
    @ViewBuilder let content: (PrayerSnapshot) -> Content
    @Environment(\.roomTheme) private var theme
    @State private var snapshot: PrayerSnapshot?
    @State private var failed = false

    var body: some View {
        Group {
            if let snapshot { content(snapshot) }
            else if failed {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 28)).foregroundStyle(theme.accent)
                    Text("تعذّر تحميل بيانات الصلاة").font(MadarTypography.title())
                    Text("حاول مرة أخرى لفتح هذه الصفحة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    Button("أعد المحاولة", action: reload).buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("prayer-snapshot-retry")
                    Button("إغلاق", action: close).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("prayer-snapshot-close")
                }
                .multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
            } else { ProgressView("تُفتح بيانات الصلاة…").frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.background) }
        }
        .task(id: revision) { reload() }
    }

    private func reload() {
        do { snapshot = try load(); failed = false }
        catch { snapshot = nil; failed = true }
    }
}
