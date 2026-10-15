import AppIntents
import SwiftUI
import WidgetKit

struct PrayerCountdownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alqzan.madar2.prayer-countdown") {
            ControlWidgetButton(action: StartPrayerActivityIntent()) {
                Label("عدّاد الصلاة", systemImage: "timer")
            }
        }
        .displayName("عدّاد الصلاة")
        .description("ابدأ متابعة الصلاة القادمة مع احترام الحرمة والهدوء وميزانية الجهاز.")
    }
}
