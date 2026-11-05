import SwiftUI
import MadarDesign

struct MihbaraPageNoteSheet: View {
    let app: AppSession
    let draft: MihbaraWordCardState
    let palette: MihbaraReaderPalette
    let pageText: String?
    let save: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var rootBlockerID = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("إلغاء") { dismiss() }.font(MadarTypography.body()).frame(minHeight: 44)
                    .accessibilityIdentifier("mihbara-note-cancel")
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1",
                   ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                    Button("الجذر") { app.open(URL(string: "madar://mihbara")!) }
                        .font(MadarTypography.fine()).frame(minHeight: 44)
                        .accessibilityIdentifier("mihbara-page-note-root-route")
                }
#endif
                Spacer()
                Text("ملاحظة على الصفحة").font(MadarTypography.section())
                Spacer()
                Button("احفظ") {
                    saving = true
                    Task { if !(await save(text.trimmingCharacters(in: .whitespacesAndNewlines))) { saving = false } }
                }
                .font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body)).frame(minHeight: 44)
                .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                .accessibilityIdentifier("mihbara-note-save")
            }
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(palette.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.paragraphText).font(.custom("Amiri-Regular", size: 17, relativeTo: .body)).foregroundStyle(palette.ink).lineLimit(4).lineSpacing(4)
                    if let pageText { Text(pageText).font(MadarTypography.fine()).foregroundStyle(palette.ink2) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("ما الذي أوقفك هنا؟").font(MadarTypography.body()).foregroundStyle(palette.ink2).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $text).font(MadarTypography.body()).foregroundStyle(palette.ink).scrollContentBackground(.hidden).focused($focused)
                    .accessibilityLabel("نص الملاحظة").accessibilityIdentifier("mihbara-note-text")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.ink.opacity(palette.isDark ? 0.10 : 0.05)))
            // AU-95: past the limit «احفظ» dims; say why, as the notebook editor does.
            if text.count > 2000 {
                Text("اختصر الملاحظة إلى ألفي حرف حتى تُحفظ.").font(MadarTypography.fine()).foregroundStyle(palette.ink)
                    .accessibilityIdentifier("mihbara-note-too-long")
            } else {
                Text("تُحفظ في حاشية هذا الكتاب مربوطة بهذه الفقرة.").font(MadarTypography.fine()).foregroundStyle(palette.ink2)
            }
        }
        .padding(20)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        // A swipe never throws away a written note; «إلغاء» stays the deliberate way out.
        .interactiveDismissDisabled(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .onAppear { focused = true }
        .onChange(of: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving, initial: true) { _, blocked in app.setMihbaraRootDraftBlocker(rootBlockerID, active: blocked) }
        .onDisappear { app.setMihbaraRootDraftBlocker(rootBlockerID, active: false) }
    }
}
