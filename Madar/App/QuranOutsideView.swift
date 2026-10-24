import SwiftUI
import MadarDesign
import MadarSnapshots

struct QuranOutsideView: View {
    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var value: QuranWidgetSnapshot?
    @State private var error: String?
    private var app: AppSession { service.app }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Button("رجوع", action: close).frame(minHeight: 44); Spacer(); Text("التذكير والودجات").font(MadarTypography.cardTitle()) }
                if let value {
                    if app.string("quran.wirdReminder") != "off" { reminder(QuranReminderCopy.title, detail: QuranReminderCopy.body, timing: reminderTitle) }
                    if app.bool("quran.lateReminder") { reminder(QuranReminderCopy.lateTitle, detail: QuranReminderCopy.lateBody, timing: "بعد العصر") }
                    HStack(spacing: 14) { preview(value, .coverage, height: 170); preview(value, .path, height: 170) }
                    preview(value, .week, height: 150)
                }
                MadarCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("التذكير").font(MadarTypography.section())
                        HStack {
                            Text("تذكير الورد"); Spacer()
                            Menu(reminderTitle) {
                                ForEach([("afterFajr", "بعد الفجر"), ("afterAsr", "بعد العصر"), ("afterIsha", "بعد العشاء"), ("off", "بلا")], id: \.0) { key, title in
                                    Button(title) { app.set(.string(key), key: "quran.wirdReminder") }.accessibilityIdentifier("quran-reminder-" + key)
                                }
                            }.frame(minHeight: 44).accessibilityIdentifier("quran-reminder-choice")
                        }
                        Toggle("المتأخر قبل أن يبعد", isOn: Binding(get: { app.bool("quran.lateReminder") }, set: { app.set(.bool($0), key: "quran.lateReminder") }))
                            .accessibilityIdentifier("quran-late-reminder")
                        Text("تصل التذكيرات بعد انتهاء حرمة الصلاة، وضمن ميزانية هذا الجهاز.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Toggle("تذكيرات هذا الجهاز", isOn: Binding(get: { app.bool("notif.thisDeviceReminders") }, set: { app.set(.bool($0), key: "notif.thisDeviceReminders") }))
                        if !app.notificationsAuthorized {
                            Button(app.shouldOpenNotificationSettings ? "افتح إعدادات الإشعارات" : "اسمح بالتذكيرات") {
                                if app.shouldOpenNotificationSettings { app.openPrayerNotificationSettings() } else { app.requestPrayerNotificationPermission() }
                            }.frame(minHeight: 44)
                        }
                        Button("أعِد المتفق عليه") { app.reset(["quran.wirdReminder", "quran.lateReminder"]) }.frame(minHeight: 44).accessibilityIdentifier("quran-reminder-reset")
                    }.font(MadarTypography.body()).disabled(app.settingsWriteInProgress)
                }
                Text("أضف «القرآن» من معرض ودجات iOS، واختر قالب «في صدرك» أو «مسار اليوم» أو «الحفظ والمراجعة». الحجم يختاره النظام. تحكّم «مؤقّت المراجعة» يفتح جلستك، والمؤقّت في طريقة الجلسة.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let error { Text(error).font(MadarTypography.caption()) }
            }.padding(16)
        }.foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea()).tint(theme.color("review"))
            .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo).accessibilityIdentifier("quran-reminder-undo") } }
            .task { do { value = try service.widgetSnapshot().payload } catch { self.error = quranUserMessage(error) } }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
    }
    private var reminderTitle: String { ["afterFajr": "بعد الفجر", "afterAsr": "بعد العصر", "afterIsha": "بعد العشاء", "off": "بلا"][app.string("quran.wirdReminder")] ?? "بعد الفجر" }
    private func reminder(_ title: String, detail: String, timing: String) -> some View {
        HStack(spacing: 12) {
            Text("م").font(.custom("Amiri-Bold", size: 28)).frame(width: 44, height: 44).foregroundStyle(theme.onAccent).background(theme.color("cover"), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(MadarTypography.section()); Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            Spacer(minLength: 0); Text(timing).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }.padding(14).background(theme.surface, in: .rect(cornerRadius: 24))
    }
    private func preview(_ value: QuranWidgetSnapshot, _ template: QuranWidgetTemplate, height: CGFloat) -> some View {
        QuranWidgetContent(snapshot: value, template: template).padding(14).frame(maxWidth: .infinity).frame(height: height)
            .background(theme.surface, in: .rect(cornerRadius: 24)).accessibilityIdentifier("quran-widget-preview-" + template.rawValue)
    }
}
