import MadarCore
import MadarDesign
import PhotosUI
import SwiftUI
import UIKit

/// 10 Nov owner: writing in the diary is direct. One quiet field at the foot of today's page — type and send, pick a photo, change a line or write
/// after one right here. The full page (voice, camera, files) is one tap away and shares the same draft, so nothing typed is lost.
struct DiaryInlineComposer: View {
    @Bindable var app: AppSession
    @Binding var insertAt: Date?
    @Binding var anchor: String?
    @Binding var edit: DiaryLineEdit?
    @Binding var focusTick: Int
    /// True while the full writing page is open; when it closes the shared draft is read again.
    let editorOpen: Bool
    let openEditor: () -> Void
    let saved: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var text = ""
    @State private var editText = ""
    @State private var draftID = UUID()
    @State private var hasDraftRecord = false
    @State private var draftDay = "today"
    @State private var draftWritingDay: GregorianDay?
    @State private var saving = false
    @State private var failure: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var service: AppDiaryService { AppDiaryService(app: app, clock: { app.prayerNow() }) }
    private var field: Binding<String> { edit == nil ? $text : $editText }
    private var trimmed: String { field.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !saving && (edit == nil || editText != edit?.text) }

    var body: some View {
        VStack(spacing: 6) {
            if edit != nil || (insertAt != nil && anchor != nil) { chip }
            if let failure {
                Text(failure).font(MadarTypography.fine()).foregroundStyle(theme.color("late")).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diary-inline-failure")
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text")).disabled(edit != nil || saving)
                    .accessibilityLabel("أضف صورة").accessibilityIdentifier("diary-inline-photo")
                TextField(edit != nil ? "عدّل السطر…" : "اكتب ما تيسّر…", text: field, axis: .vertical)
                    .font(DiaryType.writing).lineLimit(1...5).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                    .background(theme.surface, in: .rect(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 0.7) }
                    .accessibilityIdentifier("diary-inline-field")
                if trimmed.isEmpty {
                    Button {
                        Task { await keepDraft(); openEditor() }
                    } label: {
                        Image(systemName: "mic").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                        .accessibilityLabel("الورقة الكاملة: صوت وكاميرا وملفات").accessibilityIdentifier("diary-day-write")
                } else {
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                            .foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .circle)
                            .contentShape(Circle())
                    }.buttonStyle(.madarPlain).disabled(!canSend)
                        .accessibilityLabel(edit != nil ? "احفظ التعديل" : "أضف إلى الصفحة").accessibilityIdentifier("diary-inline-send")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(theme.background)
        .task(id: editorOpen) { if !editorOpen { await loadDraft() } }
        .onChange(of: text) { _, _ in if edit == nil { scheduleDraft() } }
        .onChange(of: edit) { _, value in if let value { editText = value.text; focused = true } }
        .onChange(of: focusTick) { _, _ in focused = true }
        .onChange(of: photo) { _, item in if let item { Task { await addPhoto(item) } } }
    }

    private var chip: some View {
        HStack(spacing: 8) {
            Text(edit != nil ? "تعدّل هذا السطر" : "بعد: «" + (anchor ?? "") + "»")
                .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).lineLimit(1)
            Spacer(minLength: 4)
            Button { edit = nil; insertAt = nil; anchor = nil; editText = "" } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 36, height: 30).contentShape(Rectangle())
            }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                .accessibilityLabel("ألغِ").accessibilityIdentifier("diary-inline-chip-clear")
        }.padding(.horizontal, 6)
    }

    private func loadDraft() async {
        do {
            if let draft = try service.draft(margin: nil) {
                draftID = draft.id; hasDraftRecord = true; text = draft.text; draftDay = draft.day; draftWritingDay = draft.writingDay
            } else { hasDraftRecord = false; text = ""; draftID = UUID(); draftDay = "today"; draftWritingDay = nil }
        } catch { failure = madarUserMessage(error) }
        loaded = true
    }
    private func currentWritingDay() throws -> GregorianDay {
        if let draftWritingDay { return draftWritingDay }
        return try service.currentDay()
    }
    private func scheduleDraft() {
        guard loaded, !saving else { return }
        draftTask?.cancel()
        draftTask = Task {
            do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation(); try await persistDraft() }
            catch is CancellationError {} catch { failure = madarUserMessage(error) }
        }
    }
    private func persistDraft() async throws {
        guard hasDraftRecord || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await service.saveDraft(id: draftID, text: text, day: draftDay, margin: nil, writingDay: try currentWritingDay())
        hasDraftRecord = true
    }
    private func keepDraft() async {
        draftTask?.cancel()
        do { try await persistDraft() } catch { failure = madarUserMessage(error) }
    }
    private func send() async {
        guard canSend else { return }
        saving = true; failure = nil; draftTask?.cancel()
        defer { saving = false }
        do {
            if let edit {
                try await service.edit(edit.id, text: editText)
                self.edit = nil; editText = ""
            } else {
                try await persistDraft()
                var payload: [String: MadarCore.JSONValue] = ["id": .string(draftID.uuidString)]
                if let insertAt, draftDay == "today", insertAt < app.prayerNow() { payload["at"] = .number(insertAt.timeIntervalSince1970) }
                try await app.executeDiaryCommand("diary.commitDraft", payload: payload, id: draftID)
                text = ""; hasDraftRecord = false; draftID = UUID(); draftDay = "today"; draftWritingDay = nil
                insertAt = nil; anchor = nil
            }
            saved()
        } catch { failure = madarUserMessage(error) }
    }
    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let copy = DiaryPhotoLibrary.smallCopy(of: data) else {
                failure = "تعذّر فتح الصورة."; return
            }
            let writingDay = try service.currentDay()
            try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: writingDay)
            failure = nil; saved()
        } catch { failure = madarUserMessage(error) }
    }
}
