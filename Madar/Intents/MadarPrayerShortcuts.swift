import AppIntents

struct MadarPrayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPrayerIntent(),
            phrases: ["سجّل صلاة في \(.applicationName)", "سجّل صلاتي في \(.applicationName)"],
            shortTitle: "سجّل صلاة",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: StartPrayerActivityIntent(),
            phrases: ["ابدأ عداد الصلاة في \(.applicationName)", "تابع الصلاة القادمة في \(.applicationName)"],
            shortTitle: "عدّاد الصلاة",
            systemImageName: "timer"
        )
    }
}
