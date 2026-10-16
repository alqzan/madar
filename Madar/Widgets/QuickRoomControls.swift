import WidgetKit
import AppIntents
import SwiftUI

struct DiaryWriterControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"com.alqzan.madar2.diary-write") {
            ControlWidgetButton(action:OpenDiaryWriterIntent()){Label("سطر سريع",image:"MadarDiary")}
        }.displayName("سطر سريع").description("يفتح الكتابة مباشرة، دون عرض مذكراتك.")
    }
}
struct HabitsRoomControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"com.alqzan.madar2.habits-open") {
            ControlWidgetButton(action:OpenHabitsRoomIntent()){Label("عاداتك",image:"MadarHabits")}
        }.displayName("عاداتك").description("يفتح عاداتك لتختار ما تسجّله.")
    }
}
