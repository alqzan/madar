import SwiftUI
import MadarCore
import MadarDesign
@preconcurrency import UserNotifications

/// Batch 3 «صحة مدار» (owner, 10 Nov 2026: build them all): one read-only page that says whether the things Madar depends on
/// are in order: the last backup, widget actions waiting or refused, and notifications. It reads what other services own and writes nothing.
struct MadarHealthView: View {
    let session: AppSession
    @State private var report: Report?
    @State private var attempt = 0
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    private var digits: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }

    private struct Report {
        let backup: (lastSuccess: Date?, estimatedBytes: Int?)?
        let actions: (pending: Int, rejected: Int)?
        let notifications: NotificationState
    }

    private enum NotificationState {
        case unavailable, offInMadar, needsPermission, offInSystem, allowed

        var detail: String {
            switch self {
            case .unavailable: ""
            case .offInMadar: "أوقفت تذكيرات هذا الجهاز من إعدادات مدار"
            case .needsPermission: "اسمح بالإشعارات من إعدادات مدار لتصلك التذكيرات"
            case .offInSystem: "متوقفة من إعدادات الجهاز؛ لن تصلك تذكيرات الغرف"
            case .allowed: "مسموحة"
            }
        }

        var requiresAttention: Bool { self != .unavailable && self != .allowed }
    }

    var body: some View {
        SettingsPage(title: "صحة مدار") {
            if let report {
                let health = report.backup.map {
                    MadarHealth(lastBackup: $0.lastSuccess, now: session.prayerNow(),
                                pendingActions: report.actions?.pending ?? 0, rejectedActions: report.actions?.rejected ?? 0,
                                notificationsAllowed: !report.notifications.requiresAttention)
                }
                if let health, report.actions != nil {
                    verdict(health)
                } else {
                    MadarCard {
                        Text("تعذّر التحقق من بعض المعلومات").font(MadarTypography.section())
                            .accessibilityIdentifier("health-read-incomplete")
                        Button("أعد المحاولة") { attempt += 1 }
                            .frame(minHeight: 44).accessibilityIdentifier("health-retry")
                    }
                }
                VStack(spacing: 0) {
                    row("externaldrive", "النسخة الاحتياطية", health.map { backupLine($0.backup) } ?? "تعذّرت قراءة حالة النسخ",
                        attention: health.map { !isFresh($0.backup) } ?? true, id: "health-backup") {
                        if let lastBackup = report.backup?.lastSuccess { MadarDateLabel(session.dateLabels(GregorianDay.containing(lastBackup, in: session.activePlace.timeZone))) }
                    }
                    Divider().overlay(theme.line)
                    row("arrow.triangle.2.circlepath", "طلبات الودجة والاختصارات",
                        report.actions.map { actionsLine(pending: $0.pending, rejected: $0.rejected) } ?? "تعذّرت قراءة حالة الطلبات",
                        attention: report.actions.map { $0.rejected > 0 } ?? true, id: "health-actions")
                    if report.notifications != .unavailable {
                        Divider().overlay(theme.line)
                        row("bell.badge", "الإشعارات", report.notifications.detail,
                            attention: report.notifications.requiresAttention, id: "health-notifications")
                    }
                    if let dataBytes = report.backup?.estimatedBytes {
                        Divider().overlay(theme.line)
                        row("internaldrive", "حجم بياناتك على الجهاز", "نحو " + sizeText(dataBytes), attention: false, id: "health-size")
                    }
                }.background(theme.surface, in: .rect(cornerRadius: 20))
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(scenePhase)-\(attempt)-\(ObjectIdentifier(session.container))-\(session.bool("notif.thisDeviceReminders"))") {
            if scenePhase == .active { await load() }
        }
        .accessibilityIdentifier("health-page")
    }

    private func isFresh(_ backup: MadarHealth.Backup) -> Bool { if case .fresh = backup { true } else { false } }

    private func verdict(_ health: MadarHealth) -> some View {
        HStack(spacing: 12) {
            Image(systemName: health.isHealthy ? "checkmark.seal.fill" : "exclamationmark.circle.fill").font(.title2)
                .foregroundStyle(health.isHealthy ? theme.accent : theme.ink)
            Text(health.isHealthy ? "كل شيء على ما يرام" : health.attentionCount == 1 ? "أمر واحد يحتاج نظرة" : "\(digits.string(health.attentionCount)) أمور تحتاج نظرة")
                .font(MadarTypography.section())
            Spacer()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine).accessibilityIdentifier("health-verdict")
    }

    private func row<Extra: View>(_ symbol: String, _ title: String, _ detail: String, attention: Bool, id: String, @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: attention ? "exclamationmark.circle" : symbol).font(.system(size: 18)).frame(width: 28).foregroundStyle(attention ? theme.ink : theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MadarTypography.body().bold())
                Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    private func backupLine(_ backup: MadarHealth.Backup) -> String {
        switch backup {
        case .never: "لا توجد نسخة بعد؛ افتح «النسخ والاستعادة» لتبدأ"
        case .fresh(let days): days == 0 ? "نُسخت بياناتك اليوم" : days == 1 ? "آخر نسخة أمس" : "آخر نسخة قبل \(digits.string(days)) \(days <= 10 ? "أيام" : "يومًا")"
        case .stale(let days): "مرّ على آخر نسخة \(digits.string(days)) يومًا؛ جهّز نسخة جديدة"
        }
    }
    private func actionsLine(pending: Int, rejected: Int) -> String {
        if rejected > 0 { return "\(digits.string(rejected)) لم تُطبَّق؛ راجعها من الصفحة الرئيسية للإعدادات" }
        if pending > 0 { return "\(digits.string(pending)) تنتظر دورها وتُطبَّق وحدها" }
        return "لا شيء ينتظر"
    }
    private func sizeText(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1 { return "أقل من ميغابايت" }
        return digits.localized(String(format: "%.0f", megabytes)) + " ميغابايت"
    }

    @MainActor private func load() async {
        let inbox = session.pendingInbox
        let counts = Task.detached(priority: .utility) {
            (pending: try inbox.unacknowledgedCommandIDs().count, rejected: try inbox.rejectedDeliveries().count)
        }
        defer { counts.cancel() }
        let backup: (lastSuccess: Date?, estimatedBytes: Int?)?
        if let appBackup = session.backupService as? AppBackupService {
            backup = try? await appBackup.healthReading()
        } else if let status = try? await session.backupService?.status() {
            backup = (status.lastSuccess, status.estimatedBytes)
        } else {
            backup = nil
        }
        let notifications = await loadNotificationState()
        let actions = try? await counts.value
        guard !Task.isCancelled else { return }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if attempt == 0, env["MADAR_UI_HEALTH_FAIL_FIRST"] == "1",
           env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
            report = Report(backup: nil, actions: actions, notifications: notifications)
            return
        }
        #endif
        report = Report(backup: backup, actions: actions, notifications: notifications)
    }

    private func loadNotificationState() async -> NotificationState {
        guard MadarPlatform.hasNotifications else { return .unavailable }
        guard session.bool("notif.thisDeviceReminders") else { return .offInMadar }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .needsPermission
        default: return .offInSystem
        }
    }
}
