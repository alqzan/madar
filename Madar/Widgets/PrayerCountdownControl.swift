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
        .description("يضع عدّاد الصلاة القادمة على شاشتك، إلا وقت الصلاة نفسها وساعات الهدوء.")
    }
}
