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

struct MoneyExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alqzan.madar2.money-expense") {
            ControlWidgetButton(action: OpenMoneyExpenseIntent()) { Label("مصروف", systemImage: "plus.circle") }
        }.displayName("مصروف").description("يفتح تسجيل مصروف، دون عرض رصيدك.")
    }
}
struct OpenMihbaraRoomIntent:AppIntent {
    static let title:LocalizedStringResource="افتح المحبرة"
    static let supportedModes:IntentModes = .foreground
    func perform() async throws->some IntentResult & OpensIntent {
        .result(opensIntent:OpenURLIntent(URL(string:"madar://mihbara")!))
    }
}
struct MihbaraRoomControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"com.alqzan.madar2.mihbara-open") {
            ControlWidgetButton(action:OpenMihbaraRoomIntent()){Label("المحبرة",systemImage:"book.closed")}
        }.displayName("المحبرة").description("يفتح رفّك ومكتبك في المحبرة.")
    }
}
