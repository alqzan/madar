import SwiftUI
import MadarCore
import MadarDesign

/// RD1 · editing a written line. Before the freeze it is corrected in place; after it the original stays and the
/// page marks the line «عُدّل». Both are undoable.
struct DiaryLineEdit: Identifiable, Equatable { let id: String; let text: String }

struct DiaryLineEditSheet: View {
    @Bindable var app: AppSession
    let edit: DiaryLineEdit
    let saved: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failure: String?
    @State private var saving = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("إن كان اليوم قد أُغلق، يبقى نصّك الأول محفوظًا ويظهر السطر بعلامة «عُدّل».").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                TextEditor(text: $text).font(DiaryType.writing).scrollContentBackground(.hidden).focused($focused)
                    .padding(12).background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }
                    .accessibilityIdentifier("diary-line-edit-text")
                if let failure { Text(failure).font(MadarTypography.body()).foregroundStyle(theme.color("late")) }
            }.padding(18).background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("عدّل السطر").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { if text == edit.text { dismiss() } else { confirmDiscard = true } }.accessibilityIdentifier("diary-line-edit-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("احفظ") { Task { saving = true; defer { saving = false }
                            do { try await AppDiaryService(app: app).edit(edit.id, text: text); saved(); dismiss() } catch { failure = madarUserMessage(error) } } }
                            .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == edit.text).accessibilityIdentifier("diary-line-edit-save")
                    }
                }.toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .onAppear { text = edit.text; focused = true }
                // A typed change is not lost to a stray swipe or cancel.
                .interactiveDismissDisabled(text != edit.text || saving)
                .alert("تتجاهل تعديلك؟", isPresented: $confirmDiscard) {
                    Button("تجاهل التعديل", role: .destructive) { dismiss() }
                    Button("أكمل التعديل", role: .cancel) {}
                }
        }
    }
}

struct DiaryOriginalSheet: View {
    let text: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("النص كما كُتب أول مرة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                Text(text).font(DiaryType.writing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-line-original")
            }.padding(22)
        }.background(theme.background).foregroundStyle(theme.ink)
    }
}
