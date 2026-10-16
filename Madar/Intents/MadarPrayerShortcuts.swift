import AppIntents

/// The app's single AppShortcutsProvider: Siri phrases for v1 actions of built rooms only (§9).
struct MadarPrayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPrayerIntent(),
            phrases: ["سجّل صلاة في \(.applicationName)", "سجّل صلاتي في \(.applicationName)", "صلّيت \(\.$prayer) في \(.applicationName)"],
            shortTitle: "سجّل صلاة",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["التقط في \(.applicationName)", "سجّل في \(.applicationName)"],
            shortTitle: "التقاط",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: AddDiaryLineIntent(),
            phrases: ["أضف سطرًا في \(.applicationName)", "اكتب في مذكرات \(.applicationName)"],
            shortTitle: "سطر في المذكرات",
            systemImageName: "pencil.line"
        )
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: ["أتممت \(\.$habit) في \(.applicationName)", "أتمّ عادة في \(.applicationName)"],
            shortTitle: "أتمّ عادة",
            systemImageName: "circle.dashed.inset.filled"
        )
        AppShortcut(
            intent: StartQuranSessionIntent(),
            phrases: ["ابدأ \(\.$step) في \(.applicationName)", "ابدأ جلسة القرآن في \(.applicationName)"],
            shortTitle: "جلسة القرآن",
            systemImageName: "book"
        )
        AppShortcut(
            intent: OpenRoomIntent(),
            phrases: ["افتح \(\.$room) في \(.applicationName)"],
            shortTitle: "افتح غرفة",
            systemImageName: "door.left.hand.open"
        )
        AppShortcut(
            intent: StartPrayerActivityIntent(),
            phrases: ["ابدأ عداد الصلاة في \(.applicationName)", "تابع الصلاة القادمة في \(.applicationName)"],
            shortTitle: "عدّاد الصلاة",
            systemImageName: "timer"
        )
    }
}
