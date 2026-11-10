import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarInbox

/// B1-10: a widget, control or Siri action that the app refused for good used to be moved aside and never shown.
/// This row appears in the general settings only while at least one such action exists; the page lets the owner retry or drop each one.
struct RejectedActionsRow: View {
    let session: AppSession
    @State private var items: [PendingInbox.RejectedDelivery] = []
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !items.isEmpty {
                NavigationLink { RejectedActionsPage(session: session, items: $items) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90").font(.system(size: 18)).frame(width: 28).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("إجراءات لم تُطبَّق (\(MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi).string(items.count)))")
                                .font(MadarTypography.body().bold())
                            Text("طلبات من الودجة أو الاختصارات رفضها التطبيق").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.left").font(.footnote).foregroundStyle(theme.secondaryInk)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("settings-rejected-actions")
            }
        }
        .task(id: scenePhase) { items = await session.rejectedActions() }
    }
}

private struct RejectedActionsPage: View {
    let session: AppSession
    @Binding var items: [PendingInbox.RejectedDelivery]
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsPage(title: "إجراءات لم تُطبَّق") {
            Text("هذه طلبات وصلت من الودجة أو الاختصارات ولم يقبلها التطبيق. أعد المحاولة أو تجاهلها.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.title(item.commandName)).font(MadarTypography.body().bold())
                    if let issuedAt = item.issuedAt {
                        Text(session.dateLabels(GregorianDay.containing(issuedAt, in: session.activePlace.timeZone)).combined)
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    HStack(spacing: 12) {
                        if item.canRetry {
                            Button("أعد المحاولة") { act(item, retry: true) }.buttonStyle(.borderedProminent).tint(theme.accent)
                        }
                        Button("تجاهل", role: .destructive) { act(item, retry: false) }.buttonStyle(.bordered)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 20))
            }
        }
    }

    private func act(_ item: PendingInbox.RejectedDelivery, retry: Bool) {
        Task {
            if retry { await session.retryRejectedAction(item) } else { await session.dismissRejectedAction(item) }
            items = await session.rejectedActions()
            if items.isEmpty { dismiss() }
        }
    }

    static func title(_ name: String?) -> String {
        guard let name else { return "إجراء غير مقروء" }
        if name.hasPrefix("prayer.") { return "تسجيل صلاة" }
        if name.hasPrefix("habit.") { return "إجراء على عادة" }
        if name.hasPrefix("money.") || name.hasPrefix("expense.") { return "إجراء مالي" }
        if name.hasPrefix("quran.") { return "إجراء في القرآن" }
        return "إجراء من الودجة"
    }
}

extension AppSession {
    func rejectedActions() async -> [PendingInbox.RejectedDelivery] {
        let inbox = pendingInbox
        return await Task.detached { (try? inbox.rejectedDeliveries()) ?? [] }.value
    }
    func retryRejectedAction(_ item: PendingInbox.RejectedDelivery) async {
        let inbox = pendingInbox, name = item.fileName
        _ = await Task.detached { try? inbox.retryRejected(fileName: name) }.value
        _ = try? await drainInbox()
    }
    func dismissRejectedAction(_ item: PendingInbox.RejectedDelivery) async {
        let inbox = pendingInbox, name = item.fileName
        _ = await Task.detached { try? inbox.dismissRejected(fileName: name) }.value
    }
}
