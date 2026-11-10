import SwiftUI
import MadarCore
import MadarDesign
@preconcurrency import UserNotifications

/// Batch 3 «صحة مدار» (owner, 10 Nov 2026: build them all): one read-only page that says whether the things Madar depends on
/// are in order: the last backup, widget actions waiting or refused, and notifications. It reads what other services own and writes nothing.
struct MadarHealthView: View {
    let session: AppSession
    @State private var health: MadarHealth?
    @State private var lastBackup: Date?
    @State private var dataBytes: Int?
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    private var digits: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }

    var body: some View {
        SettingsPage(title: "صحة مدار") {
            if let health {
                verdict(health)
                VStack(spacing: 0) {
                    row("externaldrive", "النسخة الاحتياطية", backupLine(health.backup), attention: !isFresh(health.backup), id: "health-backup") {
                        if let lastBackup { MadarDateLabel(session.dateLabels(GregorianDay.containing(lastBackup, in: session.activePlace.timeZone))) }
                    }
                    Divider().overlay(theme.line)
                    row("arrow.triangle.2.circlepath", "طلبات الودجة والاختصارات", actionsLine(health), attention: health.rejectedActions > 0, id: "health-actions")
                    Divider().overlay(theme.line)
                    row("bell.badge", "الإشعارات", health.notificationsAllowed ? "مسموحة" : "متوقفة من إعدادات الجهاز؛ لن تصلك تذكيرات الغرف", attention: !health.notificationsAllowed, id: "health-notifications")
                    if let dataBytes {
                        Divider().overlay(theme.line)
                        row("internaldrive", "حجم بياناتك", "نحو " + sizeText(dataBytes), attention: false, id: "health-size")
                    }
                }.background(theme.surface, in: .rect(cornerRadius: 20))
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) { await load() }
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
    private func actionsLine(_ health: MadarHealth) -> String {
        if health.rejectedActions > 0 { return "\(digits.string(health.rejectedActions)) لم تُطبَّق؛ راجعها من الصفحة الرئيسية للإعدادات" }
        if health.pendingActions > 0 { return "\(digits.string(health.pendingActions)) تنتظر دورها وتُطبَّق وحدها" }
        return "لا شيء ينتظر"
    }
    private func sizeText(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1 { return "أقل من ميغابايت" }
        return digits.localized(String(format: "%.0f", megabytes)) + " ميغابايت"
    }

    @MainActor private func load() async {
        let status = try? await session.backupService?.status()
        lastBackup = status?.lastSuccess; dataBytes = status?.estimatedBytes
        let pending = (try? session.pendingInbox.unacknowledgedCommandIDs().count) ?? 0
        let rejected = await session.rejectedActions().count
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        health = MadarHealth(lastBackup: lastBackup, now: session.prayerNow(), pendingActions: pending, rejectedActions: rejected, notificationsAllowed: allowed)
    }
}
