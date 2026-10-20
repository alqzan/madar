import SwiftUI
import MadarDesign

struct DiaryVoiceControls: View {
    @Bindable var controller: DiaryVoiceController
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                DisclosureGroup((controller.language == "ar-SA" ? "العربية" : "الإنجليزية") + " · " + controller.runtimeDescription) { options }
                    .font(MadarTypography.caption())
            } else { options }
            DiaryVoiceFeedback(controller: controller)
        }
        .task(id: controller.language) { await controller.refreshLanguage() }
        .alert("يُرسل الصوت إلى Apple للتحويل", isPresented: $controller.needsConsent) {
            Button("موافق") { Task { await controller.consent(true) } }
            Button("لا، سجّل فقط", role: .cancel) { Task { await controller.consent(false) } }
        } message: { Text("التحويل على الجهاز غير متاح لهذه اللغة الآن. يمكنك إبقاء الصوت والكتابة دون إرساله. موافقتك لهذا الجهاز، ويمكن إلغاؤها من خصّص المذكرات.") }
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("لغة التسجيل", selection: $controller.language) { Text("العربية").tag("ar-SA"); Text("الإنجليزية").tag("en-US") }
                .pickerStyle(.segmented).disabled(controller.recording || controller.converting).accessibilityIdentifier("diary-voice-language")
            if !compact { Text(controller.runtimeDescription).font(MadarTypography.fine()) }
            if controller.canDownload {
                if let progress = controller.downloadProgress {
                    ProgressView("تُحمّل لغة الإملاء…", value: progress)
                    Button("ألغِ التحميل") { controller.cancelDownload() }.frame(minHeight: 44)
                } else { Button("حمّل لغة الإملاء") { controller.downloadLanguage() }.font(MadarTypography.caption()).frame(minHeight: 44) }
            }
        }
    }
}

/// Feedback stays available in the text editor even when its recording options are collapsed.
struct DiaryVoiceFeedback: View {
    let controller: DiaryVoiceController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !controller.message.isEmpty { Text(controller.message).font(MadarTypography.caption()).accessibilityIdentifier("diary-voice-status") }
            if !controller.partialText.isEmpty { Text(controller.partialText).font(DiaryType.writing).foregroundStyle(.secondary) }
            if controller.converting { Button("ألغِ التحويل؛ أبقِ الصوت") { controller.cancelConversion() }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("diary-voice-cancel") }
            if controller.pendingAudioCount > 0 { Button("أعد حفظ التسجيل في الصفحة") { Task { await controller.recoverRecordings() } }.frame(minHeight: 44).disabled(controller.savingAudio || controller.recording) }
            if controller.microphoneDenied { Button("افتح إعدادات الميكروفون") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(MadarTypography.caption()).frame(minHeight: 44) }
        }
    }
}
