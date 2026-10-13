import AppIntents
import SwiftUI
import WidgetKit

struct PrayerLogControl: ControlWidget {
    static let kind = "com.alqzan.madar2.prayer-log"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: PrayerLogControlConfiguration.self) { configuration in
            ControlWidgetButton(
                action: LogConfiguredPrayerControlIntent(
                    prayer: configuration.prayer,
                    status: configuration.status,
                    fridayKind: configuration.fridayKind
                )
            ) {
                Label {
                    Text(controlLabel(configuration))
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
        .displayName("سجّل الصلاة")
        .description("سجّل صلاة وحالة تختارهما عند إضافة التحكم.")
        .promptsForUserConfiguration()
    }

    private func controlLabel(_ configuration: PrayerLogControlConfiguration) -> String {
        guard let prayer = configuration.prayer, let status = configuration.status else { return "اختر الصلاة" }
        let fridayKind: String
        if prayer == .dhuhr, let kind = configuration.fridayKind { fridayKind = " " + kind.arabicName }
        else { fridayKind = "" }
        return "\(prayer.arabicName) \(status.arabicName)\(fridayKind)"
    }
}
