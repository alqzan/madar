import SwiftUI
import MadarDesign
import MadarPrayer

/// Keeps a failed read visible and retryable instead of presenting an empty prayer sheet.
struct PrayerSnapshotSheet<Content: View>: View {
    let revision: Int
    let isActive: Bool
    let load: () async throws -> PrayerSnapshot
    let close: () -> Void
    @ViewBuilder let content: (PrayerSnapshot) -> Content
    @Environment(\.roomTheme) private var theme
    @State private var snapshot: PrayerSnapshot?
    @State private var failed = false
    @State private var retryAttempt = 0
    @State private var isRefreshing = true

    var body: some View {
        Group {
            if let snapshot {
                // Keep the same stateful sheet in the view tree while a newer snapshot is read.
                content(snapshot)
                    .disabled(isRefreshing || failed)
                    .accessibilityHidden(isRefreshing || failed)
            } else if failed {
                failureView
            } else {
                ProgressView("تُفتح بيانات الصلاة…").frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.background)
            }
        }
        .overlay {
            if snapshot != nil, isRefreshing {
                ProgressView("تُحدّث بيانات الصلاة…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.background.opacity(0.96).ignoresSafeArea())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prayer-snapshot-refreshing")
            } else if snapshot != nil, failed {
                failureView
            }
        }
        .task(id: "\(revision)-\(retryAttempt)-\(isActive)") {
            guard isActive else { return }
            await reload()
        }
    }

    private var failureView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.clockwise").font(.system(size: 28)).foregroundStyle(theme.accent)
            Text("تعذّر تحميل بيانات الصلاة").font(MadarTypography.title())
            Text("حاول مرة أخرى لفتح هذه الصفحة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
            Button("أعد المحاولة") { retryAttempt &+= 1 }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("prayer-snapshot-retry")
            Button("إغلاق", action: close).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("prayer-snapshot-close")
        }
        .multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
    }

    private func reload() async {
        isRefreshing = true
        failed = false
        do {
            let value = try await load()
            try Task.checkCancellation()
            snapshot = value
            isRefreshing = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            isRefreshing = false
            failed = true
        }
    }
}
