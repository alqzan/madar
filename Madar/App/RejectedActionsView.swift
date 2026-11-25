import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarInbox

/// B1-10: a widget, control or Siri action that the app refused for good used to be moved aside and never shown.
/// The entry stays available during a read failure so the user can retry from the same place.
struct RejectedActionsRow: View {
    let session: AppSession
    @State private var items: [PendingInbox.RejectedDelivery] = []
    @State private var readFailed = false
    @State private var updating = false
    #if DEBUG
    @State private var injectedReadFailure = false
    #endif
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Keep a host for the read task when the healthy list has no rows.
        VStack(spacing: 0) {
            if !items.isEmpty || readFailed {
                NavigationLink {
                    RejectedActionsPage(session: session, items: $items, readFailed: $readFailed, updating: $updating)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90").font(.system(size: 18)).frame(width: 28).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(MadarTypography.body().bold())
                            Text(readFailed ? "تعذّرت قراءة الطلبات. افتح الصفحة لإعادة المحاولة." : "طلبات من الودجة أو الاختصارات رفضها التطبيق")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.left").font(.footnote).foregroundStyle(theme.secondaryInk)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("settings-rejected-actions")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !updating else { return }
            updating = true
            defer { updating = false }
            do {
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if !injectedReadFailure, environment["MADAR_UI_REJECTED_READ_FAIL_ONCE"] == "1",
                   environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                    injectedReadFailure = true
                    throw CocoaError(.fileReadUnknown)
                }
                #endif
                let listed = try await session.rejectedActions()
                guard !Task.isCancelled else { return }
                items = listed
                readFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                readFailed = true
            }
        }
    }

    private var title: String {
        guard !readFailed else { return "إجراءات لم تُطبَّق" }
        let digits = MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)
        return "إجراءات لم تُطبَّق (\(digits.string(items.count)))"
    }
}

private struct RejectedActionsPage: View {
    let session: AppSession
    @Binding var items: [PendingInbox.RejectedDelivery]
    @Binding var readFailed: Bool
    @Binding var updating: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsPage(title: "إجراءات لم تُطبَّق") {
            if readFailed {
                Text("تعذّرت قراءة الطلبات.")
                    .font(MadarTypography.body()).accessibilityIdentifier("rejected-actions-read-failure")
                Button("أعد قراءة الطلبات") { Task { await refresh() } }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(updating).accessibilityIdentifier("rejected-actions-reload")
            } else {
                Text("هذه طلبات وصلت من الودجة أو الاختصارات ولم يقبلها التطبيق. أعد المحاولة أو تجاهلها.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
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
                    }.disabled(readFailed || updating)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 20))
            }
        }
    }

    private func act(_ item: PendingInbox.RejectedDelivery, retry: Bool) {
        guard !readFailed, !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            if retry { await session.retryRejectedAction(item) } else { await session.dismissRejectedAction(item) }
            await load()
        }
    }

    private func refresh() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        await load()
    }

    private func load() async {
        do {
            let listed = try await session.rejectedActions()
            items = listed
            readFailed = false
            if items.isEmpty { dismiss() }
        } catch {
            readFailed = true
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
    func rejectedActions() async throws -> [PendingInbox.RejectedDelivery] {
        let inbox = pendingInbox
        return try await Task.detached(priority: .utility) { try inbox.rejectedDeliveries() }.value
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
